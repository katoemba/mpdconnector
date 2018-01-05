//
//  MPDStatus.swift
//  MPDConnector_iOS
//
//  Created by Berrie Kremers on 03-01-18.
//  Copyright © 2018 Kaotemba Software. All rights reserved.
//

import Foundation
import ConnectorProtocol
import libmpdclient
import RxSwift
import RxCocoa

public class MPDStatus: StatusProtocol {
    /// Connection to a MPD Player
    public var connection: OpaquePointer?
    private let mpd: MPDProtocol
    private var identification = ""
    private var connectionProperties: [String: Any]
    
    /// ConectionStatus for the player
    private var _connectionStatus = Variable<ConnectionStatus>(.unknown)
    public var connectionStatusObservable : Driver<ConnectionStatus> {
        get {
            return _connectionStatus.asDriver()
        }
    }
    
    /// PlayerStatus object for the player
    private var reloadTrigger = PublishSubject<Int>()
    private var _playerStatus = Variable<PlayerStatus>(PlayerStatus())
    public var playerStatusObservable : Driver<PlayerStatus> {
        get {
            return _playerStatus.asDriver()
        }
    }
    
    // Dispatch queue to serialize starting / stopping, thereby preventing multiple connections
    private let startStopDispatchQueue = DispatchQueue(label: "com.katoemba.mpdconnector.status.startstop")
    private var connecting = false
    
    private let serialScheduler = SerialDispatchQueueScheduler(internalSerialQueueName: "com.katoemba.mpdconnector.status")
    private let bag = DisposeBag()
    
    public init(mpd: MPDProtocol? = nil,
                connectionProperties: [String: Any],
                identification: String = "NoID") {
        self.mpd = mpd ?? MPDWrapper()
        self.connectionProperties = connectionProperties
        self.identification = identification
        
        HelpMePlease.allocUp(name: "MPDStatus")
    }
    
    /// Cleanup connection object
    deinit {
        if let connection = self.connection {
            mpd.connection_free(connection)
            self.connection = nil
        }
        HelpMePlease.allocDown(name: "MPDStatus")
    }
    
    /// Start monitoring status changes on a player
    public func start() {
        startStopDispatchQueue.sync {
            guard _connectionStatus.value != .online,
                    connecting == false else {
                return
            }
            
            connecting = true
            MPDHelper.connectToMPD(mpd: self.mpd, connectionProperties: connectionProperties)
                .subscribe(onNext: { (connection) in
                    self.connection = connection
                    self._connectionStatus.value = .online
                    self.connecting = false
                }, onError: { (error) in
                    self._connectionStatus.value = .offline
                    self.connecting = false
                })
                .disposed(by: bag)

            let manualStatusUpdateStream = reloadTrigger.asObservable()
            let timerStatusUpdateStream = Observable<Int>
                .timer(RxTimeInterval(1.0), period: RxTimeInterval(1.0), scheduler: serialScheduler)
            
            Observable.of(manualStatusUpdateStream, timerStatusUpdateStream)
                .merge()
                .observeOn(serialScheduler)
                .map { [weak self] _ -> PlayerStatus in
                    guard let weakSelf = self else {
                        return PlayerStatus.init()
                    }
                    
                    return weakSelf.fetchPlayerStatus()
                }
                .subscribe(onNext: { [weak self] playerStatus in
                    guard let weakSelf = self else {
                        return
                    }
                    
                    weakSelf._playerStatus.value = playerStatus
                })
                .disposed(by: bag)
            
            // Force a first status load
            reloadTrigger.onNext(1)
        }
    }
    
    /// Stop monitoring status changes on a player, and close the active connection
    public func stop() {
        connectionCleanup()
    }
    
    private func connectionCleanup() {
        startStopDispatchQueue.sync {
            if connection != nil {
                mpd.connection_free(connection)
                connection = nil
            }
            _connectionStatus.value = .offline
            connecting = false
        }
    }
    
    /// Validate if the current connection is valid.
    ///
    /// - Returns: true if the connection is active and has no error, false otherwise.
    private func validateConnection() -> Bool {
        guard connection != nil else {
            connectionCleanup()
            return false
        }
        
        let error = self.mpd.connection_get_error(connection)
        if [MPD_ERROR_TIMEOUT, MPD_ERROR_SYSTEM, MPD_ERROR_RESOLVER, MPD_ERROR_MALFORMED, MPD_ERROR_CLOSED].contains(error) {
            mpd.connection_free(connection)
            connection = nil
            _connectionStatus.value = .offline
            
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
    private func fetchPlayerStatus() -> PlayerStatus {
        var playerStatus = PlayerStatus()
        
        if self.validateConnection() {
            if let status = self.mpd.run_status(self.connection) {
                defer {
                    self.mpd.status_free(status)
                }
                
                playerStatus.volume = Float(self.mpd.status_get_volume(status)) / 100.0
                playerStatus.time.elapsedTime = Int(self.mpd.status_get_elapsed_time(status))
                playerStatus.time.trackTime = Int(self.mpd.status_get_total_time(status))
                
                playerStatus.playing.playPauseMode = (self.mpd.status_get_state(status) == MPD_STATE_PLAY) ? .Playing : .Paused
                playerStatus.playing.randomMode = (self.mpd.status_get_random(status) == true) ? .On : .Off
                let repeatStatus = self.mpd.status_get_repeat(status)
                let singleStatus = self.mpd.status_get_single(status)
                playerStatus.playing.repeatMode = (repeatStatus == true && singleStatus == true) ? .Single : ((repeatStatus == true) ? .All : .Off)
                
                playerStatus.playqueue.length = Int(self.mpd.status_get_queue_length(status))
                playerStatus.playqueue.version = Int(self.mpd.status_get_queue_version(status))
                playerStatus.playqueue.songIndex = Int(self.mpd.status_get_song_pos(status))
            }
            
            // Note: it's possible that here the connection is gone! Need a mutex or check.
            if let song = self.mpd.run_current_song(self.connection) {
                defer {
                    self.mpd.song_free(song)
                }
                
                if let song = MPDHelper.songFromMpdSong(mpd: mpd, mpdSong: song) {
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
            var mpdSong = mpd.get_song(connection)
            var position = start
            while mpdSong != nil {
                if var song = MPDHelper.songFromMpdSong(mpd: mpd, mpdSong: mpdSong) {
                    song.position = position
                    songs.append(song)
                    
                    position += 1
                }
                
                mpd.song_free(mpdSong)
                mpdSong = mpd.get_song(connection)
            }
            
            _ = mpd.response_finish(connection)
        }
        mpd.connection_free(connection)
        
        return songs
    }

    
    /// Force a refresh of the status.
    public func forceStatusRefresh() {
        reloadTrigger.onNext(1)
    }
}
