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
import RxCocoa

public class MPDController: ControlProtocol {
    /// Connection to a MPD Player
    public var connection: OpaquePointer?
    private let mpd: MPDProtocol
    private var identification = ""

    /// PlayerStatus object for the player
    private var reloadTrigger = PublishSubject<Int>()
    private var _playerStatus = Variable<PlayerStatus>(PlayerStatus())
    public var playerStatus : Driver<PlayerStatus> {
        get {
            return _playerStatus.asDriver()
        }
    }
    
    private let _serialScheduler = SerialDispatchQueueScheduler(internalSerialQueueName: "com.katoemba.mpdconnector.controller")
    public var serialScheduler : SerialDispatchQueueScheduler {
        get {
            return _serialScheduler
        }
    }
    public var disconnectedHandler: ((_ connection: OpaquePointer, _ error: mpd_error) -> Void)?
    
    private let bag = DisposeBag()
    
    public init(mpd: MPDProtocol? = nil,
                connection: OpaquePointer? = nil,
                identification: String = "NoID",
                disconnectedHandler: ((_ connection: OpaquePointer, _ error: mpd_error) -> Void)? = nil) {
        self.mpd = mpd ?? MPDWrapper()
        self.connection = connection
        self.identification = identification
        self.disconnectedHandler = disconnectedHandler
        
        let manualStatusUpdateStream = reloadTrigger.asObservable()
        let timerStatusUpdateStream = Observable<Int>
            .timer(RxTimeInterval(0.1), period: RxTimeInterval(1.0), scheduler: serialScheduler)
        
        Observable.of(manualStatusUpdateStream, timerStatusUpdateStream)
            .merge()
            .observeOn(serialScheduler)
            .map { [weak self] _ -> PlayerStatus in
                guard let strongSelf = self else {
                    return PlayerStatus.init()
                }
                
                return strongSelf.getPlayerStatus()
            }
            .subscribe(onNext: { [weak self] playerStatus in
                guard let strongSelf = self else {
                    return
                }
                
                strongSelf._playerStatus.value = playerStatus
            })
            .disposed(by: bag)
    }
    
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
        else if error != MPD_ERROR_SUCCESS {
            print("Error when validating connection: \(self.mpd.connection_get_error_message(connection))")
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
    /// - Parameter randomMode: The shuffle mode to use.
    public func setRandom(randomMode: RandomMode) {
        guard validateConnection() else {
            return
        }
        guard randomMode != _playerStatus.value.playing.randomMode else {
            return
        }
        
        self.runCommand {
            _ = self.mpd.run_random(self.connection, (randomMode == .On) ? true : false)
        }
    }
    
    /// Toggle the random mode (off -> on -> off)
    public func toggleRandom() {
        guard validateConnection() else {
            return
        }
        
        self.runCommand {
            _ = self.mpd.run_random(self.connection, (self._playerStatus.value.playing.randomMode == .On) ? false : true)
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
            switch repeatMode {
                case .Off:
                    _ = self.mpd.run_single(self.connection, false)
                    _ = self.mpd.run_repeat(self.connection, false)
                case .All:
                    _ = self.mpd.run_repeat(self.connection, true)
                    _ = self.mpd.run_single(self.connection, false)
                case .Single:
                    _ = self.mpd.run_single(self.connection, true)
                    _ = self.mpd.run_repeat(self.connection, true)
                case .Album:
                    _ = self.mpd.run_repeat(self.connection, true)
                    _ = self.mpd.run_single(self.connection, false)
            }
        }
    }
    
    /// Toggle the repeat mode (off -> all -> single -> off)
    public func toggleRepeat() {
        guard validateConnection() else {
            return
        }
        
        if self._playerStatus.value.playing.repeatMode == .Off {
            self.setRepeat(repeatMode: .All)
        }
        else if self._playerStatus.value.playing.repeatMode == .All {
            self.setRepeat(repeatMode: .Single)
        }
        else if self._playerStatus.value.playing.repeatMode == .Single {
            self.setRepeat(repeatMode: .Off)
        }
    }
    
    /// Set the volume of the player.((randomMode == .On)?,true:false)
    ///
    /// - Parameter volume: The volume to set. Must be a value between 0.0 and 1.0, values outside this range will be ignored.
    public func setVolume(volume: Float) {
        guard volume >= 0.0, volume <= 1.0 else {
            return
        }
        
        guard validateConnection() else {
            return
        }
        
        self.runCommand(refreshStatus: false)  {
            _ = self.mpd.run_set_volume(self.connection, UInt32(roundf(volume * 100.0)))
            }
    }
    
    /// Get an array of songs from the playqueue.
    ///
    /// - Parameters
    ///   - start: the first song to fetch, zero-based.
    ///   - end: the last song to fetch, zero-based.
    /// Returns: an array of filled Songs objects.
    public func getPlayqueueSongs(start: Int, end: Int) -> [Song] {
        guard start >= 0 else {
            return []
        }
        
        guard self.validateConnection() else {
            return []
        }
        
        var songs = [Song]()
        if self.mpd.send_list_queue_range_meta(self.connection, start: UInt32(start), end: UInt32(end)) == true {
            var mpdSong = self.mpd.get_song(self.connection)
            var position = start
            while mpdSong != nil {
                if var song = MPDController.songFromMpdSong(mpd: mpd, mpdSong: mpdSong) {
                    song.position = position
                    songs.append(song)
                    
                    position += 1
                }
                
                self.mpd.song_free(mpdSong)
                mpdSong = self.mpd.get_song(self.connection)
            }
            
            _ = self.mpd.response_finish(self.connection)
        }
        
        return songs
    }
    
    /// Fill a generic Song object from an mpdSong
    ///
    /// - Parameter mpdSong: pointer to a mpdSong data structire
    /// - Returns: the filled Song object
    public static func songFromMpdSong(mpd: MPDProtocol, mpdSong: OpaquePointer!) -> Song? {
        guard mpdSong != nil else  {
            return nil
        }
        
        var song = Song()
        
        song.id = mpd.song_get_uri(mpdSong)
        if song.id.starts(with: "spotify:") {
            song.source = .Spotify
        }
        else if song.id.starts(with: "tunein:") {
            song.source = .TuneIn
        }
        else if song.id.starts(with: "podcast+") {
            song.source = .Podcast
        }
        else {
            song.source = .Local
        }
        song.title = mpd.song_get_tag(mpdSong, MPD_TAG_TITLE, 0)
        song.album = mpd.song_get_tag(mpdSong, MPD_TAG_ALBUM, 0)
        song.artist = mpd.song_get_tag(mpdSong, MPD_TAG_ARTIST, 0)
        song.albumartist = mpd.song_get_tag(mpdSong, MPD_TAG_ALBUM_ARTIST, 0)
        song.composer = mpd.song_get_tag(mpdSong, MPD_TAG_COMPOSER, 0)
        song.genre = mpd.song_get_tag(mpdSong, MPD_TAG_GENRE, 0)
        song.length = Int(mpd.song_get_duration(mpdSong))
        song.name = mpd.song_get_tag(mpdSong, MPD_TAG_NAME, 0)
        song.date = mpd.song_get_tag(mpdSong, MPD_TAG_DATE, 0)
        song.performer = mpd.song_get_tag(mpdSong, MPD_TAG_PERFORMER, 0)
        song.comment = mpd.song_get_tag(mpdSong, MPD_TAG_COMMENT, 0)
        song.disc = mpd.song_get_tag(mpdSong, MPD_TAG_DISC, 0)
        song.musicbrainzArtistId = mpd.song_get_tag(mpdSong, MPD_TAG_MUSICBRAINZ_ARTISTID, 0)
        song.musicbrainzAlbumId = mpd.song_get_tag(mpdSong, MPD_TAG_MUSICBRAINZ_ALBUMID, 0)
        song.musicbrainzAlbumArtistId = mpd.song_get_tag(mpdSong, MPD_TAG_MUSICBRAINZ_ALBUMARTISTID, 0)
        song.musicbrainzTrackId = mpd.song_get_tag(mpdSong, MPD_TAG_MUSICBRAINZ_TRACKID, 0)
        song.musicbrainzReleaseId = mpd.song_get_tag(mpdSong, MPD_TAG_MUSICBRAINZ_RELEASETRACKID, 0)
        song.originalDate = mpd.song_get_tag(mpdSong, MPD_TAG_ORIGINAL_DATE, 0)
        song.sortArtist = mpd.song_get_tag(mpdSong, MPD_TAG_ARTIST_SORT, 0)
        song.sortAlbumArtist = mpd.song_get_tag(mpdSong, MPD_TAG_ALBUM_ARTIST_SORT, 0)
        song.sortAlbum = mpd.song_get_tag(mpdSong, MPD_TAG_ALBUM_SORT, 0)

        return song
    }
    
    /// Get the current status of a controller
    ///
    /// - Returns: a filled PlayerStatus struct
    public func getPlayerStatus() -> PlayerStatus {
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
            
            if let song = self.mpd.run_current_song(self.connection) {
                defer {
                    self.mpd.song_free(song)
                }
                
                if let song = MPDController.songFromMpdSong(mpd: mpd, mpdSong: song) {
                    playerStatus.currentSong = song
                }
            }
        }
        
        return playerStatus
    }
    
    /// Run a command on the serialScheduler, then update the observable status
    ///
    /// - Parameters:
    ///   - refreshStatus: whether the PlayerStatus must be updated after the call (default = YES)
    ///   - command: the block to execute
    private func runCommand(refreshStatus: Bool = true, command: @escaping () -> Void) {
        _ = Observable
            .just(1)
            .observeOn(serialScheduler)
            .subscribe(onNext: { [weak self] _ in
                guard let strongSelf = self else {
                    return
                }
                
                command()
                if refreshStatus {
                    strongSelf.reloadTrigger.onNext(1)
                }
            })
            //.disposed(by: bag)
    }
}
