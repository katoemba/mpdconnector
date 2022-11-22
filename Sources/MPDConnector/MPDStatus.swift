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
import libmpdclient
import RxSwift
import RxRelay

public class MPDStatus: StatusProtocol {
    private var playerVolumeAdjustmentKey: String {
        MPDHelper.playerVolumeAdjustmentKey((connectionProperties[ConnectionProperties.name.rawValue] as? String) ?? "NoName")
    }

    /// Connection to a MPD Player
    private let mpd: MPDProtocol
    private var identification = ""
    private var connectionProperties: [String: Any]
    private var userDefaults: UserDefaults
    
    /// ConectionStatus for the player
    private var _connectionStatus = BehaviorRelay<ConnectionStatus>(value: .unknown)
    private var _connectionStatusObservable : Observable<ConnectionStatus>
    public var connectionStatusObservable : Observable<ConnectionStatus> {
        get {
            return _connectionStatusObservable
        }
    }
    private var connecting = false
    private var statusConnection: MPDConnection?

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
    
    public init(mpd: MPDProtocol? = nil,
                connectionProperties: [String: Any],
                identification: String = "NoID",
                scheduler: SchedulerType? = nil,
                userDefaults: UserDefaults) {
        self.mpd = mpd ?? MPDWrapper()
        self.connectionProperties = connectionProperties
        self.identification = identification
        self.statusConnection = nil
        self.userDefaults = userDefaults
        
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
        guard _connectionStatus.value != .online,
                connecting == false else {
            return
        }
        
        connecting = true
        MPDHelper.connectToMPD(mpd: self.mpd, connectionProperties: connectionProperties, scheduler: statusScheduler)
            .subscribe(onNext: { [weak self] (mpdConnection) in
                guard let mpdConnection = mpdConnection else {
                    self?._connectionStatus.accept(.offline)
                    self?.connecting = false
                    return
                }
                self?.statusConnection = mpdConnection
                self?._connectionStatus.accept(.online)
                self?.connecting = false
                self?.startMonitoring()
            })
            .disposed(by: bag)
    }
    
    private func startMonitoring() {
        let timerObservable = Observable<Int>
            .timer(RxTimeInterval.milliseconds(300), period: RxTimeInterval.milliseconds(300), scheduler: elapsedTimeScheduler)
            .map({ [weak self] (_) -> PlayerStatus? in
                if let weakSelf = self {
                    if weakSelf._playerStatus.value.playing.playPauseMode == .Playing {
                        var newPlayerStatus = PlayerStatus.init(weakSelf._playerStatus.value)
                        newPlayerStatus.time.elapsedTime = weakSelf.lastKnownElapsedTime + Int(Date().timeIntervalSince(weakSelf.lastKnownElapsedTimeRecorded))
                        return newPlayerStatus
                    }
                }

                return nil
            })

        let forceReloadObservable = Observable<Int>
            .timer(RxTimeInterval.seconds(1), period: RxTimeInterval.seconds(5), scheduler: elapsedTimeScheduler)
            .flatMap({ [weak self] (_) -> Observable<PlayerStatus?> in
                guard let weakSelf = self else { return Observable.empty() }
                
                return MPDHelper.connectToMPD(mpd: weakSelf.mpd, connectionProperties: weakSelf.connectionProperties, scheduler: weakSelf.elapsedTimeScheduler, timeout: 1000)
                    .map( { [weak self] (mpdConnection) -> PlayerStatus? in
                        guard let weakSelf = self, let connection = mpdConnection?.connection else {
                            return nil
                        }

                        return weakSelf.fetchPlayerStatus(connection)
                })
            })

        let changeStatusUpdateStream = Observable<PlayerStatus?>.create { [weak self] observer in
            guard let weakSelf = self else {
                observer.on(.completed)
                return Disposables.create()
            }
            
            if let connection = weakSelf.statusConnection?.connection {
                observer.onNext(weakSelf.fetchPlayerStatus(connection))
            }
                
            while true {
                if let connection = weakSelf.statusConnection?.connection {
                    if weakSelf.mpd.connection_get_error(connection) != MPD_ERROR_SUCCESS {
                        break
                    }

                    let mask = weakSelf.mpd.run_idle_mask(connection, mask: mpd_idle(rawValue: mpd_idle.RawValue(UInt8(MPD_IDLE_QUEUE.rawValue) | UInt8(MPD_IDLE_PLAYER.rawValue) | UInt8(MPD_IDLE_MIXER.rawValue) | UInt8(MPD_IDLE_OPTIONS.rawValue) | UInt8(MPD_IDLE_OUTPUT.rawValue))))
                    if mask.rawValue == 0 {
                        break
                    }
                    
                    observer.onNext(weakSelf.fetchPlayerStatus(connection))
                }
                else {
                    break
                }
            }
            
            weakSelf.disconnectFromMPD()
            observer.on(.completed)

            weakSelf._connectionStatus.accept(.offline)
            
            return Disposables.create()
        }
        .subscribe(on: statusScheduler)
        
        monitoringBag = DisposeBag()
        Observable.merge(timerObservable, forceReloadObservable, changeStatusUpdateStream)
            .subscribe(onNext: { [weak self] playerStatus in
                guard let weakSelf = self, let playerStatus = playerStatus else {
                    return
                }

                weakSelf._playerStatus.accept(playerStatus)
            })
            .disposed(by: monitoringBag!)
    }
    
    /// Stop monitoring status changes on a player, and close the active connection
    public func stop() {
        if let connection = statusConnection?.connection {
            _ = mpd.send_noidle(connection)
        }
        monitoringBag = nil
    }
    
    /// Validate if the current connection is valid.
    ///
    /// - Returns: true if the connection is active and has no error, false otherwise.
    private func validateConnection(_ connection: OpaquePointer) -> Bool {
        let error = self.mpd.connection_get_error(connection)
        if [MPD_ERROR_TIMEOUT, MPD_ERROR_SYSTEM, MPD_ERROR_RESOLVER, MPD_ERROR_MALFORMED, MPD_ERROR_CLOSED].contains(error) {
            return false
        }
        else if error != MPD_ERROR_SUCCESS {
            print("Error when validating connection: \(self.mpd.connection_get_error_message(connection))")
        }
        
        return true
    }
    
    /// Put quality data from status into the proper format
    ///
    /// - Parameter status: a mpd status objects
    /// - Returns: a filled QualityStatus struct
    private func processQuality(_ status: OpaquePointer) -> QualityStatus {
        var quality = QualityStatus()
        
        let bitrate = self.mpd.status_get_kbit_rate(status)
        quality.bitrate = bitrate > 0 ? "\(bitrate)kbps" : "-"
        if let audioFormat = self.mpd.status_get_audio_format(status) {
            if audioFormat.0 > 0 {
                quality.samplerate = "\(audioFormat.0/1000)kHz"
            }
            else {
                quality.samplerate = "-"
            }
            
            if audioFormat.1 == MPD_SAMPLE_FORMAT_FLOAT {
                quality.encoding = "FLOAT"
            }
            else if audioFormat.1 == MPD_SAMPLE_FORMAT_DSD {
                quality.encoding = "DSD"
            }
            else if audioFormat.1 > 0 {
                quality.encoding = "\(audioFormat.1)bit"
            }
            else {
                quality.encoding = "???"
            }
            
            quality.channels = audioFormat.2 == 1 ? "Mono" : "Stereo"
        }
        
        return quality
    }
    
    /// Get the current status of a controller
    ///
    /// - Parameter connection: an active connection to a mpd player
    /// - Returns: a filled PlayerStatus struct
    public func fetchPlayerStatus(_ connection: OpaquePointer) -> PlayerStatus {
        var playerStatus = PlayerStatus()
        
        if validateConnection(connection) {
            if let status = self.mpd.run_status(connection) {
                defer {
                    self.mpd.status_free(status)
                }
                
                let volume = self.mpd.status_get_volume(status)
                if volume < 0 {
                    playerStatus.volume = 0.5
                    playerStatus.volumeEnabled = false
                }
                else {
                    if let volumeAdjustment = userDefaults.value(forKey: playerVolumeAdjustmentKey) as? Float {
                        print("Status.volumeAdjustment = \(volumeAdjustment)")
                        playerStatus.volume = MPDHelper.adjustedVolumeFromPlayer(Float(volume) / 100.0, volumeAdjustment: volumeAdjustment)
                    }
                    else {
                        playerStatus.volume = Float(volume) / 100.0
                    }
                    playerStatus.volumeEnabled = true
                }
                playerStatus.time.elapsedTime = Int(self.mpd.status_get_elapsed_time(status))
                playerStatus.time.trackTime = Int(self.mpd.status_get_total_time(status))
                self.lastKnownElapsedTime = playerStatus.time.elapsedTime
                self.lastKnownElapsedTimeRecorded = Date()
                
                playerStatus.playing.playPauseMode = (self.mpd.status_get_state(status) == MPD_STATE_PLAY) ? .Playing : .Paused
                playerStatus.playing.randomMode = (self.mpd.status_get_random(status) == true) ? .On : .Off
                let repeatStatus = self.mpd.status_get_repeat(status)
                let singleStatus = self.mpd.status_get_single(status)
                playerStatus.playing.repeatMode = (repeatStatus == true && singleStatus == true) ? .Single : ((repeatStatus == true) ? .All : .Off)
                playerStatus.playing.consumeMode = (self.mpd.status_get_consume(status) == true) ? .On : .Off
                
                playerStatus.playqueue.length = Int(self.mpd.status_get_queue_length(status))
                playerStatus.playqueue.version = Int(self.mpd.status_get_queue_version(status))
                playerStatus.playqueue.songIndex = Int(self.mpd.status_get_song_pos(status))
                
                playerStatus.quality = processQuality(status)
            }
            
            var song = self.mpd.run_current_song(connection)
            if song == nil {
                if mpd.send_list_queue_range_meta(connection, start: UInt32(0), end: UInt32(1)) == true {
                    song = mpd.recv_song(connection)
                }
                _ = mpd.response_finish(connection)
            }
            if let mpdSong = song {
                defer {
                    self.mpd.song_free(mpdSong)
                }
                
                if var song = MPDHelper.songFromMpdSong(mpd: mpd, connectionProperties: connectionProperties, mpdSong: mpdSong) {
                    song.position = playerStatus.playqueue.songIndex
                    playerStatus.quality.filetype = song.quality.filetype
                    
                    if song.id.starts(with: "http://") {
                        song.location = song.id
                        song.id = song.id + song.title
                        song.source = .Shoutcast
                        song.artist = song.name
                        song.album = ""
                    }
                    
                    playerStatus.currentSong = song
                }
            }
            
            var outputs = [Output]()
            if mpd.send_outputs(connection) == true {
                while let mpdOutput = mpd.recv_output(connection) {
                    if let output = MPDHelper.outputFromMPDOutput(mpd: mpd, mpdOutput: mpdOutput) {
                        outputs.append(output)
                    }
                    mpd.output_free(mpdOutput)
                }
                _ = mpd.response_finish(connection)
            }
            playerStatus.outputs = outputs
            
            playerStatus.lastUpdateTime = Date()
        }
        
        return playerStatus
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
        
        let mpdConnection = MPDHelper.connect(mpd: mpd,
                                              host: MPDHelper.hostToUse(connectionProperties),
                                              port: connectionProperties[ConnectionProperties.port.rawValue] as! Int,
                                              password: connectionProperties[ConnectionProperties.password.rawValue] as! String,
                                              timeout: 1000)
        guard let connection = mpdConnection?.connection else {
            return Observable.just([])
        }
        
        var songs = [Song]()
        if mpd.send_list_queue_range_meta(connection, start: UInt32(start), end: UInt32(end)) == true {
            var mpdSong = mpd.recv_song(connection)
            var position = start
            while mpdSong != nil {
                if var song = MPDHelper.songFromMpdSong(mpd: mpd, connectionProperties: connectionProperties, mpdSong: mpdSong) {
                    song.position = position
                    songs.append(song)
                    
                    position += 1
                }
                
                mpd.song_free(mpdSong)
                mpdSong = mpd.recv_song(connection)
            }
            
            _ = mpd.response_finish(connection)
        }
        
        return Observable.just(songs)
    }
    
    /// Get a block of song id's from the playqueue
    ///
    /// - Parameters:
    ///   - start: the start position of the requested block
    ///   - end: the end position of the requested block
    /// - Returns: Array of tuples of playqueue position and track id, not guaranteed to have the same number of songs as requested.
    public func playqueueSongIds(start: Int, end: Int) -> Observable<[(Int, Int)]> {
        guard start >= 0, start < end else {
            return Observable.just([])
        }
        
        let mpdConnection = MPDHelper.connect(mpd: mpd,
                                              host: MPDHelper.hostToUse(connectionProperties),
                                              port: connectionProperties[ConnectionProperties.port.rawValue] as! Int,
                                              password: connectionProperties[ConnectionProperties.password.rawValue] as! String,
                                              timeout: 1000)
        guard let connection = mpdConnection?.connection else {
            return Observable.just([])
        }
        
        var positions = [(Int, Int)]()
        if mpd.send_queue_changes_brief(connection, version: 0) == true {
            var mpdPositionId = mpd.recv_queue_change_brief(connection)
            while let currentMpdPositionId = mpdPositionId {
                positions.append((Int(currentMpdPositionId.0), Int(currentMpdPositionId.1)))
                mpdPositionId = mpd.recv_queue_change_brief(connection)
            }
            
            _ = mpd.response_finish(connection)
        }
        
        return Observable.just(positions)
    }
    
    public func disconnectFromMPD() {
        statusConnection?.disconnect()
        statusConnection = nil
    }

    /// Force a refresh of the status.
    public func forceStatusRefresh() {
    }
    
    /// Manually set a status for test purposes
    public func testSetPlayerStatus(playerStatus: PlayerStatus) {
        _playerStatus.accept(playerStatus)
    }
}
