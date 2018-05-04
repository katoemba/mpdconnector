//
//  MPCControl.swift
//  MPDConnector
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
            var playingStatus = MPD_STATE_UNKNOWN
            if let status = self.mpd.run_status(connection) {
                playingStatus = self.mpd.status_get_state(status)
                self.mpd.status_free(status)
            }
            
            if playingStatus == MPD_STATE_STOP {
                _ = self.mpd.run_play(connection)
            }
            else {
                _ = self.mpd.run_toggle_pause(connection)
            }
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
            
            // Add songs in a command list, as this can be a longer list.
            _ = self.mpd.command_list_begin(connection, discrete_ok: false)
            for song in songsToAdd {
                _ = self.mpd.send_add_id_to(connection, uri: song.id, to: pos)
                pos = pos + 1
            }
            _ = self.mpd.command_list_end(connection)
            _ = self.mpd.response_finish(connection)

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
    ///   - startWithSong: the position of the song (within the album) to start playing
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
    ///   - startWithSong: the position of the song (within the playlist) to start playing
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

    /// Add a genre to the play queue
    ///
    /// - Parameters:
    ///   - genre: the genre to add
    ///   - addMode: how to add the songs to the playqueue
    ///   - shuffle: whether or not to shuffle the songs before adding them
    public func addGenre(_ genre: String, addMode: AddMode, shuffle: Bool) {
        MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties)
            .observeOn(serialScheduler)
            .subscribe(onNext: { (connection) in
                guard let connection = connection else { return }
                do {
                    _ = self.mpd.run_clear(connection)

                    try self.mpd.search_add_db_songs(connection, exact: true)
                    try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_GENRE, value: genre)
                    try self.mpd.search_commit(connection)
                    
                    _ = self.mpd.response_finish(connection)

                    if shuffle {
                        _ = self.mpd.run_shuffle(connection)
                    }
                    
                    _ = self.mpd.run_play_pos(connection, 0)

                    self.mpd.connection_free(connection)
                }
                catch {
                    print(self.mpd.connection_get_error_message(connection))
                    _ = self.mpd.connection_clear_error(connection)
                    self.mpd.connection_free(connection)
                }
            })
            .disposed(by: bag)
    }
    
    /// Add a folder to the play queue
    ///
    /// - Parameters:
    ///   - album: the album to add
    ///   - addMode: how to add the songs to the playqueue
    ///   - shuffle: whether or not to shuffle the songs before adding them
    ///   - startWithSong: the position of the song (within the folder) to start playing
    public func addFolder(_ folder: Folder, addMode: AddMode, shuffle: Bool, startWithSong: UInt32) {
        // First we need to get all the songs on an album, then add them one by one
        let browse = MPDBrowse.init(mpd: mpd, connectionProperties: connectionProperties)
        browse.fetchFolderContents(parentFolder: folder)
            .map({ (folderContents) -> [Song] in
                var songs = [Song]()
                for folderContent in folderContents {
                    if case let .song(song) = folderContent {
                        songs.append(song)
                    }
                }
                return songs
            })
            .subscribe(onNext: { (songs) in
                self.addSongs(songs, addMode: addMode, shuffle: shuffle, startWithSong: startWithSong)
            })
            .disposed(by: bag)
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
        
        // Connect and run the command on the serial scheduler to prevent any blocking.
        MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties)
            .subscribeOn(serialScheduler)
            .observeOn(serialScheduler)
            .subscribe(onNext: { (connection) in
                guard let connection = connection else { return }
                command(connection)
                mpd.connection_free(connection)
            }, onError: { (error) in
            })
            .disposed(by: bag)
    }
}
