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

public class MPDStatus: StatusProtocol, @unchecked Sendable {
    /// Connection to a MPD Player
    private var identification = ""
    private var connectionProperties: [String: Any]
    private var userDefaults: UserDefaults
    
    /// ConectionStatus for the player
    private var mpdIdleConnector: SwiftMPD.MPDConnector?
    private var mpdConnector: SwiftMPD.MPDConnector
    
    @Published var connectionStatus: ConnectionStatus = .unknown
    public var connectionStatusPublisher: AnyPublisher<ConnectionStatus, Never> { $connectionStatus.eraseToAnyPublisher() }
    
    private var connectionStatusContinuation: AsyncStream<ConnectionStatus>.Continuation!
    lazy var _connectionStatusStream: AsyncStream<ConnectionStatus> = {
        AsyncStream<ConnectionStatus> { continuation in
            self.connectionStatusContinuation = continuation
        }
    }()
    public var connectionStatusStream: AsyncStream<ConnectionStatus> {
        _connectionStatusStream
    }

    @Published public var playerStatus: PlayerStatus = PlayerStatus() {
        didSet {
            let _ = playerStatusStream
            playerStatusContinuation.yield(playerStatus)
        }
    }
    public var playerStatusPublisher: AnyPublisher<PlayerStatus, Never> { $playerStatus.eraseToAnyPublisher() }
    
    private var playerStatusContinuation: AsyncStream<PlayerStatus>.Continuation!
    lazy var _playerStatusStream: AsyncStream<PlayerStatus> = {
        AsyncStream<PlayerStatus> { continuation in
            self.playerStatusContinuation = continuation
        }
    }()
    public var playerStatusStream: AsyncStream<PlayerStatus> {
        _playerStatusStream
    }

    private var lastKnownElapsedTime = 0
    private var lastKnownElapsedTimeRecorded = Date()
    private var elapsedTask: Task<Void, Never>?

    public init(connectionProperties: [String: Any],
                identification: String = "NoID",
                userDefaults: UserDefaults,
                mpdConnector: SwiftMPD.MPDConnector,
                mpdIdleConnector: SwiftMPD.MPDConnector? = nil) {
        self.connectionProperties = connectionProperties
        self.identification = identification
        self.userDefaults = userDefaults
        self.mpdConnector = mpdConnector
        self.mpdIdleConnector = mpdIdleConnector
        let _ = _connectionStatusStream
        self.connectionStatusContinuation.yield(.unknown)
    }
    
    /// Cleanup connection object
    deinit {
        disconnectFromMPD()
    }

    public func start() {
        guard connectionStatus != .online, let mpdIdleConnector else {
            return
        }
        
        connectionStatus = .online
        connectionStatusContinuation.yield(.online)
        Task {
            while (true) {
                if let playerStatus = try? await playerStatus(connector: mpdIdleConnector) {
                    self.playerStatus = playerStatus
                    lastKnownElapsedTimeRecorded = Date()
                    lastKnownElapsedTime = playerStatus.time.elapsedTime
                }
                
                guard let changes = try? await mpdIdleConnector.status.idle([.player, .playlist, .mixer, .output, .options]), changes.count > 0 else {
                    break
                }
            }
        }
        
        elapsedTask = Task { [weak self] in
            guard let self else { return }
            
            var counter = 0
            while (Task.isCancelled == false) {
                if playerStatus.playing.playPauseMode == .playing {
                    var newPlayerStatus = PlayerStatus.init(playerStatus)
                    newPlayerStatus.time.elapsedTime = self.lastKnownElapsedTime + Int(Date().timeIntervalSince(self.lastKnownElapsedTimeRecorded))

                    self.playerStatus = newPlayerStatus
                }

                counter += 1
                if counter > 20 {
                    counter = 0
                    if let playerStatus = try? await playerStatus() {
                        self.playerStatus = playerStatus
                        lastKnownElapsedTimeRecorded = Date()
                        lastKnownElapsedTime = playerStatus.time.elapsedTime
                    }
                }
                
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }
    
    /// Stop monitoring status changes on a player, and close the active connection
    public func stop() {
        Task {
            connectionStatus = .offline
            connectionStatusContinuation.yield(.offline)
            try? await mpdIdleConnector?.status.noidle()
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
        
        return PlayerStatus(from: status, currentSong: currentSong, outputs: outputs, connectionProperties: connectionProperties, userDefaults: userDefaults)
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
        
        let connectionProperties = self.connectionProperties
        do {
            let mpdSongs = try await mpdConnector.queue.playlistinfo(range: start...end)
            
            var position = start
            let songs = mpdSongs.map {
                var song = Song(mpdSong: $0, connectionProperties: connectionProperties, forcePlayqueueId: true)
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
    
    public func disconnectFromMPD() {
    }

    /// Force a refresh of the status.
    public func forceStatusRefresh() {
        Task {
            do {
                playerStatus = try await playerStatus()
            }
            catch {
                
            }
        }
    }
    
    /// Manually set a status for test purposes
    public func testSetPlayerStatus(playerStatus: PlayerStatus) {
        self.playerStatus = playerStatus
    }
}

extension PlayerStatus {
    public init(from: SwiftMPD.MPDStatus.Status, currentSong: SwiftMPD.MPDSong?, outputs: [SwiftMPD.MPDOutput.Output], connectionProperties: [String: Any], userDefaults: UserDefaults) {
        self.init()
        
        if let currentSong {
            self.currentSong = Song(mpdSong: currentSong, connectionProperties: connectionProperties)
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
            let playerVolumeAdjustmentKey = MPDHelper.playerVolumeAdjustmentKey((connectionProperties[ConnectionProperties.name.rawValue] as? String) ?? "NoName")
            if let volumeAdjustment = userDefaults.value(forKey: playerVolumeAdjustmentKey) as? Float {
                self.volume = MPDHelper.adjustedVolumeFromPlayer(Float(volume) / 100.0, volumeAdjustment: volumeAdjustment)
            }
            else {
                self.volume = Float(volume) / 100.0
            }
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
    public init(mpdSong: SwiftMPD.MPDSong, connectionProperties: [String: Any], forcePlayqueueId: Bool = false) {
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
        
        let coverString = newPath.removingPercentEncoding?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        var coverHost = connectionProperties[MPDConnectionProperties.alternativeCoverHost.rawValue] as? String ?? ""
        if coverHost == "" {
            coverHost = connectionProperties[ConnectionProperties.host.rawValue] as? String ?? ""
        }
        let coverHttpPort = connectionProperties[MPDConnectionProperties.coverHttpPort.rawValue] as? String ?? ""
        let portExtension = coverHttpPort == "" ? coverHttpPort : ":\(coverHttpPort)"
        let prefix = connectionProperties[MPDConnectionProperties.coverPrefix.rawValue] as? String ?? ""
        let postfix = connectionProperties[MPDConnectionProperties.coverPostfix.rawValue] as? String ?? ""
        let alternativePostfix = connectionProperties[MPDConnectionProperties.alternativeCoverPostfix.rawValue] as? String ?? ""

//        if postfix == "" && alternativePostfix == "" {
//            coverURI = CoverURI.fullPathURI("http://\(coverHost)\(portExtension)/\(prefix)\(coverString)")
//        }
//        else
        if postfix == "<track>" {
            coverURI = CoverURI.filenameOptionsURI("http://\(coverHost)\(portExtension)/\(prefix)\(id)", newPath, ["cover.jpg"])
        }
        else if alternativePostfix == "" {
            coverURI = CoverURI.filenameOptionsURI("http://\(coverHost)\(portExtension)/\(prefix)\(coverString)", newPath, [postfix, CoverURI.embeddedPrefix + id])
        }
        else {
            coverURI = CoverURI.filenameOptionsURI("http://\(coverHost)\(portExtension)/\(prefix)\(coverString)", newPath, [postfix, alternativePostfix, CoverURI.embeddedPrefix + id])
        }
     }
}
