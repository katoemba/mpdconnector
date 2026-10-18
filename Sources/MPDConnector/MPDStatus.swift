//
//  MPDStatus.swift
//  MPDConnector_iOS
//
// The MIT License (MIT)
//
// Copyright (c) 2018 Katoemba Software
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of
// this software and associated documentation files (the "Software"), to deal in
// the Software without restriction, including without limitation the rights to
// use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
// the Software, and to permit persons to whom the Software is furnished to do so,
// subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
// FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
// COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
// IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

import Foundation
import ConnectorProtocol
import SwiftMPD
import Combine
import SwiftUI
import os
import os.log

public class MPDStatus: StatusProtocol, @unchecked Sendable {
    static let logger = os.Logger(subsystem: "com.katoemba.mpdconnector", category: "status")

    /// Connection to a MPD Player
    private var identification = ""
    /// Changed from the player settings while the monitoring loops read it, hence the lock (see SharedState).
    private let attributesLock: OSAllocatedUnfairLock<MPDPlayer.PlayerAttributes>
    private var attributes: MPDPlayer.PlayerAttributes {
        attributesLock.withLockUnchecked { $0 }
    }

    /// ConectionStatus for the player
    private var mpdIdleConnector: SwiftMPD.MPDConnector?
    private var mpdConnector: SwiftMPD.MPDConnector
    
    /// The state that the monitoring loops write and the rest of the app reads, at any moment and
    /// from any thread. It is guarded by a lock: a PlayerStatus is a large struct holding strings
    /// and arrays, so reading one while it is being replaced hands out a copy with broken
    /// reference counts, which crashes later on when that copy is released.
    private struct SharedState {
        var playerStatus = PlayerStatus()
        var connectionStatus = ConnectionStatus.unknown
        var lastKnownElapsedTime = 0
        var lastKnownElapsedTimeRecorded = Date()
    }
    private let sharedState = OSAllocatedUnfairLock(initialState: SharedState())

    public private(set) var statusStream = ConnectorProtocol.AsyncValueBroadcaster<ConnectorProtocol.PlayerStatus>()
    public var playerStatus: PlayerStatus {
        get {
            sharedState.withLock { $0.playerStatus }
        }
        set {
            sharedState.withLock { $0.playerStatus = newValue }
            send(newValue)
        }
    }

    public private(set) var connectionStatusStream = ConnectorProtocol.AsyncValueBroadcaster<ConnectorProtocol.ConnectionStatus>()
    public var connectionStatus: ConnectionStatus {
        get {
            sharedState.withLock { $0.connectionStatus }
        }
        set {
            setConnectionStatus(newValue)
        }
    }

    private var elapsedTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?

    /// Whether status monitoring is running. Deliberately separate from `connectionStatus`, which
    /// tells whether the player is actually reachable and can therefore change while monitoring.
    private var isMonitoring = false
    private var connectionObservers = Set<AnyCancellable>()

    /// Seconds to wait before re-establishing a lost monitoring connection, per consecutive
    /// failure. The last value is used for all further attempts.
    private static let reconnectDelays: [UInt64] = [1, 2, 5, 10, 20, 30]

    public init(attributes: MPDPlayer.PlayerAttributes,
                identification: String = "NoID",
                mpdConnector: SwiftMPD.MPDConnector,
                mpdIdleConnector: SwiftMPD.MPDConnector? = nil) {
        self.attributesLock = OSAllocatedUnfairLock(uncheckedState: attributes)
        self.identification = identification
        self.mpdConnector = mpdConnector
        self.mpdIdleConnector = mpdIdleConnector
    }

    /// The player's settings changed (e.g. its type or cover art settings).
    func updateAttributes(_ attributes: MPDPlayer.PlayerAttributes) {
        attributesLock.withLockUnchecked { $0 = attributes }
    }

    /// Cleanup connection object
    deinit {
        elapsedTask?.cancel()
        idleTask?.cancel()
        disconnectFromMPD()
    }

    public func start() {
        guard isMonitoring == false, let mpdIdleConnector else {
            return
        }

        isMonitoring = true
        observeConnectionState()
        startIdleLoop(with: mpdIdleConnector)
        startElapsedLoop()
    }

    private func startElapsedLoop() {
        elapsedTask = Task { [weak self] in
            var counter = 0
            while (Task.isCancelled == false) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)

                guard let self else { return }

                self.updateElapsedTime()

                counter += 1
                if counter > 5 {
                    counter = 0
                    if let playerStatus = try? await playerStatus() {
                        self.store(playerStatus)
                    }
                }
            }
        }
    }
    
    /// Stop monitoring status changes on a player, and close the active connections
    public func stop() {
        isMonitoring = false
        connectionObservers.removeAll()
        elapsedTask?.cancel()
        elapsedTask = nil
        idleTask?.cancel()
        idleTask = nil
        setConnectionStatus(.offline)

        // Note that statusStream is deliberately left in place: subscribers are long-lived and
        // must keep receiving updates when monitoring is started again. Closing the connections
        // also breaks the pending idle command, so the idle loop stops even if it was parked.
        disconnectFromMPD()
    }

    /// Monitor the player for changes.
    ///
    /// Every iteration reads the status and then waits for the player to report a change. Any
    /// failure is recoverable: the connection is dropped so that the next command establishes a
    /// fresh one, and the loop retries with a backoff until it succeeds or monitoring is stopped.
    /// Failing to recover here means no more status updates at all, so the loop must never end
    /// on its own.
    private func startIdleLoop(with idleConnector: SwiftMPD.MPDConnector) {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            var failures = 0

            while Task.isCancelled == false {
                do {
                    guard let self else { return }

                    let playerStatus = try await self.playerStatus(connector: idleConnector)
                    self.store(playerStatus)
                    self.setConnectionStatus(.online)
                    failures = 0
                }
                catch {
                    guard Task.isCancelled == false, let self else { return }

                    failures += 1
                    await self.recoverFromMonitoringFailure(error, connector: idleConnector, attempt: failures)
                    continue
                }

                do {
                    // No reference to self is held while waiting here, which can take arbitrarily
                    // long on a player that isn't doing anything.
                    _ = try await idleConnector.status.idle([.player, .playlist, .mixer, .output, .options])
                }
                catch {
                    guard Task.isCancelled == false, let self else { return }

                    failures += 1
                    await self.recoverFromMonitoringFailure(error, connector: idleConnector, attempt: failures)
                }
            }
        }
    }

    /// Report the player as unreachable and drop the monitoring connection, so the next command
    /// on it connects again. Closing is essential: a connection can be half-open, or the player
    /// can still be in idle mode after an idle command timed out, and in both cases only a fresh
    /// connection recovers.
    private func recoverFromMonitoringFailure(_ error: Error, connector: SwiftMPD.MPDConnector, attempt: Int) async {
        MPDStatus.logger.info("Status monitoring on \(self.identification, privacy: .public) failed (attempt \(attempt)): \(error.localizedDescription, privacy: .public)")

        setConnectionStatus(.offline)
        await connector.closeConnection()

        let delay = MPDStatus.reconnectDelays[min(attempt - 1, MPDStatus.reconnectDelays.count - 1)]
        try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
    }

    /// Notice a connection that is dropped underneath us (the player is switched off or reboots,
    /// the network changes, iOS tears down sockets while the app is suspended), so the player is
    /// reported as offline right away instead of only when the idle loop notices.
    /// Only the monitoring connection is observed, as that is the one that is meant to stay open;
    /// the command connection is closed and reopened as part of normal operation.
    private func observeConnectionState() {
        connectionObservers.removeAll()

        mpdIdleConnector?.connectedStatus
            .sink { [weak self] connected in
                guard let self, self.isMonitoring, connected == false else { return }

                self.setConnectionStatus(.offline)
            }
            .store(in: &connectionObservers)
    }

    private func setConnectionStatus(_ status: ConnectionStatus) {
        let changed = sharedState.withLock { state -> Bool in
            guard state.connectionStatus != status else { return false }

            state.connectionStatus = status
            return true
        }
        guard changed else { return }

        Task {
            await connectionStatusStream.send(status)
        }
    }

    /// Store a status as freshly read from the player, and use it as the anchor from which the
    /// elapsed time is counted up in between reads.
    private func store(_ playerStatus: PlayerStatus) {
        sharedState.withLock { state in
            state.playerStatus = playerStatus
            state.lastKnownElapsedTimeRecorded = Date()
            state.lastKnownElapsedTime = playerStatus.time.elapsedTime
        }
        send(playerStatus)
    }

    /// Advance the elapsed time of the current status while the player is playing, so that the
    /// position keeps running in between two reads from the player. Read and write happen under
    /// a single lock, as the idle loop can replace the status at any moment.
    private func updateElapsedTime() {
        let updated: PlayerStatus? = sharedState.withLock { state in
            guard state.playerStatus.playing.playPauseMode == .playing else { return nil }

            var playerStatus = PlayerStatus(state.playerStatus)
            playerStatus.time.elapsedTime = state.lastKnownElapsedTime + Int(Date().timeIntervalSince(state.lastKnownElapsedTimeRecorded))
            state.playerStatus = playerStatus

            return playerStatus
        }

        guard let updated else { return }
        send(updated)
    }

    private func send(_ playerStatus: PlayerStatus) {
        Task {
            await statusStream.send(playerStatus)
        }
    }

    /// Swap in new connectors (for example after the user changes the password) without
    /// tearing down the existing status/connection streams that views are subscribed to.
    public func replaceConnectors(mpdConnector: SwiftMPD.MPDConnector, mpdIdleConnector: SwiftMPD.MPDConnector?) {
        let oldIdleConnector = self.mpdIdleConnector
        self.mpdConnector = mpdConnector
        self.mpdIdleConnector = mpdIdleConnector

        guard isMonitoring else { return }

        // Closing the old connection breaks the in-flight idle, so the previous loop exits.
        idleTask?.cancel()
        Task {
            await oldIdleConnector?.closeConnection()
        }

        observeConnectionState()
        if let mpdIdleConnector {
            startIdleLoop(with: mpdIdleConnector)
        }
    }
            
    public func playerStatus() async throws -> PlayerStatus {
        try await playerStatus(connector: nil)
    }
    
    /// Get the current status of a controller
    ///
    /// - Parameter connection: an active connection to a mpd player
    /// - Returns: a filled PlayerStatus struct
    private func playerStatus(connector: MPDConnector? = nil) async throws -> PlayerStatus {
        let connector = connector ?? mpdConnector
        let statusExecutor = connector.status.statusExecutor()
        let outputsExecutor = connector.output.outputsExecutor()
        let currentsongExecutor = connector.status.currentsongExecutor()

        try await connector.batchCommand([statusExecutor, outputsExecutor, currentsongExecutor])
        
        let status = try statusExecutor.processResults()
        let outputs = try outputsExecutor.processResults()
        let currentSong = try? currentsongExecutor.processResults()
        
        return PlayerStatus(from: status, currentSong: currentSong, outputs: outputs, attributes: attributes)
    }
    
    /// Get an array of songs from the playqueue.
    ///
    /// - Parameters
    ///   - start: the first song to fetch, zero-based.
    ///   - end: the last song to fetch, zero-based.
    /// Returns: an array of filled Songs objects.
    public func playqueueSongs(start: Int, end: Int) async -> [Song] {
        guard start >= 0, start < end else {
            return []
        }
        
        let attributes = self.attributes
        do {
            let mpdSongs = try await mpdConnector.queue.playlistinfo(range: start...end)
            
            var position = start
            let songs = mpdSongs.map {
                var song = Song(mpdSong: $0, attributes: attributes, forcePlayqueueId: true)
                song.position = position
                
                position += 1
                return song
            }
            return songs
        }
        catch {
            return []
        }
    }
    
    /// Get a block of song id's from the playqueue
    ///
    /// - Parameters:
    ///   - start: the start position of the requested block
    ///   - end: the end position of the requested block
    /// - Returns: Array of tuples of playqueue position and track id, not guaranteed to have the same number of songs as requested.
    public func playqueueSongIds(start: Int, end: Int) async -> [(Int, String)] {
        guard start >= 0, start < end else {
            return []
        }

        do {
            let posids = try await mpdConnector.queue.plchangesposid(version: 0)

            return posids
                .filter {
                    $0.cpos >= start && $0.cpos < end
                }
                .map {
                    ($0.cpos, "\($0.id)")
                }
        }
        catch {
            return []
        }
    }
    
    /// Close the connections to the player. Any following command reconnects, so this is also the
    /// way to get rid of connections that have gone stale, for example because the app was
    /// suspended and the sockets were torn down while it wasn't running.
    public func disconnectFromMPD() {
        let connector = mpdConnector
        let idleConnector = mpdIdleConnector

        Task {
            await idleConnector?.closeConnection()
            await connector.closeConnection()
        }
    }

    /// Force a refresh of the status.
    public func forceStatusRefresh() {
        Task {
            if let playerStatus = try? await playerStatus() {
                store(playerStatus)
            }
        }
    }
    
    /// Manually set a status for test purposes
    public func testSetPlayerStatus(playerStatus: PlayerStatus) {
        self.playerStatus = playerStatus
    }
}

extension PlayerStatus {
    public init(from: SwiftMPD.MPDStatus.Status, currentSong: SwiftMPD.MPDSong?, outputs: [SwiftMPD.MPDOutput.Output], attributes: MPDPlayer.PlayerAttributes) {
        self.init()
        
        if let currentSong {
            self.currentSong = Song(mpdSong: currentSong, attributes: attributes)
        }
        else {
            self.currentSong = Song()
        }
        lastUpdateTime = Date()
        time.elapsedTime = Int(from.elapsed ?? 0)
        if let duration = from.duration {
            time.trackTime = Int(duration)
        }
        else if self.currentSong.length > 0 {
            time.trackTime = self.currentSong.length
        }
        
        if let volume = from.volume, volume >= 0 {
            self.volume = Float(volume) / 100.0
            volumeEnabled = true
        }
        else {
            self.volume = 0.5
            volumeEnabled = false
        }

        switch from.state {
        case .pause:
            playing.playPauseMode = .paused
        case .play:
            playing.playPauseMode = .playing
        case .stop:
            playing.playPauseMode = .stopped
        }
        switch from.consume {
        case .off:
            playing.consumeMode = .off
        case .on:
            playing.consumeMode = .on
        case .oneshot:
            playing.consumeMode = .on
        }
        playing.randomMode = (from.random == .on) ? .on : .off
        switch from.repeat {
        case .off:
            playing.repeatMode = .off
        case .on:
            if from.single == .off {
                playing.repeatMode = .all
            }
            else {
                playing.repeatMode = .single
            }
        }
        
        self.playqueue.songIndex = from.song ?? -1
        self.playqueue.length = from.playlistlength ?? 0
        self.playqueue.version = (from.playlist == nil) ? -1 : Int(from.playlist!)
        
        self.quality = QualityStatus(audioFormat: from.audioFormat)
        if let bitrate = from.bitrate {
            self.quality.rawBitrate = UInt32(bitrate * 1000)
        }
        if let fileExtension = currentSong?.file.split(separator: ".").last {
            self.quality.filetype = String(fileExtension)
        }
        
        self.outputs = outputs.map { Output($0) }
        
        self.lastUpdateTime = Date()
    }
}

extension Output {
    public init(_ from: MPDOutput.Output) {
        self.init()
        
        id = "\(from.id)"
        name = from.name
        enabled = from.enabled
    }
}

extension QualityStatus {
    public init(audioFormat: String) {
        self.init(audioFormat: AudioFormat(audioFormat))
    }
    
    public init(audioFormat: AudioFormat) {
        self.init()
        
        rawBitrate = nil
        if let channels = audioFormat.channels {
            rawChannels = UInt32(channels)
        }
        if let samplerate = audioFormat.samplerate {
            rawSamplerate = UInt32(samplerate)
        }
        if let bits = audioFormat.bits {
            switch bits {
            case .eight:
                rawEncoding = .bits(8)
            case .sixteen:
                rawEncoding = .bits(16)
            case .twentyfour:
                rawEncoding = .bits(24)
            case .thirtytwo:
                rawEncoding = .bits(32)
            case .dsd:
                rawEncoding = .text("DSD")
            case .dsd64:
                rawEncoding = .text("DSD64")
            case .dsd128:
                rawEncoding = .text("DSD128")
            case .dsd256:
                rawEncoding = .text("DSD256")
            case .dsd512:
                rawEncoding = .text("DSD512")
            case .dsd1024:
                rawEncoding = .text("DSD1024")
            case .floatingpoint:
                rawEncoding = .text("Float")
            }
        }
    }
}

extension Song {
    public init(mpdSong: SwiftMPD.MPDSong, attributes: MPDPlayer.PlayerAttributes, forcePlayqueueId: Bool = false) {
        self.init()
        
        id = mpdSong.file
        if id.starts(with: "spotify:") {
            source = .Spotify
        }
        else if id.starts(with: "tunein:") {
            source = .TuneIn
        }
        else if id.starts(with: "podcast+") {
            source = .Podcast
        }
        else if id.starts(with: "http://") || id.starts(with: "https://") {
            source = .Radio
        }
        else {
            source = .Local
        }
        title = mpdSong.title ?? ""
        // Some mpd versions (on Bryston) don't pick up the title correctly for wav files.
        // In such case, get it from the file path.
        if title == "", source == .Local {
            let components = id.components(separatedBy: "/")
            if components.count >= 1 {
                let filename = components[components.count - 1]
                let filecomponents = filename.components(separatedBy: ".")
                if filecomponents.count >= 1 {
                    title = filecomponents[0]
                }
            }
        }
        album = mpdSong.album ?? ""
        // Some mpd versions (on Bryston) don't pick up the album correctly for wav files.
        // In such case, get it from the file path.
        if album == "", source == .Local {
            let components = id.components(separatedBy: "/")
            if components.count >= 2 {
                album = components[components.count - 2]
            }
        }
        artist = mpdSong.artist ?? ""
        // Some mpd versions (on Bryston) don't pick up the album correctly for wav files.
        // In such case, get it from the file path.
        if artist == "", source == .Local {
            let components = id.components(separatedBy: "/")
            if components.count >= 3 {
                artist = components[components.count - 3]
            }
        }
        albumartist = mpdSong.albumartist ?? ""
        composer = mpdSong.composer ?? ""
        conductor = mpdSong.conductor ?? ""
        genre = mpdSong.genre == nil ? [] : [mpdSong.genre!]
        length = Int(mpdSong.duration)
        if length == 0, let time = mpdSong.time {
            length = Int(time)
        }
        name = mpdSong.name ?? ""
        date = mpdSong.date ?? ""
        year = Int(String(date.prefix(4))) ?? 0
        performer = mpdSong.performer ?? ""
        comment = mpdSong.comment ?? ""
        
        track = Int(mpdSong.track ?? 0)
        if let components = mpdSong.disc?.components(separatedBy: .decimalDigits.inverted), components.count > 0 {
            disc = Int(components[0]) ?? 0
        }
        musicbrainzArtistId = mpdSong.musicbrainz_artistid ?? ""
        musicbrainzAlbumId = mpdSong.musicbrainz_albumid ?? ""
        musicbrainzAlbumArtistId = mpdSong.musicbrainz_albumartistid ?? ""
        musicbrainzTrackId = mpdSong.musicbrainz_trackid ?? ""
        musicbrainzReleaseId = mpdSong.musicbrainz_releasetrackid ?? ""
        originalDate = mpdSong.originaldate ?? ""
        sortArtist = mpdSong.artistsort ?? ""
        sortAlbumArtist = mpdSong.albumartistsort ?? ""
        sortAlbum = mpdSong.albumsort ?? ""
        lastModified = mpdSong.lastmodified ?? Date()
        if let id = mpdSong.id {
            playqueueId = "\(id)"
        }
        else if forcePlayqueueId {
            playqueueId = UUID().uuidString
        }
        
        var filetype = ""
        let components = id.components(separatedBy: "/")
        if components.count >= 1 {
            let filename = components[components.count - 1]
            let filecomponents = filename.components(separatedBy: ".")
            if filecomponents.count >= 2 {
                filetype = filecomponents[filecomponents.count - 1]
            }
        }
        
        quality = QualityStatus(audioFormat: mpdSong.audioFormat)
        quality.filetype = filetype
        
        location = mpdSong.file
                
        // Get a sensible coverURI
        guard source == .Local else { return }
        
        let pathSections = id.split(separator: "/")
        var newPath = ""
        if pathSections.count > 0 {
            for index in 0..<(pathSections.count - 1) {
                newPath.append(contentsOf: pathSections[index])
                newPath.append(contentsOf: "/")
            }
        }
       
        let host = attributes.host.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? ""
        if attributes.type == .moodeaudio && attributes.useHttpCoverArt == true {
            let coverString = mpdSong.file.removingPercentEncoding?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
            coverURI = CoverURI.fullPathURI("http://\(host)/coverart.php/\(coverString)")
        }
        else if attributes.type == .bryston && attributes.useHttpCoverArt == true {
            let path = "\(newPath)\(attributes.coverFilename)".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
            coverURI = CoverURI.fullPathURI("http://\(host)/music/\(path)")
        }
        else {
            coverURI = CoverURI.filenameOptionsURI("", mpdSong.file, [])
        }
     }
}
