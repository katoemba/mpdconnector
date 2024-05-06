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
import RxSwift
import RxRelay
import SwiftMPD

public class MPDStatus: StatusProtocol {
    private var playerVolumeAdjustmentKey: String {
        MPDHelper.playerVolumeAdjustmentKey((connectionProperties[ConnectionProperties.name.rawValue] as? String) ?? "NoName")
    }

    /// Connection to a MPD Player
    private var identification = ""
    private var connectionProperties: [String: Any]
    private var userDefaults: UserDefaults
    
    /// ConectionStatus for the player
    private var mpdIdleConnector: SwiftMPD.MPDConnector?
    private var mpdConnector: SwiftMPD.MPDConnector
    private var _connectionStatus = BehaviorRelay<ConnectionStatus>(value: .unknown)
    private var _connectionStatusObservable : Observable<ConnectionStatus>
    public var connectionStatusObservable : Observable<ConnectionStatus> {
        get {
            return _connectionStatusObservable
        }
    }

    /// PlayerStatus object for the player
    private var _playerStatus = BehaviorRelay<PlayerStatus>(value: PlayerStatus())
    public var playerStatusObservable : Observable<PlayerStatus> {
        get {
            return _playerStatus
                .distinctUntilChanged()
                .observe(on: MainScheduler.instance)
        }
    }
    
    private var lastKnownElapsedTime = 0
    private var lastKnownElapsedTimeRecorded = Date()

    private var statusScheduler: SchedulerType
    private var elapsedTimeScheduler: SchedulerType
    private var bag = DisposeBag()
    private var monitoringBag: DisposeBag? = nil
    private var elapsedTask: Task<Void, Never>?
    
    public init(connectionProperties: [String: Any],
                identification: String = "NoID",
                scheduler: SchedulerType? = nil,
                userDefaults: UserDefaults,
                mpdConnector: SwiftMPD.MPDConnector,
                mpdIdleConnector: SwiftMPD.MPDConnector? = nil) {
        self.connectionProperties = connectionProperties
        self.identification = identification
        self.userDefaults = userDefaults
        self.mpdConnector = mpdConnector
        self.mpdIdleConnector = mpdIdleConnector
        
        if scheduler == nil {
            self.statusScheduler = SerialDispatchQueueScheduler.init(qos: .background, internalSerialQueueName: "com.katoemba.mpdconnector.status")
            self.elapsedTimeScheduler = SerialDispatchQueueScheduler.init(internalSerialQueueName: "com.katoemba.mpdconnector.elapsedtime")
        }
        else {
            self.statusScheduler = scheduler!
            self.elapsedTimeScheduler = scheduler!
        }
        
        _connectionStatusObservable = _connectionStatus
            .observe(on: MainScheduler.instance)

        HelpMePlease.allocUp(name: "MPDStatus")
    }
    
    /// Cleanup connection object
    deinit {
        HelpMePlease.allocDown(name: "MPDStatus")
        
        disconnectFromMPD()
    }
    
    /// Start monitoring status changes on a player
    public func start() {
        assert(Thread.isMainThread, "MPDStatus.start can only be called from the main thread")
        guard _connectionStatus.value != .online, let mpdIdleConnector else {
            return
        }
        
        _connectionStatus.accept(.online)
        Task {
            while (true) {
                if let playerStatus = try? await fetchPlayerStatus(mpdIdleConnector) {
                    _playerStatus.accept(playerStatus)
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
                if self._playerStatus.value.playing.playPauseMode == .Playing {
                    var newPlayerStatus = PlayerStatus.init(self._playerStatus.value)
                    newPlayerStatus.time.elapsedTime = self.lastKnownElapsedTime + Int(Date().timeIntervalSince(self.lastKnownElapsedTimeRecorded))

                    _playerStatus.accept(newPlayerStatus)
                }

                counter += 1
                if counter > 4 * 5 {
                    counter = 0
                    if let playerStatus = try? await fetchPlayerStatus(mpdConnector) {
                        _playerStatus.accept(playerStatus)
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
            elapsedTask?.cancel()
            _connectionStatus.accept(.offline)
            try? await mpdIdleConnector?.status.noidle()
        }
    }
            
    /// Get the current status of a controller
    ///
    /// - Parameter connection: an active connection to a mpd player
    /// - Returns: a filled PlayerStatus struct
    public func fetchPlayerStatus(_ connector: MPDConnector) async throws -> PlayerStatus {
        let statusExecutor = connector.status.statusExecutor()
        let outputsExecutor = connector.output.outputsExecutor()
        let currentsongExecutor = connector.status.currentsongExecutor()

        try await connector.batchCommand([statusExecutor, outputsExecutor, currentsongExecutor])
        
        let status = try statusExecutor.processResults()
        let outputs = try outputsExecutor.processResults()
        let currentSong = try? currentsongExecutor.processResults()
        
        return PlayerStatus(from: status, currentSong: currentSong, outputs: outputs, connectionProperties: connectionProperties, userDefaults: userDefaults)
    }
    
    /// Get the current status from the player
    public func getStatus() -> Observable<PlayerStatus> {
        Observable<PlayerStatus>.fromAsync {
            try await self.fetchPlayerStatus(self.mpdConnector)
        }
    }

    /// Get an array of songs from the playqueue.
    ///
    /// - Parameters
    ///   - start: the first song to fetch, zero-based.
    ///   - end: the last song to fetch, zero-based.
    /// Returns: an array of filled Songs objects.
    public func playqueueSongs(start: Int, end: Int) -> Observable<[Song]> {
        guard start >= 0, start < end else {
            return Observable.just([])
        }
        
        let mpdConnector = self.mpdConnector
        let connectionProperties = self.connectionProperties
        return Observable<[Song]>.fromAsync {
            let mpdSongs = try await mpdConnector.queue.playlistinfo(range: start..<end)

            var position = start
            let songs = mpdSongs.map {
                var song = Song(mpdSong: $0, connectionProperties: connectionProperties)
                song.position = position
                
                position += 1
                return song
            }
            return songs
        }
    }
    
    /// Get a block of song id's from the playqueue
    ///
    /// - Parameters:
    ///   - start: the start position of the requested block
    ///   - end: the end position of the requested block
    /// - Returns: Array of tuples of playqueue position and track id, not guaranteed to have the same number of songs as requested.
    public func playqueueSongIds(start: Int, end: Int) -> Observable<[(Int, String)]> {
        guard start >= 0, start < end else {
            return Observable.just([])
        }
        
        let mpdConnector = self.mpdConnector
        return Observable<[(Int, Int)]>.fromAsync {
            let posids = try await mpdConnector.queue.plchangesposid(version: 0)

            return posids
                .filter {
                    $0.cpos >= start && $0.cpos < end
                }
                .map {
                    ($0.cpos, "\($0.id)")
                }
        }
    }
    
    public func disconnectFromMPD() {
    }

    /// Force a refresh of the status.
    public func forceStatusRefresh() {
    }
    
    /// Manually set a status for test purposes
    public func testSetPlayerStatus(playerStatus: PlayerStatus) {
        _playerStatus.accept(playerStatus)
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
        time.trackTime = Int(from.duration ?? 0)
        
        if from.volume < 0 {
            volume = 0.5
            volumeEnabled = false
        }
        else {
            let playerVolumeAdjustmentKey = MPDHelper.playerVolumeAdjustmentKey((connectionProperties[ConnectionProperties.name.rawValue] as? String) ?? "NoName")
            if let volumeAdjustment = userDefaults.value(forKey: playerVolumeAdjustmentKey) as? Float {
                volume = MPDHelper.adjustedVolumeFromPlayer(Float(from.volume) / 100.0, volumeAdjustment: volumeAdjustment)
            }
            else {
                volume = Float(from.volume) / 100.0
            }
            volumeEnabled = true
        }

        switch from.state {
        case .pause:
            playing.playPauseMode = .Paused
        case .play:
            playing.playPauseMode = .Playing
        case .stop:
            playing.playPauseMode = .Stopped
        }
        switch from.consume {
        case .off:
            playing.consumeMode = .Off
        case .on:
            playing.consumeMode = .On
        case .oneshot:
            playing.consumeMode = .On
        }
        playing.randomMode = (from.random == .on) ? .On : .Off
        switch from.repeat {
        case .off:
            playing.repeatMode = .Off
        case .on:
            if from.single == .off {
                playing.repeatMode = .All
            }
            else {
                playing.repeatMode = .Single
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
    public init(mpdSong: SwiftMPD.MPDSong, connectionProperties: [String: Any]) {
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
        playqueueId = (mpdSong.id == nil) ? UUID().uuidString : "\(mpdSong.id!)"
        
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

        if postfix == "" && alternativePostfix == "" {
            coverURI = CoverURI.fullPathURI("http://\(coverHost)\(portExtension)/\(prefix)\(coverString)")
        }
        else if postfix == "<track>" {
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
