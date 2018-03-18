//
//  MPCControl.swift
//  MPDConnector
//
//  Created by Berrie Kremers on 26-08-17.
//  Copyright © 2017 Katoemba Software. All rights reserved.
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
    private var serialScheduler: SchedulerType
    
    private let songIndex = BehaviorRelay<Int>(value: 0)
    private let endIndex = BehaviorRelay<Int>(value: 0)
    private let repeatMode = BehaviorRelay<RepeatMode>(value: .Off)
    private let randomMode = BehaviorRelay<RandomMode>(value: .Off)
    private let currentSong = BehaviorRelay<Song?>(value: nil)
    
    public init(mpd: MPDProtocol? = nil,
                connectionProperties: [String: Any],
                identification: String = "NoID",
                scheduler: SchedulerType? = nil,
                playerStatusObservable: Observable<PlayerStatus>) {
        self.mpd = mpd ?? MPDWrapper()
        self.identification = identification
        self.connectionProperties = connectionProperties
        
        self.serialScheduler = scheduler ?? SerialDispatchQueueScheduler.init(qos: .background, internalSerialQueueName: "com.katoemba.mpdcontrol")
        
        playerStatusObservable
            .map { (playerStatus) -> Int in
                playerStatus.playqueue.songIndex
            }
            .distinctUntilChanged()
            .bind(to: songIndex)
            .disposed(by: bag)

        playerStatusObservable
            .map { (playerStatus) -> Int in
                playerStatus.playqueue.length
            }
            .distinctUntilChanged()
            .bind(to: endIndex)
            .disposed(by: bag)

        playerStatusObservable
            .map { (playerStatus) -> RepeatMode in
                playerStatus.playing.repeatMode
            }
            .distinctUntilChanged()
            .bind(to: repeatMode)
            .disposed(by: bag)
        
        playerStatusObservable
            .map { (playerStatus) -> RandomMode in
                playerStatus.playing.randomMode
            }
            .distinctUntilChanged()
            .bind(to: randomMode)
            .disposed(by: bag)
        
        playerStatusObservable
            .map { (playerStatus) -> Song in
                playerStatus.currentSong
            }
            .distinctUntilChanged()
            .bind(to: currentSong)
            .disposed(by: bag)

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
    
    /// Set the random mode of the player.
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
    public func toggleRandom() {
        runCommand()  { connection in
            _ = self.mpd.run_random(connection, (self.randomMode.value == .On) ? false : true)
        }
    }
    
    /// Shuffle the current playqueue
    public func shufflePlayqueue() {
        runCommand()  { connection in
            _ = self.mpd.run_shuffle(connection)
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
    public func toggleRepeat() {
        let from = self.repeatMode.value
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
    
    /// Seek to a position in the current song
    ///
    /// - Parameter seconds: seconds in the current song, must be <= length of the song
    public func setSeek(seconds: UInt32) {
        guard let song = currentSong.value else { return }
        guard seconds < song.length else { return }
        
        runCommand()  { connection in
            _ = self.mpd.run_seek(connection, pos: UInt32(song.position), t: seconds)
        }
    }
    
    /// Seek to a relative position in the current song
    ///
    /// - Parameter percentage: relative position in the current song, must be between 0.0 and 1.0
    public func setSeek(percentage: Float) {
        guard let song = currentSong.value else { return }
        guard percentage >= 0.0 && percentage <= 1.0 else { return }

        setSeek(seconds: UInt32(percentage * Float(song.length)))
    }
    
    /// add an array of songs to the playqueue
    ///
    /// - Parameters:
    ///   - songs: an array of Song objects
    ///   - addMode: how to add the songs to the playqueue
    ///   - shuffle: whether or not to shuffle the songs before adding them
    private func addSongs(_ songs: [Song], addMode: AddMode, shuffle: Bool, startWithSong: UInt32 = 0) {
        runCommand()  { connection in
            var pos = UInt32(0)
            
            switch addMode {
            case .replace:
                _ = self.mpd.run_clear(connection)
            case .addNext:
                pos = UInt32(self.songIndex.value + 1)
            case .addNextAndPlay:
                pos = UInt32(self.songIndex.value + 1)
            case .addAtEnd:
                pos = UInt32(self.endIndex.value)
            }
            
            let songsToAdd = shuffle ? songs.shuffled() : songs
            
            for song in songsToAdd {
                print("Adding \(song.id) at position \(pos)")
                _ = self.mpd.run_add_id_to(connection, uri: song.id, to: pos)
                pos = pos + 1
            }

            if addMode == .replace {
                _ = self.mpd.run_play_pos(connection, startWithSong)
            }
            else if addMode == .addNextAndPlay {
                _ = self.mpd.run_play_pos(connection, UInt32(self.songIndex.value + 1))
            }
        }
    }

    /// Add a song to the play queue
    ///
    /// - Parameters:
    ///   - song: the song to add
    ///   - addMode: how to add the songs to the playqueue
    public func addSong(_ song: Song, addMode: AddMode) {
        addSongs([song], addMode: addMode, shuffle: false)
    }
    
    /// Add a batch of songs to the play queue
    ///
    /// - Parameters:
    ///   - songs: array of songs to add
    ///   - addMode: how to add the song to the playqueue
    public func addSongs(_ songs: [Song], addMode: AddMode) {
        addSongs(songs, addMode: addMode, shuffle: false)
    }
    
    /// Add an album to the play queue
    ///
    /// - Parameters:
    ///   - album: the album to add
    ///   - addMode: how to add the songs to the playqueue
    ///   - shuffle: whether or not to shuffle the songs before adding them
    public func addAlbum(_ album: Album, addMode: AddMode, shuffle: Bool, startWithSong: UInt32) {
        // First we need to get all the songs on an album, then add them one by one
        let browse = MPDBrowse.init(mpd: mpd, connectionProperties: connectionProperties)
        browse.songsOnAlbum(album)
            .subscribe(onNext: { (songs) in
                self.addSongs(songs, addMode: addMode, shuffle: shuffle, startWithSong: startWithSong)
            })
            .disposed(by: bag)
    }
    
    /// Add an artist to the play queue
    ///
    /// - Parameters:
    ///   - artist: the artist to add
    ///   - addMode: how to add the songs to the playqueue
    ///   - shuffle: whether or not to shuffle the songs before adding them
    public func addArtist(_ artist: Artist, addMode: AddMode, shuffle: Bool) {
        // First we need to get all the songs on an album, then add them one by one
        let browse = MPDBrowse.init(mpd: mpd, connectionProperties: connectionProperties)
        browse.songsByArtist(artist)
            .subscribe(onNext: { (songs) in
                self.addSongs(songs, addMode: addMode, shuffle: shuffle)
            })
            .disposed(by: bag)
    }
    
    /// Add a playlist to the play queue
    ///
    /// - Parameters:
    ///   - playlist: the playlist to add
    ///   - addMode: how to add the song to the playqueue
    ///   - shuffle: whether or not to shuffle the playlist
    public func addPlaylist(_ playlist: Playlist, addMode: AddMode, shuffle: Bool, startWithSong: UInt32) {
        runCommand()  { connection in
            switch addMode {
            case .replace:
                _ = self.mpd.run_clear(connection)
            default:
                break
            }

            _ = self.mpd.run_load(connection, name: playlist.id)
            if shuffle {
                _ = self.mpd.run_shuffle(connection)
            }
            
            _ = self.mpd.run_play_pos(connection, startWithSong)
        }
    }

    /// Move a song in the playqueue to a different position
    ///
    /// - Parameters:
    ///   - from: the position of the song to change
    ///   - to: the position to move the song to
    public func moveSong(from: Int, to: Int) {
        runCommand()  { connection in
            _ = self.mpd.run_move(connection, from: UInt32(from), to: UInt32(to))
        }
    }
    
    /// Remove song from the playqueue
    ///
    /// - Parameter at: the position of the song to remove
    public func deleteSong(_ at: Int) {
        runCommand()  { connection in
            _ = self.mpd.run_delete(connection, pos: UInt32(at))
        }
    }
    
    /// Save the current playqueue as a playlist
    ///
    /// - Parameter name: name for the playlist
    public func savePlaylist(_ name: String) {
        runCommand()  { connection in
            _ = self.mpd.run_save(connection, name: name)
        }
    }
    
    /// Run a command on a background thread, then optionally trigger an update to the player status
    ///
    /// - Parameters:
    ///   - refreshStatus: whether the PlayerStatus must be updated after the call (default = YES)
    ///   - command: the block to execute
    private func runCommand(refreshStatus: Bool = true, command: @escaping (OpaquePointer) -> Void) {
        let mpd = self.mpd
        
        MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties)
            .observeOn(serialScheduler)
            .subscribe(onNext: { (connection) in
                command(connection)
                mpd.connection_free(connection)
            }, onError: { (error) in
            })
            .disposed(by: bag)
    }
}
