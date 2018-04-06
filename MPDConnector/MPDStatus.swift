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
import RxCocoa

public class MPDStatus: StatusProtocol {
    /// Connection to a MPD Player
    private let mpd: MPDProtocol
    private var identification = ""
    private var connectionProperties: [String: Any]
    
    /// ConectionStatus for the player
    private var _connectionStatus = BehaviorRelay<ConnectionStatus>(value: .unknown)
    private var _connectionStatusObservable : Observable<ConnectionStatus>
    public var connectionStatusObservable : Observable<ConnectionStatus> {
        get {
            return _connectionStatusObservable
        }
    }
    private var connecting = false
    private var statusConnection: OpaquePointer?

    /// PlayerStatus object for the player
    private var _playerStatus = BehaviorRelay<PlayerStatus>(value: PlayerStatus())
    private var _playerStatusObservable : Observable<PlayerStatus>
    public var playerStatusObservable : Observable<PlayerStatus> {
        get {
            return _playerStatusObservable
        }
    }
    let disconnectHandler = PublishSubject<Int>()
    
    private var lastKnownElapsedTime = 0
    private var lastKnownElapsedTimeRecorded = Date()
    
    private var statusScheduler: SchedulerType
    private var elapsedTimeScheduler: SchedulerType
    private var bag = DisposeBag()
    
    public init(mpd: MPDProtocol? = nil,
                connectionProperties: [String: Any],
                identification: String = "NoID",
                scheduler: SchedulerType? = nil) {
        self.mpd = mpd ?? MPDWrapper()
        self.connectionProperties = connectionProperties
        self.identification = identification
        self.statusConnection = nil
        
        if scheduler == nil {
            self.statusScheduler = SerialDispatchQueueScheduler.init(qos: .background, internalSerialQueueName: "com.katoemba.mpdconnector.status")
            self.elapsedTimeScheduler = SerialDispatchQueueScheduler.init(internalSerialQueueName: "com.katoemba.mpdconnector.elapsedtime")
        }
        else {
            self.statusScheduler = scheduler!
            self.elapsedTimeScheduler = scheduler!
        }
        
        _connectionStatusObservable = _connectionStatus
            .observeOn(MainScheduler.instance)

        _playerStatusObservable = _playerStatus
            .observeOn(MainScheduler.instance)

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
        MPDHelper.connectToMPD(mpd: self.mpd, connectionProperties: connectionProperties)
            .subscribeOn(statusScheduler)
            .subscribe(onNext: { [weak self] (connection) in
                self?.statusConnection = connection
                self?._connectionStatus.accept(.online)
                self?.connecting = false
                self?.startMonitoring()
            },
                       onError: { [weak self] _ in
                        self?._connectionStatus.accept(.offline)
                        self?.connecting = false
            })
            .disposed(by: bag)
    }
    
    private func startMonitoring() {
        let timerObservable = Observable<Int>
            .timer(RxTimeInterval(1.0), period: RxTimeInterval(1.0), scheduler: elapsedTimeScheduler)
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
        
        let changeStatusUpdateStream = Observable<PlayerStatus?>.create { [weak self] observer in
            guard let weakSelf = self else {
                observer.on(.completed)
                return Disposables.create()
            }
            
            if let connection = weakSelf.statusConnection {
                observer.onNext(weakSelf.fetchPlayerStatus(connection))
            }
                
            while true {
                if let connection = weakSelf.statusConnection {
                    if weakSelf.mpd.connection_get_error(connection) != MPD_ERROR_SUCCESS {
                        break
                    }

                    let mask = weakSelf.mpd.run_idle_mask(connection, mask: mpd_idle(rawValue: mpd_idle.RawValue(UInt8(MPD_IDLE_QUEUE.rawValue) | UInt8(MPD_IDLE_PLAYER.rawValue) | UInt8(MPD_IDLE_MIXER.rawValue) | UInt8(MPD_IDLE_OPTIONS.rawValue))))
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
        
        Observable.of(timerObservable, changeStatusUpdateStream)
            .merge()
            .subscribe(onNext: { [weak self] playerStatus in
                guard let weakSelf = self, let playerStatus = playerStatus else {
                    return
                }
                
                weakSelf._playerStatus.accept(playerStatus)
            })
            .disposed(by: bag)
        
        disconnectHandler.asObservable()
            .subscribe(onNext: { [weak self] (_) in
                guard let weakSelf = self, let connection = weakSelf.statusConnection else {
                    return
                }
                
                _ = weakSelf.mpd.send_noidle(connection)
            })
            .disposed(by: bag)
    }
    
    /// Stop monitoring status changes on a player, and close the active connection
    public func stop() {
        disconnectHandler.onNext(1)
        //disconnectHandler.onCompleted()
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
    
    /// Get the current status of a controller
    ///
    /// - Returns: a filled PlayerStatus struct
    private func fetchPlayerStatus(_ connection: OpaquePointer) -> PlayerStatus {
        var playerStatus = PlayerStatus()
        
        if validateConnection(connection) {
            if let status = self.mpd.run_status(connection) {
                defer {
                    self.mpd.status_free(status)
                }
                
                playerStatus.volume = Float(self.mpd.status_get_volume(status)) / 100.0
                playerStatus.time.elapsedTime = Int(self.mpd.status_get_elapsed_time(status))
                playerStatus.time.trackTime = Int(self.mpd.status_get_total_time(status))
                self.lastKnownElapsedTime = playerStatus.time.elapsedTime
                self.lastKnownElapsedTimeRecorded = Date()
                
                playerStatus.playing.playPauseMode = (self.mpd.status_get_state(status) == MPD_STATE_PLAY) ? .Playing : .Paused
                playerStatus.playing.randomMode = (self.mpd.status_get_random(status) == true) ? .On : .Off
                let repeatStatus = self.mpd.status_get_repeat(status)
                let singleStatus = self.mpd.status_get_single(status)
                playerStatus.playing.repeatMode = (repeatStatus == true && singleStatus == true) ? .Single : ((repeatStatus == true) ? .All : .Off)
                
                playerStatus.playqueue.length = Int(self.mpd.status_get_queue_length(status))
                playerStatus.playqueue.version = Int(self.mpd.status_get_queue_version(status))
                playerStatus.playqueue.songIndex = Int(self.mpd.status_get_song_pos(status))
                
                let samplerate = self.mpd.status_get_kbit_rate(status)
                playerStatus.quality.samplerate = samplerate > 0 ? "\(self.mpd.status_get_kbit_rate(status))bit" : "-"
                if let audioFormat = self.mpd.status_get_audio_format(status) {
                    if audioFormat.0 > 0 {
                        playerStatus.quality.samplerate = "\(audioFormat.0/1000)kHz"
                    }
                    else {
                        playerStatus.quality.samplerate = "-"
                    }
                    
                    if audioFormat.1 == MPD_SAMPLE_FORMAT_FLOAT {
                        playerStatus.quality.encoding = "FLOAT"
                    }
                    else if audioFormat.1 == MPD_SAMPLE_FORMAT_DSD {
                        playerStatus.quality.encoding = "DSD"
                    }
                    else if audioFormat.1 > 0 {
                        playerStatus.quality.encoding = "\(audioFormat.1)bit"
                    }
                    else {
                        playerStatus.quality.encoding = "???"
                    }
                    
                    playerStatus.quality.channels = audioFormat.2 == 1 ? "Mono" : "Stereo"
                }
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
                    playerStatus.currentSong = song
                }
            }
        }
        
        return playerStatus
    }
    
    /// Get an array of songs from the playqueue.
    ///
    /// - Parameters
    ///   - start: the first song to fetch, zero-based.
    ///   - end: the last song to fetch, zero-based.
    /// Returns: an array of filled Songs objects.
    public func playqueueSongs(start: Int, end: Int) -> [Song] {
        guard start >= 0, start < end else {
            return []
        }
        
        guard let connection = MPDHelper.connect(mpd: mpd,
                                                 host: connectionProperties[ConnectionProperties.Host.rawValue] as! String,
                                                 port: connectionProperties[ConnectionProperties.Port.rawValue] as! Int,
                                                 password: connectionProperties[ConnectionProperties.Password.rawValue] as! String,
                                                 timeout: 1000) else {
            return []
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
        mpd.connection_free(connection)
        
        return songs
    }
    
    private func disconnectFromMPD() {
        if let connection = statusConnection {
            mpd.connection_free(connection)
            statusConnection = nil
        }
    }

    /// Force a refresh of the status.
    public func forceStatusRefresh() {
    }
    
    /// Manually set a status for test purposes
    public func testSetPlayerStatus(playerStatus: PlayerStatus) {
        _playerStatus.accept(playerStatus)
    }
}
