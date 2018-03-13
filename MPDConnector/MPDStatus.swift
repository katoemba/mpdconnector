//
//  MPDStatus.swift
//  MPDConnector_iOS
//
//  Created by Berrie Kremers on 03-01-18.
//  Copyright © 2018 Katoemba Software. All rights reserved.
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
    public var connectionStatusObservable : Driver<ConnectionStatus> {
        get {
            return _connectionStatus.asDriver()
        }
    }
    private var connecting = false

    /// PlayerStatus object for the player
    private var _playerStatus = BehaviorRelay<PlayerStatus>(value: PlayerStatus())
    public var playerStatusObservable : Observable<PlayerStatus> {
        get {
            return _playerStatus.asObservable()
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
        
        if scheduler == nil {
            self.statusScheduler = SerialDispatchQueueScheduler.init(qos: .background, internalSerialQueueName: "com.katoemba.mpdconnector.status")
            self.elapsedTimeScheduler = SerialDispatchQueueScheduler.init(internalSerialQueueName: "com.katoemba.mpdconnector.elapsedtime")
        }
        else {
            self.statusScheduler = scheduler!
            self.elapsedTimeScheduler = scheduler!
        }
        
        HelpMePlease.allocUp(name: "MPDStatus")
    }
    
    /// Cleanup connection object
    deinit {
        HelpMePlease.allocDown(name: "MPDStatus")
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
                self?._connectionStatus.accept(.online)
                self?.connecting = false
                self?.startMonitoring(connection: connection)
            },
                       onError: { [weak self] _ in
                        self?._connectionStatus.accept(.offline)
                        self?.connecting = false
            })
            .disposed(by: bag)
    }
    
    private func startMonitoring(connection: OpaquePointer) {
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
            observer.onNext(self?.fetchPlayerStatus(connection))

            while true {
                if self?.mpd.connection_get_error(connection) != MPD_ERROR_SUCCESS {
                    break
                }
                
                let mask = self?.mpd.run_idle_mask(connection, mask: mpd_idle(rawValue: mpd_idle.RawValue(UInt8(MPD_IDLE_QUEUE.rawValue) | UInt8(MPD_IDLE_PLAYER.rawValue) | UInt8(MPD_IDLE_MIXER.rawValue) | UInt8(MPD_IDLE_OPTIONS.rawValue))))
                if mask?.rawValue == 0 {
                    break
                }
                
                observer.onNext(self?.fetchPlayerStatus(connection))
            }
            
            self?.mpd.connection_free(connection)
            observer.on(.completed)

            self?._connectionStatus.accept(.offline)
            
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
                _ = self?.mpd.send_noidle(connection)
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
            }
            
            if let song = self.mpd.run_current_song(connection) {
                defer {
                    self.mpd.song_free(song)
                }
                
                if var song = MPDHelper.songFromMpdSong(mpd: mpd, connectionProperties: connectionProperties, mpdSong: song) {
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

    /// Force a refresh of the status.
    public func forceStatusRefresh() {
    }
    
    /// Manually set a status for test purposes
    public func testSetPlayerStatus(playerStatus: PlayerStatus) {
        _playerStatus.accept(playerStatus)
    }
}
