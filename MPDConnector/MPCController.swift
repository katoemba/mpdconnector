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

public class MPDController: ControlProtocol {
    /// Connection to a MPD Player
    public var connection: OpaquePointer?
    private let mpd: MPDProtocol

    /// PlayerStatus object for the player
    public var playerStatus = PlayerStatus()
    public var playqueueLength = 0
    public var playqueueVersion = -1

    private let commandQueue = DispatchQueue(label: "com.katoemba.mpdcontroller")
    
    public var disconnectedHandler: ((_ connection: OpaquePointer, _ error: mpd_error) -> Void)?

    private var _statusTimer: Timer?
    
    public init(mpd: MPDProtocol? = nil,
                connection: OpaquePointer? = nil,
                disconnectedHandler: ((_ connection: OpaquePointer, _ error: mpd_error) -> Void)? = nil) {
        self.mpd = mpd ?? MPDWrapper()
        self.connection = connection
        self.disconnectedHandler = disconnectedHandler
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
        
        return true
    }

    /// Start playback.
    public func play() {
        guard validateConnection() else {
            return
        }
        
        self.commandQueue.async {
            _ = self.mpd.run_play(self.connection)
            self.fetchStatus()
        }
    }
    
    /// Start playback.
    public func play(index: Int) {
        guard validateConnection() else {
            return
        }
        
        guard index >= 0 && index < playqueueLength else {
            return
        }
        
        self.commandQueue.async {
            _ = self.mpd.run_play_pos(self.connection, UInt32(index))
            self.fetchStatus()
        }
    }
    
    /// Pause playback.
    public func pause() {
        guard validateConnection() else {
            return
        }
        
        self.commandQueue.async {
            _ = self.mpd.run_pause(self.connection, true)
            self.fetchStatus()
        }
    }
    
    /// Toggle between play and pause: when paused -> start to play, when playing -> pause.
    public func togglePlayPause() {
        guard validateConnection() else {
            return
        }
        
        self.commandQueue.async {
            _ = self.mpd.run_toggle_pause(self.connection)
            self.fetchStatus()
        }
    }
    
    /// Skip to the next track.
    public func skip() {
        guard validateConnection() else {
            return
        }
        
        self.commandQueue.async {
            _ = self.mpd.run_next(self.connection)
            self.fetchStatus()
        }
    }
    
    /// Go back to the previous track.
    public func back() {
        guard validateConnection() else {
            return
        }
        
        self.commandQueue.async {
            _ = self.mpd.run_previous(self.connection)
            self.fetchStatus()
        }
    }
    
    /// Set the shuffle mode of the player.
    ///
    /// - Parameter shuffleMode: The shuffle mode to use.
    public func setShuffle(shuffleMode: ShuffleMode) {
        guard validateConnection() else {
            return
        }
        
        self.commandQueue.async {
            _ = self.mpd.run_random(self.connection, (shuffleMode == .On) ? true : false)
            self.fetchStatus()
        }
    }
    
    /// Set the repeat mode of the player.
    ///
    /// - Parameter repeatMode: The repeat mode to use.
    public func setRepeat(repeatMode: RepeatMode) {
        guard validateConnection() else {
            return
        }
        
        self.commandQueue.async {
            _ = self.mpd.run_repeat(self.connection, (repeatMode == .Off) ? false : true)
            self.fetchStatus()
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
        
        self.commandQueue.async {
            _ = self.mpd.run_set_volume(self.connection, UInt32(roundf(volume * 100.0)))
            self.fetchStatus()
        }
    }
    
    /// Retrieve the status from the player and fill all relevant elements in the playerStatus object
    public func fetchStatus() {
        // Call validate and beginUpdate on the main thread.
        DispatchQueue.main.async {
            guard self.validateConnection() else {
                return
            }
            
            self.playerStatus.beginUpdate()
            
            // Then perform fetchStatus on the backgound.
            self.commandQueue.async {
                if let status = self.mpd.run_status(self.connection) {
                    defer {
                        self.mpd.status_free(status)
                    }
                    
                    self.playerStatus.volume = Float(self.mpd.status_get_volume(status)) / 100.0
                    self.playerStatus.elapsedTime = Int(self.mpd.status_get_elapsed_time(status))
                    self.playerStatus.trackTime = Int(self.mpd.status_get_total_time(status))
                    
                    self.playerStatus.playingStatus = (self.mpd.status_get_state(status) == MPD_STATE_PLAY) ? .Playing : .Paused
                    self.playerStatus.shuffleMode = (self.mpd.status_get_random(status) == true) ? .On : .Off
                    self.playerStatus.repeatMode = (self.mpd.status_get_repeat(status) == true) ? .All : .Off
                    
                    let length = Int(self.mpd.status_get_queue_length(status))
                    let version = Int(self.mpd.status_get_queue_version(status))
                    if length != self.playqueueLength || version != self.playqueueVersion {
                        // The playqueue has changed. Do something!
                    }
                    
                    self.playerStatus.songIndex = Int(self.mpd.status_get_song_pos(status))
                    self.playqueueLength = length
                    self.playqueueVersion = version
                }
                
                if let song = self.mpd.run_current_song(self.connection) {
                    defer {
                        self.mpd.song_free(song)
                    }
                    
                    self.playerStatus.song = self.mpd.song_get_tag(song, MPD_TAG_TITLE, 0)
                    self.playerStatus.album = self.mpd.song_get_tag(song, MPD_TAG_ALBUM, 0)
                    self.playerStatus.artist = self.mpd.song_get_tag(song, MPD_TAG_ARTIST, 0)
                }
                
                // And finally do an endUpdate on the main thread.
                DispatchQueue.main.async {
                    self.playerStatus.endUpdate()
                }
            }
        }
    }
    
    public func getPlayqueueSongs(start: Int, end: Int,
                                  songsFound: @escaping (([Song]) -> Void)) {
        let actualEnd = min(end, self.playqueueLength)
        
        guard start >= 0 && start < actualEnd else {
            songsFound([])
            return
        }
        
        guard self.validateConnection() else {
            songsFound([])
            return
        }
        
        self.commandQueue.async {
            var songs = [Song]()
            if self.mpd.send_list_queue_range_meta(self.connection, start: UInt32(start), end: UInt32(actualEnd)) == true {
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
    
    private func songFromMpdSong(mpdSong: OpaquePointer!) -> Song? {
        guard mpdSong != nil else  {
            return nil
        }
        
        var song = Song()
        
        song.title = self.mpd.song_get_tag(mpdSong, MPD_TAG_TITLE, 0)
        song.album = self.mpd.song_get_tag(mpdSong, MPD_TAG_ALBUM, 0)
        song.artist = self.mpd.song_get_tag(mpdSong, MPD_TAG_ARTIST, 0)
        song.composer = self.mpd.song_get_tag(mpdSong, MPD_TAG_COMPOSER, 0)
        song.length = Int(self.mpd.song_get_duration(mpdSong))
        
        return song
    }
    
    /// Start listening for status updates on a regular interval (every second). This will also perform an immediate fetchStatus.
    public func startListeningForStatusUpdates() {
        // Start a statusUpdate timer only once
        guard self._statusTimer == nil else {
            return
        }
        
        self.playerStatus = PlayerStatus()
        self.fetchStatus()
        _statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0 , repeats: true, block: { (timer) in
            self.fetchStatus()
        })
    }
    
    /// Stop listening for status updates. Must be called before nilling a MPDPlayer object to prevent retain cycles.
    public func stopListeningForStatusUpdates() {
        guard let timer = self._statusTimer else {
            return
        }
        
        timer.invalidate()
        _statusTimer = nil
    }
}
