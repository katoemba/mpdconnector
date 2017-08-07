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
    private var connection: OpaquePointer? = nil
    
    private var statusTimer = Timer()

    /// PlayerStatus object for the player
    public var playerStatus = PlayerStatus()

    // MARK: - Initialization
    public init() {
        connection = mpd_connection_new("localhost", UInt32(6600), 1000)
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0 , repeats: true, block: { (timer) in
            self.updateStatus()
        })
        
        updateStatus()
    }
    
    // MARK: - ControlProtocol Implementations

    /// Start playback.
    public func play() {
        if let conn = connection {
            mpd_run_play(conn)
        }
    }
    
    /// Start playback.
    public func pause() {
        if let conn = connection {
            mpd_run_pause(conn, false)
        }
    }
    
    /// Skip to the next track.
    public func skip() {
        if let conn = connection {
            mpd_run_next(conn)
        }
    }
    
    /// Go back to the previous track.
    public func back() {
        if let conn = connection {
            mpd_run_previous(conn)
        }
    }
    
    /// Set the shuffle mode of the player.
    ///
    /// - Parameter shuffleMode: The shuffle mode to use.
    public func setShuffle(shuffleMode: ShuffleMode) {
        if let conn = connection {
            mpd_run_random(conn, (shuffleMode == .On) ? true : false)
        }
    }
    
    /// Set the repeat mode of the player.
    ///
    /// - Parameter repeatMode: The repeat mode to use.
    public func setRepeat(repeatMode: RepeatMode) {
        if let conn = connection {
            mpd_run_repeat(conn, (repeatMode == .Off) ? false : true)
        }
    }
    
    /// Set the volume of the player.((shuffleMode == .On)?,true:false)
    ///
    /// - Parameter volume: The volume to set. Must be a value between 0.0 and 1.0, values outside this range will be ignored.
    public func setVolume(volume: Float) {
        if volume < 0.0 || volume > 1.0 {
            return
        }
        
        if let conn = connection {
            mpd_run_set_volume(conn, UInt32(roundf(volume * 100.0)))
        }
    }
    
    /// Convert a raw mpd-string to a standard Swift string.
    ///
    /// - Parameter mpdString: Pointer to a null-terminated (unsigned char) string.
    /// - Returns: Converted string, or empty string "" in case conversion failed.
    func stringFromMPDString(_ mpdString: UnsafePointer<Int8>?) -> String {
        if let string = mpdString {
            let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: string), count: Int(strlen(string)), deallocator: .none)
            return String(data: data, encoding: .utf8) ?? ""
        }
        return ""
    }

    /// Retrieve the status from the player and fill all relevant elements in the playerStatus object
    func updateStatus() {
        if let conn = connection {
            playerStatus.beginUpdate()
            
            if let status = mpd_run_status(conn) {
                playerStatus.volume = Float(mpd_status_get_volume(status)) / 100.0
                playerStatus.elapsedTime = Int(roundf(Float(mpd_status_get_elapsed_ms(status)) / 1000.0))
                playerStatus.trackTime = Int(mpd_status_get_total_time(status))
                
                playerStatus.playingStatus = (mpd_status_get_state(status) == MPD_STATE_PLAY) ? .Playing : .Paused
                playerStatus.shuffleMode = (mpd_status_get_random(status) == true) ? .On : .Off
                playerStatus.repeatMode = (mpd_status_get_repeat(status) == true) ? .All : .Off
            }
            
            if let song = mpd_run_current_song(conn) {
                playerStatus.song = stringFromMPDString(mpd_song_get_tag(song, MPD_TAG_TITLE, 0))
                playerStatus.album = stringFromMPDString(mpd_song_get_tag(song, MPD_TAG_ALBUM, 0))
                playerStatus.artist = stringFromMPDString(mpd_song_get_tag(song, MPD_TAG_ARTIST, 0))
            }
            
            playerStatus.endUpdate()
        }
    }
}
