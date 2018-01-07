//
//  MPCControl.swift
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

public class MPDControl: ControlProtocol {    
    private let mpd: MPDProtocol
    private var identification = ""
    private var connectionProperties: [String: Any]
    
    private let bag = DisposeBag()
    
    public init(mpd: MPDProtocol? = nil,
                connectionProperties: [String: Any],
                identification: String = "NoID") {
        self.mpd = mpd ?? MPDWrapper()
        self.identification = identification
        self.connectionProperties = connectionProperties
        
        HelpMePlease.allocUp(name: "MPDControl")
    }
    
    /// Cleanup connection object
    deinit {
        HelpMePlease.allocDown(name: "MPDControl")
    }
    
    /// Start playback.
    public func play() {
        runCommand()  { connection in
            _ = self.mpd.run_play(connection)
        }
    }
    
    /// Start playback of a specific track.
    ///
    /// - Parameter index: index in the playqueue to play
    public func play(index: Int) {
        guard index >= 0 else {
            return
        }
        
        runCommand()  { connection in
            _ = self.mpd.run_play_pos(connection, UInt32(index))
        }
    }
    
    /// Pause playback.
    public func pause() {
        runCommand()  { connection in
            _ = self.mpd.run_pause(connection, true)
        }
    }
    
    /// Toggle between play and pause: when paused -> start to play, when playing -> pause.
    public func togglePlayPause() {
        runCommand()  { connection in
            _ = self.mpd.run_toggle_pause(connection)
        }
    }
    
    /// Skip to the next track.
    public func skip() {
        runCommand()  { connection in
            _ = self.mpd.run_next(connection)
        }
    }
    
    /// Go back to the previous track.
    public func back() {
        runCommand()  { connection in
            _ = self.mpd.run_previous(connection)
        }
    }
    
    /// Set the shuffle mode of the player.
    ///
    /// - Parameter randomMode: The random mode to use.
    public func setRandom(randomMode: RandomMode) {
        runCommand()  { connection in
            _ = self.mpd.run_random(connection, (randomMode == .On) ? true : false)
        }
    }
    
    /// Toggle the random mode (off -> on -> off)
    ///
    /// - Parameter from: The current random mode.
    public func toggleRandom(from: RandomMode) {
        runCommand()  { connection in
            _ = self.mpd.run_random(connection, (from == .On) ? false : true)
        }
    }
    
    /// Set the repeat mode of the player.
    ///
    /// - Parameter repeatMode: The repeat mode to use.
    public func setRepeat(repeatMode: RepeatMode) {
        runCommand()  { connection in
            switch repeatMode {
                case .Off:
                    _ = self.mpd.run_single(connection, false)
                    _ = self.mpd.run_repeat(connection, false)
                case .All:
                    _ = self.mpd.run_repeat(connection, true)
                    _ = self.mpd.run_single(connection, false)
                case .Single:
                    _ = self.mpd.run_single(connection, true)
                    _ = self.mpd.run_repeat(connection, true)
                case .Album:
                    _ = self.mpd.run_repeat(connection, true)
                    _ = self.mpd.run_single(connection, false)
            }
        }
    }
    
    /// Toggle the repeat mode (off -> all -> single -> off)
    ///
    /// - Parameter from: The current repeat mode.
    public func toggleRepeat(from: RepeatMode) {
        if from == .Off {
            self.setRepeat(repeatMode: .All)
        }
        else if from == .All {
            self.setRepeat(repeatMode: .Single)
        }
        else if from == .Single {
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
        
        runCommand(refreshStatus: false)  { connection in
            _ = self.mpd.run_set_volume(connection, UInt32(roundf(volume * 100.0)))
        }
    }
    
    /*
    /// Get an array of songs from the playqueue.
    ///
    /// - Parameters
    ///   - start: the first song to fetch, zero-based.
    ///   - end: the last song to fetch, zero-based.
    /// Returns: an array of filled Songs objects.
    public func getPlayqueueSongs(start: Int, end: Int) -> [Song] {
        guard start >= 0, start < end else {
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
     */
    
    /// Add a song to the play queue
    ///
    /// - Parameters:
    ///   - song: the song to add
    public func addSong(_ song: Song) {
        runCommand()  { connection in
            _ = self.mpd.run_add(connection, uri: song.id)
        }
    }
    
    /// Add an album to the play queue
    ///
    /// - Parameters:
    ///   - album: the album to add
    public func addAlbum(_ album: Album) {
        // First we need to get all the songs on an album, then add them one by one
        let browse = MPDBrowse.init(mpd: mpd, connectionProperties: connectionProperties)
        browse.songsOnAlbum(album)
            .subscribe(onNext: { (songs) in
                self.runCommand()  { connection in
                    for song in songs {
                        _ = self.mpd.run_add(connection, uri: song.id)
                    }
                }
            })
            .disposed(by: bag)
    }
    
    /// Run a command on a background thread, then optionally trigger an update to the player status
    ///
    /// - Parameters:
    ///   - refreshStatus: whether the PlayerStatus must be updated after the call (default = YES)
    ///   - command: the block to execute
    private func runCommand(refreshStatus: Bool = true, command: @escaping (OpaquePointer) -> Void) {
        let mpd = self.mpd
        
        MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties)
            .observeOn(ConcurrentDispatchQueueScheduler(qos: .background))
            .subscribe(onNext: { (connection) in
                command(connection)
                mpd.connection_free(connection)
            }, onError: { (error) in
            })
            .disposed(by: bag)
    }
}
