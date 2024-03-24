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
import SwiftMPD

public class MPDControl: ControlProtocol {
    private var playerVolumeAdjustmentKey: String {
        MPDHelper.playerVolumeAdjustmentKey((connectionProperties[ConnectionProperties.name.rawValue] as? String) ?? "NoName")
    }
    private let mpd: MPDProtocol
    private var identification = ""
    private var connectionProperties: [String: Any]
    private let userDefaults: UserDefaults
    private let mpdConnector: SwiftMPD.MPDConnector
    
    private let bag = DisposeBag()
    private var serialScheduler: SchedulerType
    public var volumeAdjustment: Float? {
        get {
            userDefaults.value(forKey: playerVolumeAdjustmentKey) as? Float
        }
        set {
            if let adjustment = newValue {
                userDefaults.set(adjustment, forKey: playerVolumeAdjustmentKey)
            }
            else {
                userDefaults.removeObject(forKey: playerVolumeAdjustmentKey)
            }
        }
    }
    
    public init(mpd: MPDProtocol? = nil,
                connectionProperties: [String: Any],
                identification: String = "NoID",
                scheduler: SchedulerType? = nil,
                userDefaults: UserDefaults,
                mpdConnector: SwiftMPD.MPDConnector) {
        self.mpd = mpd ?? MPDWrapper()
        self.identification = identification
        self.connectionProperties = connectionProperties
        self.userDefaults = userDefaults
        self.mpdConnector = mpdConnector
        
        self.serialScheduler = scheduler ?? SerialDispatchQueueScheduler.init(qos: .background, internalSerialQueueName: "com.katoemba.mpdcontrol")
        
        HelpMePlease.allocUp(name: "MPDControl")
    }
    
    /// Cleanup connection object
    deinit {
        HelpMePlease.allocDown(name: "MPDControl")
    }
    
    /// Start playback.
    public func play() -> Observable<PlayerStatus> {
        runAsyncCommand {
            _ = try? await $0.playback.play()
        }
    }
    
    /// Start playback of a specific track.
    ///
    /// - Parameter index: index in the playqueue to play
    public func play(index: Int) -> Observable<PlayerStatus> {
        guard index >= 0 else {
            return Observable.empty()
        }
        
        return runAsyncCommand {
            _ = try? await $0.playback.play(index)
        }
    }
    
    /// Pause playback.
    public func pause() -> Observable<PlayerStatus> {
        runAsyncCommand {
            _ = try? await $0.playback.pause()
        }
    }
    
    /// Stop playback.
    public func stop() -> Observable<PlayerStatus> {
        runAsyncCommand {
            _ = try? await $0.playback.seek(songpos: 0, time: 0.0)
            _ = try? await $0.playback.stop()
        }
    }
    
    /// Toggle between play and pause: when paused -> start to play, when playing -> pause.
    public func togglePlayPause() -> Observable<PlayerStatus> {
        runAsyncCommand { connector, playerStatus in
            if playerStatus.playing.playPauseMode == .Playing {
                _ = try? await connector.playback.pause()
            }
            else {
                _ = try? await connector.playback.play()
            }
        }
    }
    
    /// Skip to the next track.
    public func skip() -> Observable<PlayerStatus> {
        runAsyncCommand {
            _ = try? await $0.playback.next()
        }
    }
    
    /// Go back to the previous track.
    public func back() -> Observable<PlayerStatus> {
        runAsyncCommand {
            _ = try? await $0.playback.previous()
        }
    }
    
    /// Set the random mode of the player.
    ///
    /// - Parameter randomMode: The random mode to use.
    public func setRandom(_ randomMode: RandomMode) -> Observable<PlayerStatus> {
        runAsyncCommand {
            _ = try? await $0.playback.setRandom((randomMode == .On) ? .on : .off)
        }
    }
    
    /// Toggle the random mode (off -> on -> off)
    ///
    /// - Parameter from: The current random mode.
    public func toggleRandom() -> Observable<PlayerStatus> {
        runAsyncCommand() { mpdConnector, playerStatus in
            _ = try? await mpdConnector.playback.setRandom(playerStatus.playing.randomMode == .On ? .off : .on)
        }
    }
    
    /// Shuffle the current playqueue
    public func shufflePlayqueue() -> Observable<PlayerStatus> {
        
        return runCommandWithStatus()  { connection in
            _ = self.mpd.run_shuffle(connection)
        }
    }
    
    /// Set the repeat mode of the player.
    ///
    /// - Parameter repeatMode: The repeat mode to use.
    public func setRepeat(_ repeatMode: RepeatMode) -> Observable<PlayerStatus> {
        runAsyncCommand {
            var repeatState: OnOffState
            var singleState: OnOffOneShotState
            switch repeatMode {
            case .Off:
                repeatState = .off
                singleState = .off
            case .All, .Album:
                repeatState = .on
                singleState = .off
            case .Single:
                repeatState = .on
                singleState = .on
            }
            
            _ = try? await $0.playback.setRepeat(repeatState)
            _ = try? await $0.playback.setSingle(singleState)
        }
    }
    
    /// Toggle the repeat mode (off -> all -> single -> off)
    ///
    /// - Parameter from: The current repeat mode.
    public func toggleRepeat() -> Observable<PlayerStatus> {
        runAsyncCommand { mpdConnector, playerStatus in
            var repeatState: OnOffState
            var singleState: OnOffOneShotState
            switch playerStatus.playing.repeatMode {
            case .Off:
                // Switch to All
                repeatState = .on
                singleState = .off
            case .All, .Album:
                // Switch to Single
                repeatState = .on
                singleState = .on
            case .Single:
                // Switch to Off
                repeatState = .off
                singleState = .off
            }
            
            _ = try? await mpdConnector.playback.setRepeat(repeatState)
            _ = try? await mpdConnector.playback.setSingle(singleState)
        }
    }
    
    /// Set the random mode of the player.
    ///
    /// - Parameter consumeMode: The consume mode to use.
    public func setConsume(_ consumeMode: ConsumeMode) {
        _ = runAsyncCommand() {
            _ = try? await $0.playback.setConsume(consumeMode == .On ? .on : .off)
        }
    }
    
    /// Toggle the consume mode (off -> on -> off)
    ///
    /// - Parameter from: The current consume mode.
    public func toggleConsume() {
        _ = runAsyncCommand() { mpdConnector, playerStatus in
            _ = try? await mpdConnector.playback.setConsume(playerStatus.playing.consumeMode == .On ? .off : .on)
        }
    }
    
    /// Set the volume of the player.((randomMode == .On)?,true:false)
    ///
    /// - Parameter volume: The volume to set. Must be a value between 0.0 and 1.0, values outside this range will be ignored.
    /// - Returns: an observable for the up-to-date playerStatus after the action is completed.
    public func setVolume(_ volume: Float) -> Observable<PlayerStatus> {
        runAsyncCommand {
            _ = try? await $0.playback.setVolume(Int32(roundf(MPDHelper.adjustedVolumeToPlayer(volume, volumeAdjustment: self.volumeAdjustment) * 100.0)))
        }
    }
    
    /// Adjust the volume of the player.
    ///
    /// - Parameter adjustment: The adjustment to be made. Negative values will decrease the volume, positive values will increase the volume.
    /// - Returns: an observable for the up-to-date playerStatus after the action is completed.
    public func adjustVolume(_ adjustment: Float) -> Observable<PlayerStatus> {
        runAsyncCommand { connector, playerStatus in
            let volume = adjustment < 0 ? max(playerStatus.volume + adjustment, 0.0) : min(playerStatus.volume + adjustment, 1.0)
            _ = try? await connector.playback.setVolume(Int32(roundf(MPDHelper.adjustedVolumeToPlayer(volume, volumeAdjustment: self.volumeAdjustment) * 100.0)))
        }
    }
    
    /// Seek to a position in the current song
    ///
    /// - Parameter seconds: seconds in the current song, must be <= length of the song
    /// - Returns: an observable for the up-to-date playerStatus after the action is completed.
    public func setSeek(seconds: UInt32) -> Observable<PlayerStatus> {
        runAsyncCommand { connector, playerStatus in
            if seconds < playerStatus.currentSong.length {
                _ = try? await connector.playback.seekcur(time: Float(seconds))
            }
        }
    }
    
    /// Seek to a relative position in the current song
    ///
    /// - Parameter percentage: relative position in the current song, must be between 0.0 and 1.0
    /// - Returns: an observable for the up-to-date playerStatus after the action is completed.
    public func setSeek(percentage: Float) -> Observable<PlayerStatus> {
        runAsyncCommand { connector, playerStatus in
            let seconds = UInt32(percentage * Float(playerStatus.currentSong.length))
            if seconds < playerStatus.currentSong.length {
                _ = try? await connector.playback.seekcur(time: Float(seconds))
            }
        }
    }
    
    /// Add a batch of songs to the play queue
    ///
    /// - Parameters:
    ///   - songs: array of songs to add
    ///   - addDetails: how to add the song to the playqueue
    /// - Returns: an observable tuple consisting of songs and addResponse.
    public func add(_ songs: [Song], addDetails: AddDetails) -> Observable<([Song], AddResponse)> {
        runAsyncCommand { mpdConnector, playerStatus in
            var pos = 0
            
            var executors = [any CommandExecutor]()
            switch addDetails.addMode {
            case .replace:
                executors.append(mpdConnector.queue.clearExecutor())
            case .addNext, .addNextAndPlay:
                pos = playerStatus.playqueue.songIndex + 1
            case .addAtEnd:
                pos = playerStatus.playqueue.length
            }
            
            let songsToAdd = addDetails.shuffle ? songs.shuffled() : songs

            for song in songsToAdd {
                executors.append(mpdConnector.queue.addidExecutor(song.id, position: pos))
                pos = pos + 1
            }

            if addDetails.addMode == .replace {
                executors.append(mpdConnector.playback.playExecutor(Int(addDetails.startWithSong)))
            }
            else if addDetails.addMode == .addNextAndPlay {
                executors.append(mpdConnector.playback.playExecutor(Int(playerStatus.playqueue.songIndex + 1)))
            }
            _ = try? await mpdConnector.batchCommand(executors)
        }
        .map({ (_) -> ([Song], AddResponse) in
            return (songs, AddResponse(addDetails, nil))
        })
    }
    
    /// Add a song to the play queue
    ///
    /// - Parameters:
    ///   - song: the song to add
    ///   - addDetails: how to add the song to the playqueue
    /// - Returns: an observable tuple consisting of song and addResponse.
    public func add(_ song: Song, addDetails: AddDetails) -> Observable<(Song, AddResponse)> {
        return add([song], addDetails: addDetails)
            .map({ (songs, addResponse) -> (Song, AddResponse) in
                (song, addResponse)
            })
    }
    
    /// Add a song to a playlist
    ///
    /// - Parameters:
    ///   - song: the song to add
    ///   - playlist: the playlist to add the song to
    /// - Returns: an observable tuple consisting of song and playlist.
    public func addToPlaylist(_ song: Song, playlist: Playlist) -> Observable<(Song, Playlist)> {
        return runCommandWithStatus()  { connection in
            _ = self.mpd.run_playlist_add(connection, name: playlist.id, path: song.id)
        }
        .map({ (_) -> (Song, Playlist) in
            (song, playlist)
        })
    }
    
    /// Add an album to the play queue
    ///
    /// - Parameters:
    ///   - album: the album to add
    ///   - addDetails: how to add the song to the playqueue
    /// - Returns: an observable tuple consisting of album and addResponse.
    public func add(_ album: Album, addDetails: AddDetails) -> Observable<(Album, AddResponse)> {
        // First we need to get all the songs on an album, then add them one by one
        let browse = MPDBrowse.init(mpd: mpd, connectionProperties: connectionProperties, mpdConnector: mpdConnector)
        return browse.songsOnAlbum(album)
            .flatMap({ (songs) -> Observable<(Album, AddResponse)> in
                self.add(songs, addDetails: addDetails)
                    .map({ (songs, addResponse) -> (Album, AddResponse) in
                        (album, addResponse)
                    })
            })
    }
    
    /// Add an album to a playlist
    ///
    /// - Parameters:
    ///   - album: the album to add
    ///   - playlist: the playlist to add the song to
    /// - Returns: an observable tuple consisting of album and playlist.
    public func addToPlaylist(_ album: Album, playlist: Playlist) -> Observable<(Album, Playlist)> {
        // First we need to get all the songs on an album, then add them one by one
        let browse = MPDBrowse.init(mpd: mpd, connectionProperties: connectionProperties, mpdConnector: mpdConnector)
        return browse.songsOnAlbum(album)
            .flatMap({ (songs) -> Observable<(Album, Playlist)> in
                return self.runCommandWithStatus()  { connection in
                    for song in songs {
                        _ = self.mpd.run_playlist_add(connection, name: playlist.id, path: song.id)
                    }
                }
                .map({ (_) -> (Album, Playlist) in
                    (album, playlist)
                })
            })
        
    }
    
    /// Add an artist to the play queue
    ///
    /// - Parameters:
    ///   - artist: the artist to add
    ///   - addDetails: how to add the song to the playqueue
    /// - Returns: an observable tuple consisting of artist and addResponse.
    public func add(_ artist: Artist, addDetails: AddDetails) -> Observable<(Artist, AddResponse)> {
        // First we need to get all the songs on an album, then add them one by one
        let browse = MPDBrowse.init(mpd: mpd, connectionProperties: connectionProperties, mpdConnector: mpdConnector)
        return browse.songsByArtist(artist)
            .flatMap({ (songs) -> Observable<(Artist, AddResponse)> in
                self.add(songs, addDetails: addDetails)
                    .map({ (songs, addResponse) -> (Artist, AddResponse) in
                        (artist, addResponse)
                    })
            })
    }
    
    /// Add a playlist to the play queue
    ///
    /// - Parameters:
    ///   - playlist: the playlist to add
    ///   - addDetails: how to add the playlist to the playqueue
    /// - Returns: an observable tuple consisting of playlist and addResponse.
    public func add(_ playlist: Playlist, addDetails: AddDetails) -> Observable<(Playlist, AddResponse)> {
        return runCommandWithStatus()  { connection in
            _ = self.mpd.run_clear(connection)
            _ = self.mpd.run_load(connection, name: playlist.id)
            if addDetails.shuffle {
                _ = self.mpd.run_shuffle(connection)
            }
            
            _ = self.mpd.run_play_pos(connection, addDetails.startWithSong)
        }
        .map({ (playerStatus) -> (Playlist, AddResponse) in
            (playlist, AddResponse(addDetails, playerStatus))
        })
    }
    
    /// Add a genre to the play queue
    ///
    /// - Parameters:
    ///   - genre: the genre to add
    ///   - addDetails: how to add the folder to the playqueue
    public func add(_ genre: Genre, addDetails: AddDetails) -> Observable<(Genre, AddResponse)> {
        runCommandWithStatus()  { connection in
            do {
                _ = self.mpd.run_clear(connection)
                
                try self.mpd.search_add_db_songs(connection, exact: true)
                try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_GENRE, value: genre.id)
                try self.mpd.search_commit(connection)
                
                _ = self.mpd.response_finish(connection)
                
                if addDetails.shuffle {
                    _ = self.mpd.run_shuffle(connection)
                }
                
                _ = self.mpd.run_play_pos(connection, 0)
            }
            catch {
                print(self.mpd.connection_get_error_message(connection))
                _ = self.mpd.connection_clear_error(connection)
            }
        }
        .map({ (playerStatus) -> (Genre, AddResponse) in
            (genre, AddResponse(addDetails, playerStatus))
        })
    }
    
    /// Add a folder to the play queue
    ///
    /// - Parameters:
    ///   - folder: the folder to add
    ///   - addDetails: how to add the folder to the playqueue
    /// - Returns: an observable tuple consisting of folder and addResponse.
    public func add(_ folder: Folder, addDetails: AddDetails) -> Observable<(Folder, AddResponse)> {
        // First we need to get all the songs on an album, then add them one by one
        let browse = MPDBrowse.init(mpd: mpd, connectionProperties: connectionProperties, mpdConnector: mpdConnector)
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
            .flatMap({ (songs) -> Observable<(Folder, AddResponse)> in
                self.add(songs, addDetails: addDetails)
                    .map({ (songs, addResponse) -> (Folder, AddResponse) in
                        (folder, addResponse)
                    })
            })
    }
    
    /// Add a folder recursively to the play queue
    ///
    /// - Parameters:
    ///   - folder: the folder to add
    ///   - addDetails: how to add the folder to the playqueue
    /// - Returns: an observable tuple consisting of folder and addResponse.
    public func addRecursive(_ folder: Folder, addDetails: AddDetails) -> Observable<(Folder, AddResponse)> {
        runAsyncCommand { mpdConnector, playerStatus in
            var pos = 0
            
            var executors = [any CommandExecutor]()
            switch addDetails.addMode {
            case .replace:
                executors.append(mpdConnector.queue.clearExecutor())
            case .addNext, .addNextAndPlay:
                pos = playerStatus.playqueue.songIndex + 1
            case .addAtEnd:
                pos = playerStatus.playqueue.length
            }
            
            executors.append(mpdConnector.queue.addExecutor(folder.path))

            if addDetails.addMode == .replace {
                if addDetails.shuffle == true {
                    executors.append(mpdConnector.queue.shuffleExecutor())
                }
                executors.append(mpdConnector.playback.playExecutor(Int(addDetails.startWithSong)))
            }
            else if addDetails.addMode == .addNext || addDetails.addMode == .addNextAndPlay {
                let statusExecutor = mpdConnector.status.statusExecutor()
                executors.append(statusExecutor)
                _ = try? await mpdConnector.batchCommand(executors)

                executors.removeAll()
                if let end = try? statusExecutor.processResults().playlistlength {
                    executors.append(mpdConnector.queue.moveExecutor(range: playerStatus.playqueue.length...end, topos: pos))
                }
                
                if addDetails.addMode == .addNextAndPlay {
                    executors.append(mpdConnector.playback.playExecutor(pos))
                }
            }
            _ = try? await mpdConnector.batchCommand(executors)
        }
        .map({ (playerStatus) -> (Folder, AddResponse) in
            (folder, AddResponse(addDetails, playerStatus))
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
        MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: serialScheduler, forceCleanup: false)
            .observe(on: serialScheduler)
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
        let userDefaults = self.userDefaults
        let connectionProperties = self.connectionProperties
        let mpdConnector = self.mpdConnector
        
        // Connect and run the command on the serial scheduler to prevent any blocking.
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: serialScheduler, forceCleanup: false)
            .observe(on: serialScheduler)
            .do(onNext: { (mpdConnection) in
                guard let connection = mpdConnection?.connection else { return }
                
                command(connection)
            }, onError: { (error) in
            })
            .flatMap { (mpdConnection) -> Observable<PlayerStatus> in
                guard let connection = mpdConnection?.connection else { return Observable.empty() }
                
                return MPDStatus(mpd: mpd, connectionProperties: connectionProperties, userDefaults: userDefaults, mpdConnector: mpdConnector).getStatus()
            }
            .observe(on: MainScheduler.instance)
    }
    
    private func runAsyncCommand(command: @escaping (SwiftMPD.MPDConnector, PlayerStatus) async -> Void) -> Observable<PlayerStatus> {
        let mpdConnector = self.mpdConnector
        let mpdStatus = MPDStatus(mpd: mpd, connectionProperties: connectionProperties, userDefaults: userDefaults, mpdConnector: mpdConnector)
        
        Task {
            await command(mpdConnector, await mpdStatus.fetchPlayerStatus())
        }
        
        return Observable.empty()
    }
    
    private func runAsyncCommand(command: @escaping (SwiftMPD.MPDConnector) async -> Void) -> Observable<PlayerStatus> {
        let mpdConnector = self.mpdConnector

        Task {
            await command(mpdConnector)
        }
        
        return Observable.empty()
    }
}

extension Observable {
    static func fromAsync<T>(_ fn: @escaping () async throws -> T) -> Observable<T> {
        .create { observer in
            let task = Task {
                do {
                    let result: T = try await fn()
                    
                    observer.onNext(result)
                    observer.onCompleted()
                }
                catch {
                    observer.onError(error)
                }
            }
            return Disposables.create { task.cancel() }
        }
    }
}
