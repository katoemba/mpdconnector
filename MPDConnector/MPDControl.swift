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
    private let consumeMode = BehaviorRelay<ConsumeMode>(value: .Off)
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
            .map { (playerStatus) -> ConsumeMode in
                playerStatus.playing.consumeMode
            }
            .distinctUntilChanged()
            .bind(to: consumeMode)
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
    public func play() -> Observable<PlayerStatus> {
        return runCommandWithStatus()  { connection in
            _ = self.mpd.run_play(connection)
            }
            .observeOn(MainScheduler.instance)
    }
    
    /// Start playback of a specific track.
    ///
    /// - Parameter index: index in the playqueue to play
    public func play(index: Int) -> Observable<PlayerStatus> {
        guard index >= 0 else {
            return Observable.empty()
        }
        
        return runCommandWithStatus()  { connection in
                _ = self.mpd.run_play_pos(connection, UInt32(index))
            }
    }
    
    /// Pause playback.
    public func pause() -> Observable<PlayerStatus> {
        return runCommandWithStatus()  { connection in
                _ = self.mpd.run_pause(connection, true)
            }
    }
    
    /// Stop playback.
    public func stop() -> Observable<PlayerStatus> {
        return runCommandWithStatus()  { connection in
                _ = self.mpd.run_seek(connection, pos: 0, t: 0)
                _ = self.mpd.run_stop(connection)
            }
    }
    
    /// Toggle between play and pause: when paused -> start to play, when playing -> pause.
    public func togglePlayPause() -> Observable<PlayerStatus> {
        return runCommandWithStatus()  { connection in
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
    public func skip() -> Observable<PlayerStatus> {
        return runCommandWithStatus()  { connection in
                _ = self.mpd.run_next(connection)
            }
    }
    
    /// Go back to the previous track.
    public func back() -> Observable<PlayerStatus> {
        return runCommandWithStatus()  { connection in
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
    
    /// Set the random mode of the player.
    ///
    /// - Parameter consumeMode: The consume mode to use.
    public func setConsume(consumeMode: ConsumeMode) {
        runCommand()  { connection in
            _ = self.mpd.run_consume(connection, (consumeMode == .On) ? true : false)
        }
    }
    
    /// Toggle the consume mode (off -> on -> off)
    ///
    /// - Parameter from: The current consume mode.
    public func toggleConsume() {
        runCommand()  { connection in
            _ = self.mpd.run_consume(connection, (self.consumeMode.value == .On) ? false : true)
        }
    }
    
    /// Set the volume of the player.((randomMode == .On)?,true:false)
    ///
    /// - Parameter volume: The volume to set. Must be a value between 0.0 and 1.0, values outside this range will be ignored.
    public func setVolume(volume: Float) {
        guard volume >= 0.0, volume <= 1.0 else {
            return
        }
        
        runCommand()  { connection in
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
    private func addSongs(_ songs: [Song], addMode: AddMode, shuffle: Bool, startWithSong: UInt32 = 0) -> Observable<([Song], Song, AddMode, Bool, PlayerStatus)> {
        return runCommandWithStatus()  { connection in
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
            
                let batchSize = UInt32(40)
                // Smaller sizes are added directly, trying to work around an occasional crash in mpd_command_list_end.
                if songsToAdd.count <= batchSize {
                    for song in songsToAdd {
                        _ = self.mpd.run_add_id_to(connection, uri: song.id, to: pos)
                        pos = pos + 1
                    }
                }
                else {
                    // Add songs in a command list, as this can be a longer list.
                    var index = UInt32(0)
                    while index < songsToAdd.count {
                        _ = self.mpd.command_list_begin(connection, discrete_ok: false)
                        let last = min(index + batchSize, UInt32(songsToAdd.count))
                        while index < last {
                            let song = songsToAdd[Int(index)]
                            _ = self.mpd.send_add_id_to(connection, uri: song.id, to: pos)
                            pos = pos + 1
                            index = index + 1
                        }
                        _ = self.mpd.command_list_end(connection)
                        _ = self.mpd.response_finish(connection)
                    }
                }

                if addMode == .replace {
                    _ = self.mpd.run_play_pos(connection, startWithSong)
                }
                else if addMode == .addNextAndPlay {
                    _ = self.mpd.run_play_pos(connection, UInt32(self.songIndex.value + 1))
                }
            }
            .map({ (playerStatus) -> ([Song], Song, AddMode, Bool, PlayerStatus) in
                (songs, songs[Int(startWithSong)], addMode, shuffle, playerStatus)
            })
    }

    /// Add a song to the play queue
    ///
    /// - Parameters:
    ///   - song: the song to add
    ///   - addMode: how to add the songs to the playqueue
    public func addSong(_ song: Song, addMode: AddMode) -> Observable<(Song, AddMode, PlayerStatus)> {
        return addSongs([song], addMode: addMode, shuffle: false)
            .map({ (songs, song, addMode, shuffle, playerStatus) -> (Song, AddMode, PlayerStatus) in
                (song, addMode, playerStatus)
            })
    }
    
    /// Add a song to a playlist
    ///
    /// - Parameters:
    ///   - song: the song to add
    ///   - playlist: the playlist to add the song to
    public func addSongToPlaylist(_ song: Song, playlist: Playlist) {
        runCommand()  { connection in
            _ = self.mpd.run_playlist_add(connection, name: playlist.id, path: song.id)
        }
    }
    
    /// Add a batch of songs to the play queue
    ///
    /// - Parameters:
    ///   - songs: array of songs to add
    ///   - addMode: how to add the song to the playqueue
    public func addSongs(_ songs: [Song], addMode: AddMode) -> Observable<([Song], AddMode, PlayerStatus)> {
        return addSongs(songs, addMode: addMode, shuffle: false)
            .map({ (songs, song, addMode, shuffle, playerStatus) -> ([Song], AddMode, PlayerStatus) in
                (songs, addMode, playerStatus)
            })
    }
    
    /// Add an album to the play queue
    ///
    /// - Parameters:
    ///   - album: the album to add
    ///   - addMode: how to add the songs to the playqueue
    ///   - shuffle: whether or not to shuffle the songs before adding them
    ///   - startWithSong: the position of the song (within the album) to start playing
    public func addAlbum(_ album: Album, addMode: AddMode, shuffle: Bool, startWithSong: UInt32) -> Observable<(Album, Song, AddMode, Bool, PlayerStatus)> {
        // First we need to get all the songs on an album, then add them one by one
        let browse = MPDBrowse.init(mpd: mpd, connectionProperties: connectionProperties)
        return browse.songsOnAlbum(album)
            .flatMap({ (songs) -> Observable<(Album, Song, AddMode, Bool, PlayerStatus)> in
                self.addSongs(songs, addMode: addMode, shuffle: shuffle, startWithSong: startWithSong)
                    .map({ (songs, song, addMode, shuffle, playerStatus) -> (Album, Song, AddMode, Bool, PlayerStatus) in
                        (album, song, addMode, shuffle, playerStatus)
                    })
            })
    }
    
    /// Add an artist to the play queue
    ///
    /// - Parameters:
    ///   - artist: the artist to add
    ///   - addMode: how to add the songs to the playqueue
    ///   - shuffle: whether or not to shuffle the songs before adding them
    public func addArtist(_ artist: Artist, addMode: AddMode, shuffle: Bool) -> Observable<(Artist, AddMode, Bool, PlayerStatus)> {
        // First we need to get all the songs on an album, then add them one by one
        let browse = MPDBrowse.init(mpd: mpd, connectionProperties: connectionProperties)
        return browse.songsByArtist(artist)
            .flatMap({ (songs) -> Observable<(Artist, AddMode, Bool, PlayerStatus)> in
                self.addSongs(songs, addMode: addMode, shuffle: shuffle)
                    .map({ (songs, song, addMode, shuffle, playerStatus) -> (Artist, AddMode, Bool, PlayerStatus) in
                        (artist, addMode, shuffle, playerStatus)
                    })
        })
    }
    
    /// Add a playlist to the play queue
    ///
    /// - Parameters:
    ///   - playlist: the playlist to add
    ///   - addMode: how to add the song to the playqueue
    ///   - shuffle: whether or not to shuffle the playlist
    ///   - startWithSong: the position of the song (within the playlist) to start playing
    public func addPlaylist(_ playlist: Playlist, shuffle: Bool, startWithSong: UInt32) -> Observable<(Playlist, Song, Bool, PlayerStatus)> {
        return runCommandWithStatus()  { connection in
                _ = self.mpd.run_clear(connection)
                _ = self.mpd.run_load(connection, name: playlist.id)
                if shuffle {
                    _ = self.mpd.run_shuffle(connection)
                }
            
                _ = self.mpd.run_play_pos(connection, startWithSong)
            }
            .map({ (playerStatus) -> (Playlist, Song, Bool, PlayerStatus) in
                (playlist, playerStatus.currentSong, shuffle, playerStatus)
            })
    }

    /// Add a genre to the play queue
    ///
    /// - Parameters:
    ///   - genre: the genre to add
    ///   - addMode: how to add the songs to the playqueue
    ///   - shuffle: whether or not to shuffle the songs before adding them
    public func addGenre(_ genre: String, addMode: AddMode, shuffle: Bool) {
        MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: serialScheduler)
            .observeOn(serialScheduler)
            .subscribe(onNext: { (mpdConnection) in
                guard let connection = mpdConnection?.connection else { return }
                
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
                }
                catch {
                    print(self.mpd.connection_get_error_message(connection))
                    _ = self.mpd.connection_clear_error(connection)
                }
            })
            .disposed(by: bag)
    }
    
    /// Add a folder to the play queue
    ///
    /// - Parameters:
    ///   - folder: the folder to add
    ///   - addMode: how to add the songs to the playqueue
    ///   - shuffle: whether or not to shuffle the songs before adding them
    ///   - startWithSong: the position of the song (within the folder) to start playing
    public func addFolder(_ folder: Folder, addMode: AddMode, shuffle: Bool, startWithSong: UInt32) -> Observable<(Folder, Song, AddMode, Bool, PlayerStatus)> {
        // First we need to get all the songs on an album, then add them one by one
        let browse = MPDBrowse.init(mpd: mpd, connectionProperties: connectionProperties)
        return browse.fetchFolderContents(parentFolder: folder)
            .map({ (folderContents) -> [Song] in
                var songs = [Song]()
                for folderContent in folderContents {
                    if case let .song(song) = folderContent {
                        songs.append(song)
                    }
                }
                return songs
            })
            .flatMap({ (songs) -> Observable<(Folder, Song, AddMode, Bool, PlayerStatus)> in
                self.addSongs(songs, addMode: addMode, shuffle: shuffle, startWithSong: startWithSong)
                    .map({ (songs, song, addMode, shuffle, playerStatus) -> (Folder, Song, AddMode, Bool, PlayerStatus) in
                        (folder, song, addMode, shuffle, playerStatus)
                    })
            })
    }
    
    /// Add a folder recursively to the play queue
    ///
    /// - Parameters:
    ///   - folder: the folder to add
    ///   - addMode: how to add the songs to the playqueue
    ///   - shuffle: whether or not to shuffle the songs before adding them
    public func addRecursiveFolder(_ folder: Folder, addMode: AddMode, shuffle: Bool) -> Observable<(Folder, AddMode, Bool, PlayerStatus)> {
        return runCommandWithStatus()  { connection in
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
            
                _ = self.mpd.run_add(connection, uri: folder.path)
                if addMode == .replace {
                    if shuffle == true {
                        _ = self.mpd.run_shuffle(connection)
                    }
                    _ = self.mpd.run_play_pos(connection, 0)
                }
                else if addMode == .addNext || addMode == .addNextAndPlay {
                    var end = UInt32(0)
                    if let status = self.mpd.run_status(connection) {
                        defer {
                            self.mpd.status_free(status)
                        }
                        end = self.mpd.status_get_queue_length(status)
                    }
                    _ = self.mpd.run_move_range(connection, start: UInt32(self.endIndex.value), end: end, to: pos)

                    if addMode == .addNextAndPlay {
                        _ = self.mpd.run_play_pos(connection, pos)
                    }
                    
                }
            }
            .map({ (playerStatus) -> (Folder, AddMode, Bool, PlayerStatus) in
                (folder, addMode, shuffle, playerStatus)
            })
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
    
    /// Move a song in a playlist to a different position
    ///
    /// - Parameters:
    ///   - playlist: the playlist in which to make the move
    ///   - from: the position of the song to change
    ///   - to: the position to move the song to
    public func moveSong(playlist: Playlist, from: Int, to: Int) {
        runCommand()  { connection in
            _ = self.mpd.run_playlist_move(connection, name: playlist.id, from: UInt32(from), to: UInt32(to))
        }
    }
    
    /// Remove song from a playlist
    ///
    /// - Parameters:
    ///   - playlist: the playlist from which to remove the song
    ///   - at: the position of the song to remove
    public func deleteSong(playlist: Playlist, at: Int) {
        runCommand()  { connection in
            _ = self.mpd.run_playlist_delete(connection, name: playlist.id, pos: UInt32(at))
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
    
    /// Clear the active playqueue
    public func clearPlayqueue() {
        runCommand()  { connection in
            _ = self.mpd.run_clear(connection)
        }
    }
    
    /// Play a station
    ///
    /// - Parameter station: the station that has to be played
    public func playStation(_ station: Station) {
        runCommand()  { connection in
            _ = self.mpd.run_stop(connection)
            _ = self.mpd.run_clear(connection)
            if station.url.hasSuffix(".m3u") || station.url.hasSuffix(".pls") || station.url.contains(".pls?") || station.url.contains(".m3u?") {
                _ = self.mpd.run_load(connection, name: station.url)
            }
            else {
                _ = self.mpd.run_add(connection, uri: station.url)
            }
            _ = self.mpd.run_play(connection)
        }
    }
    
    /// Enable or disable an output
    ///
    /// - Parameters:
    ///   - output: the output to set
    ///   - enabled: true to enable the output, false to disable it
    public func setOutput(_ output: Output, enabled: Bool) {
        runCommand()  { connection in
            if let output_id = UInt32(output.id) {
                if enabled {
                    _ = self.mpd.run_enable_output(connection, output_id: output_id)
                }
                else {
                    _ = self.mpd.run_disable_output(connection, output_id: output_id)
                }
            }
        }
    }
    
    /// Toggle an output on or off
    ///
    /// - Parameter output: the output to toggle
    public func toggleOutput(_ output: Output) {
        runCommand()  { connection in
            if let output_id = UInt32(output.id) {
                _ = self.mpd.run_toggle_output(connection, output_id: output_id)
            }
        }
    }

    /// Run a command on a background thread, then optionally trigger an update to the player status
    ///
    /// - Parameters:
    ///   - command: the block to execute
    private func runCommand(command: @escaping (OpaquePointer) -> Void) {
        let mpd = self.mpd
        
        // Connect and run the command on the serial scheduler to prevent any blocking.
        MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: serialScheduler)
            .observeOn(serialScheduler)
            .subscribe(onNext: { (mpdConnection) in
                guard let connection = mpdConnection?.connection else { return }

                command(connection)
            }, onError: { (error) in
            })
            .disposed(by: bag)
    }

    /// Run a command on a background thread, then optionally trigger an update to the player status
    ///
    /// - Parameters:
    ///   - command: the block to execute
    private func runCommandWithStatus(command: @escaping (OpaquePointer) -> Void) -> Observable<PlayerStatus> {
        let mpd = self.mpd
        let connectionProperties = self.connectionProperties
        
        // Connect and run the command on the serial scheduler to prevent any blocking.
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: serialScheduler)
            .observeOn(serialScheduler)
            .do(onNext: { (mpdConnection) in
                guard let connection = mpdConnection?.connection else { return }
                
                command(connection)
            }, onError: { (error) in
            })
            .flatMap { (mpdConnection) -> Observable<PlayerStatus> in
                guard let connection = mpdConnection?.connection else { return Observable.empty() }
                
                return Observable.just(MPDStatus(connectionProperties: connectionProperties).fetchPlayerStatus(connection))
            }
            .observeOn(MainScheduler.instance)
    }
}
