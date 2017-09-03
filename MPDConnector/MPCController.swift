//
//  MPCController.swift
//  MPDConnector
//
//  Created by Berrie Kremers on 26-08-17.
//  Copyright © 2017 Kaotemba Software. All rights reserved.
//

import Foundation
import ConnectorProtocol
import libmpdclient
import RxSwift

public class MPDController: ControlProtocol {
    /// Connection to a MPD Player
    public var connection: OpaquePointer?
    private let mpd: MPDProtocol

    /// PlayerStatus object for the player
    public var playerStatus = PlayerStatus()
    private var playerStatusMonitor: Observable<Void>?
    public var observablePlayerStatus = ObservablePlayerStatus()
    
    private let serialScheduler = SerialDispatchQueueScheduler(internalSerialQueueName: "com.katoemba.mpdcontroller.controller")
    private let commandQueue = DispatchQueue(label: "com.katoemba.mpdcontroller")
    
    public var disconnectedHandler: ((_ connection: OpaquePointer, _ error: mpd_error) -> Void)?

    public init(mpd: MPDProtocol? = nil,
                connection: OpaquePointer? = nil,
                disconnectedHandler: ((_ connection: OpaquePointer, _ error: mpd_error) -> Void)? = nil) {
        self.mpd = mpd ?? MPDWrapper()
        self.connection = connection
        self.disconnectedHandler = disconnectedHandler
        
        playerStatusMonitor = Observable<Int>
            .timer(RxTimeInterval(0.1), period: RxTimeInterval(1.0), scheduler: serialScheduler)
            .map { [weak self] _ in
                self?.updateObservablePlayerStatus()
        }
        
        playerStatusMonitor?
            .subscribe()
            .addDisposableTo(bag)
    }
    
    private let bag = DisposeBag()

    /// Cleanup connection object
    deinit {
        if let connection = self.connection {
            self.mpd.connection_free(connection)
            self.connection = nil
        }
    }
    
    /// Validate if the current connection is valid, and if not try to reconnect.
    ///
    /// - Returns: true if the connection is active and has no error, false otherwise.
    private func validateConnection() -> Bool {
        guard connection != nil else {
            return false
        }
        
        let error = self.mpd.connection_get_error(connection)
        if [MPD_ERROR_TIMEOUT, MPD_ERROR_SYSTEM, MPD_ERROR_RESOLVER, MPD_ERROR_MALFORMED, MPD_ERROR_CLOSED].contains(error) {
            if let handler = self.disconnectedHandler {
                handler(self.connection!, error)
            }
            self.connection = nil
            
            return false
        }
        
        return true
    }

    /// Start playback.
    public func play() {
        guard validateConnection() else {
            return
        }
        
        self.runCommand  {
            _ = self.mpd.run_play(self.connection!)
        }
    }
    
    /// Start playback.
    public func play(index: Int) {
        guard validateConnection() else {
            return
        }
        
        guard index >= 0 else {
            return
        }
        
        self.runCommand  {
            _ = self.mpd.run_play_pos(self.connection, UInt32(index))
        }
    }
    
    /// Pause playback.
    public func pause() {
        guard validateConnection() else {
            return
        }
        
        self.runCommand  {
            _ = self.mpd.run_pause(self.connection, true)
        }
    }
    
    /// Toggle between play and pause: when paused -> start to play, when playing -> pause.
    public func togglePlayPause() {
        guard validateConnection() else {
            return
        }
        
        self.runCommand  {
            _ = self.mpd.run_toggle_pause(self.connection!)
        }
    }
    
    /// Skip to the next track.
    public func skip() {
        guard validateConnection() else {
            return
        }
        
        self.runCommand  {
            _ = self.mpd.run_next(self.connection!)
        }
    }
    
    /// Go back to the previous track.
    public func back() {
        guard validateConnection() else {
            return
        }
        
        self.runCommand  {
            _ = self.mpd.run_previous(self.connection)
        }
    }
    
    /// Set the shuffle mode of the player.
    ///
    /// - Parameter shuffleMode: The shuffle mode to use.
    public func setShuffle(shuffleMode: ShuffleMode) {
        guard validateConnection() else {
            return
        }
        
        self.runCommand  {
            _ = self.mpd.run_random(self.connection, (shuffleMode == .On) ? true : false)
        }
    }
    
    /// Set the repeat mode of the player.
    ///
    /// - Parameter repeatMode: The repeat mode to use.
    public func setRepeat(repeatMode: RepeatMode) {
        guard validateConnection() else {
            return
        }
        
        self.runCommand  {
            _ = self.mpd.run_repeat(self.connection, (repeatMode == .Off) ? false : true)
        }
    }
    
    /// Set the volume of the player.((shuffleMode == .On)?,true:false)
    ///
    /// - Parameter volume: The volume to set. Must be a value between 0.0 and 1.0, values outside this range will be ignored.
    public func setVolume(volume: Float) {
        guard volume >= 0.0, volume <= 1.0 else {
            return
        }
        
        guard validateConnection() else {
            return
        }
        
        self.runCommand  {
            _ = self.mpd.run_set_volume(self.connection, UInt32(roundf(volume * 100.0)))
        }
    }
    
    public func getPlayqueueSongs(start: Int, end: Int,
                                  songsFound: @escaping (([Song]) -> Void)) {
        guard start >= 0 else {
            songsFound([])
            return
        }
        
        guard self.validateConnection() else {
            songsFound([])
            return
        }
        
        self.commandQueue.async {
            var songs = [Song]()
            if self.mpd.send_list_queue_range_meta(self.connection, start: UInt32(start), end: UInt32(end)) == true {
                var mpdSong = self.mpd.get_song(self.connection)
                while mpdSong != nil {
                    if let song = self.songFromMpdSong(mpdSong: mpdSong) {
                        songs.append(song)
                    }
                    
                    self.mpd.song_free(mpdSong)
                    mpdSong = self.mpd.get_song(self.connection)
                }
                
                _ = self.mpd.response_finish(self.connection)
            }
            
            DispatchQueue.main.async {
                songsFound(songs)
            }
        }
    }
    
    public func playqueueSongs(start: Int = 0, fetchSize: Int = 30) -> Observable<[Song]> {
        guard start >= 0 && fetchSize > 0 else {
            return Observable
                .just(1)
                .subscribeOn(serialScheduler)
                .map { _ in
                    return [Song]()
            }
        }
        
        return Observable
            .just(1)
            .subscribeOn(serialScheduler)
            .map { _ in
                var songs = [Song]()
                if self.mpd.send_list_queue_range_meta(self.connection, start: UInt32(start), end: UInt32(start + fetchSize)) == true {
                    var mpdSong = self.mpd.get_song(self.connection)
                    while mpdSong != nil {
                        if let song = self.songFromMpdSong(mpdSong: mpdSong) {
                            songs.append(song)
                        }
                        
                        self.mpd.song_free(mpdSong)
                        mpdSong = self.mpd.get_song(self.connection)
                    }
                    
                    _ = self.mpd.response_finish(self.connection)
                }
                
                return songs
            }
    }
    
    /// Fill a generic Song object from an mpdSong
    ///
    /// - Parameter mpdSong: pointer to a mpdSong data structire
    /// - Returns: the filled Song object
    private func songFromMpdSong(mpdSong: OpaquePointer!) -> Song? {
        guard mpdSong != nil else  {
            return nil
        }
        
        var song = Song()
        
        song.id = self.mpd.song_get_uri(mpdSong)
        song.title = self.mpd.song_get_tag(mpdSong, MPD_TAG_TITLE, 0)
        song.album = self.mpd.song_get_tag(mpdSong, MPD_TAG_ALBUM, 0)
        song.artist = self.mpd.song_get_tag(mpdSong, MPD_TAG_ARTIST, 0)
        song.composer = self.mpd.song_get_tag(mpdSong, MPD_TAG_COMPOSER, 0)
        song.length = Int(self.mpd.song_get_duration(mpdSong))
                
        return song
    }
    
    /// Fetch the current status of a controller
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
                playerStatus.playing.shuffleMode = (self.mpd.status_get_random(status) == true) ? .On : .Off
                playerStatus.playing.repeatMode = (self.mpd.status_get_repeat(status) == true) ? .All : .Off
                
                playerStatus.playqueue.length = Int(self.mpd.status_get_queue_length(status))
                playerStatus.playqueue.version = Int(self.mpd.status_get_queue_version(status))
                playerStatus.playqueue.songIndex = Int(self.mpd.status_get_song_pos(status))
            }
            
            if let song = self.mpd.run_current_song(self.connection) {
                defer {
                    self.mpd.song_free(song)
                }
                
                if let song = songFromMpdSong(mpdSong: song) {
                    playerStatus.currentSong = song
                }
            }
        }
        
        return playerStatus
    }
    
    /// Update the ObservablePlayerStatus object. Data is fetched on the serialScheduler,
    /// then the observable objects are updated on the main thread.
    private func updateObservablePlayerStatus() {
        _ = Observable
            .just(1)
            .subscribeOn(serialScheduler)
            .map { [weak self] _ in
                return self?.fetchPlayerStatus()
            }
            .subscribe(onNext: { [weak self] playerStatus in
                self?.observablePlayerStatus.set(playerStatus: playerStatus!)
            })
    }
    
    /// Run a command on the serialScheduler, then update the observable status
    ///
    /// - Parameters:
    ///   - refreshStatus: whether the PlayerStatus must be updated after the call (default = YES)
    ///   - command: the block to execute
    private func runCommand(refreshStatus: Bool = true, command: @escaping () -> Void) {
        _ = Observable
            .just(1)
            .subscribeOn(serialScheduler)
            .subscribe(onNext: { [weak self] _ in
                command()
                if refreshStatus {
                    self?.updateObservablePlayerStatus()
                }
            })
    }
}
