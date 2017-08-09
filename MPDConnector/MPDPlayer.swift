//
//  StatusManager.swift
//  MPDConnector
//
//  Created by Berrie Kremers on 05-08-17.
//  Copyright © 2017 Kaotemba Software. All rights reserved.
//

import Foundation
import ConnectorProtocol
import libmpdclient

public class MPDPlayer: ControlProtocol {
    /// Connection to a MPD Player
    private var _connection: OpaquePointer? = nil
    private let _mpd: MPDProtocol
    
    private var _statusTimer: Timer?

    /// PlayerStatus object for the player
    public var playerStatus = PlayerStatus()

    // MARK: - Initialization
    public init(mpd: MPDProtocol) {
        _mpd = mpd
        _connection = mpd.connection_new("localhost", UInt32(6600), 1000)
        fetchStatus()
    }
    
    /// Cleanup connection object
    deinit {
        if let connection = _connection {
            _mpd.connection_free(connection)
            _connection = nil
        }
    }
    
    /// Start listening for status updates on a regular interval (every second)
    public func startListeningForStatusUpdates() {
        _statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0 , repeats: true, block: { (timer) in
            self.fetchStatus()
        })
    }

    /// Stop listening for status updates. Must be called before nilling a MPDPlayer object to prevent retain cycles.
    public func stopListeningForStatusUpdates() {
        if let timer = _statusTimer {
            timer.invalidate()
            _statusTimer = nil
        }
    }

    // MARK: - ControlProtocol Implementations

    /// Start playback.
    public func play() {
        if let connection = _connection {
            _ = _mpd.run_play(connection)
        }
    }
    
    /// Start playback.
    public func pause() {
        if let connection = _connection {
            _ = _mpd.run_pause(connection, true)
        }
    }
    
    /// Skip to the next track.
    public func skip() {
        if let connection = _connection {
            _ = _mpd.run_next(connection)
        }
    }
    
    /// Go back to the previous track.
    public func back() {
        if let connection = _connection {
            _ = _mpd.run_previous(connection)
        }
    }
    
    /// Set the shuffle mode of the player.
    ///
    /// - Parameter shuffleMode: The shuffle mode to use.
    public func setShuffle(shuffleMode: ShuffleMode) {
        if let connection = _connection {
            _ = _mpd.run_random(connection, (shuffleMode == .On) ? true : false)
        }
    }
    
    /// Set the repeat mode of the player.
    ///
    /// - Parameter repeatMode: The repeat mode to use.
    public func setRepeat(repeatMode: RepeatMode) {
        if let connection = _connection {
            _ = _mpd.run_repeat(connection, (repeatMode == .Off) ? false : true)
        }
    }
    
    /// Set the volume of the player.((shuffleMode == .On)?,true:false)
    ///
    /// - Parameter volume: The volume to set. Must be a value between 0.0 and 1.0, values outside this range will be ignored.
    public func setVolume(volume: Float) {
        if volume < 0.0 || volume > 1.0 {
            return
        }
        
        if let connection = _connection {
            _ = _mpd.run_set_volume(connection, UInt32(roundf(volume * 100.0)))
        }
    }
    
    /// Retrieve the status from the player and fill all relevant elements in the playerStatus object
    public func fetchStatus() {
        if let connection = _connection {
            playerStatus.beginUpdate()
            
            if let status = _mpd.run_status(connection) {
                playerStatus.volume = Float(_mpd.status_get_volume(status)) / 100.0
                playerStatus.elapsedTime = Int(_mpd.status_get_elapsed_time(status))
                playerStatus.trackTime = Int(_mpd.status_get_total_time(status))
                
                playerStatus.playingStatus = (_mpd.status_get_state(status) == MPD_STATE_PLAY) ? .Playing : .Paused
                playerStatus.shuffleMode = (_mpd.status_get_random(status) == true) ? .On : .Off
                playerStatus.repeatMode = (_mpd.status_get_repeat(status) == true) ? .All : .Off
                
                _mpd.status_free(status)
            }
            
            if let song = _mpd.run_current_song(connection) {
                playerStatus.song = _mpd.song_get_tag(song, MPD_TAG_TITLE, 0)
                playerStatus.album = _mpd.song_get_tag(song, MPD_TAG_ALBUM, 0)
                playerStatus.artist = _mpd.song_get_tag(song, MPD_TAG_ARTIST, 0)
                
                _mpd.song_free(song)
            }
            
            playerStatus.endUpdate()
        }
    }
}
