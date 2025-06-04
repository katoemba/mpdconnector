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
import RxSwift
import SwiftMPD

public class MPDControl: ControlProtocol {
    private var playerVolumeAdjustmentKey: String {
        MPDHelper.playerVolumeAdjustmentKey((connectionProperties[ConnectionProperties.name.rawValue] as? String) ?? "NoName")
    }
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
    
    public init(connectionProperties: [String: Any],
                identification: String = "NoID",
                scheduler: SchedulerType? = nil,
                userDefaults: UserDefaults,
                mpdConnector: SwiftMPD.MPDConnector) {
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
        runAsyncCommand() {
            _ = try? await $0.queue.shuffle()
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
        Task {
            _ = try? await mpdConnector.playback.setConsume(consumeMode == .On ? .on : .off)
        }
    }
    
    /// Toggle the consume mode (off -> on -> off)
    ///
    /// - Parameter from: The current consume mode.
    public func toggleConsume() {
        _ = runAsyncCommand() { mpdConnector, playerStatus in
            _ = try? await mpdConnector.playback.setConsume(playerStatus.playing.consumeMode == .On ? .off : .on)
        }
        .subscribe()
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
        Observable<(Song, Playlist)>.fromAsync {
            try? await self.mpdConnector.playlist.playlistadd(name: playlist.id, uri: song.id)
            return (song, playlist)
        }
        .observe(on: MainScheduler.instance)
    }
    
    /// Add an album to the play queue
    ///
    /// - Parameters:
    ///   - album: the album to add
    ///   - addDetails: how to add the song to the playqueue
    /// - Returns: an observable tuple consisting of album and addResponse.
    public func add(_ album: Album, addDetails: AddDetails) -> Observable<(Album, AddResponse)> {
        // First we need to get all the songs on an album, then add them one by one
        let browse = MPDBrowse.init(connectionProperties: connectionProperties, mpdConnector: mpdConnector)
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
        let mpdConnector = self.mpdConnector
        let browse = MPDBrowse.init(connectionProperties: connectionProperties, mpdConnector: mpdConnector)
        return browse.songsOnAlbum(album)
            .flatMap({ (songs) -> Observable<(Album, Playlist)> in
                Observable<(Album, Playlist)>.fromAsync {
                    var executors = [any CommandExecutor]()
                    for song in songs {
                        executors.append(mpdConnector.playlist.playlistaddExecutor(name: playlist.id, uri: song.id))
                    }
                    _ = try? await mpdConnector.batchCommand(executors)
                    return (album, playlist)
                }
            })
            .observe(on: MainScheduler.instance)
    }
    
    /// Add an artist to the play queue
    ///
    /// - Parameters:
    ///   - artist: the artist to add
    ///   - addDetails: how to add the song to the playqueue
    /// - Returns: an observable tuple consisting of artist and addResponse.
    public func add(_ artist: Artist, addDetails: AddDetails) -> Observable<(Artist, AddResponse)> {
        // First we need to get all the songs on an album, then add them one by one
        let browse = MPDBrowse.init(connectionProperties: connectionProperties, mpdConnector: mpdConnector)
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
        let mpdConnector = self.mpdConnector
        return Observable<(Playlist, AddResponse)>.fromAsync {
            var executors = [any CommandExecutor]()
            executors.append(mpdConnector.queue.clearExecutor())
            executors.append(mpdConnector.playlist.loadExecutor(playlist: playlist.id))
            if addDetails.shuffle {
                executors.append(mpdConnector.queue.shuffleExecutor())
            }
            executors.append(mpdConnector.playback.playExecutor(Int(addDetails.startWithSong)))

            try await mpdConnector.batchCommand(executors)

            return (playlist, AddResponse(addDetails, nil))
        }
        .observe(on: MainScheduler.instance)
    }
    
    /// Add a genre to the play queue
    ///
    /// - Parameters:
    ///   - genre: the genre to add
    ///   - addDetails: how to add the folder to the playqueue
    public func add(_ genre: Genre, addDetails: AddDetails) -> Observable<(Genre, AddResponse)> {
        runAsyncCommand { mpdConnector, playerStatus in
            var executors = [any CommandExecutor]()
            executors.append(mpdConnector.queue.clearExecutor())
            executors.append(mpdConnector.database.findaddExecutor(filter: .tagEquals(tag: .genre, value: genre.id)))
            if addDetails.shuffle {
                executors.append(mpdConnector.queue.shuffleExecutor())
            }
            executors.append(mpdConnector.playback.playExecutor(0))
            _ = try? await mpdConnector.batchCommand(executors)
        }
        .map({ (_) -> (Genre, AddResponse) in
            (genre, AddResponse(addDetails, nil))
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
        let browse = MPDBrowse.init(connectionProperties: connectionProperties, mpdConnector: mpdConnector)
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
                    executors.append(mpdConnector.queue.moveExecutor(range: UInt(playerStatus.playqueue.length)...UInt(end), topos: .absolute(UInt(pos))))
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
        Task {
            _ = try? await mpdConnector.queue.move(frompos: from, topos: .absolute(UInt(to)))
        }
    }
    
    /// Remove song from the playqueue
    ///
    /// - Parameter at: the position of the song to remove
    public func deleteSong(_ at: Int) {
        Task {
            _ = try? await mpdConnector.queue.delete(at)
        }
    }
    
    /// Move a song in a playlist to a different position
    ///
    /// - Parameters:
    ///   - playlist: the playlist in which to make the move
    ///   - from: the position of the song to change
    ///   - to: the position to move the song to
    public func moveSong(playlist: Playlist, from: Int, to: Int) {
        Task {
            try? await mpdConnector.playlist.playlistmove(name: playlist.id, from: UInt(from), to: UInt(to))
        }
    }
    
    /// Remove song from a playlist
    ///
    /// - Parameters:
    ///   - playlist: the playlist from which to remove the song
    ///   - at: the position of the song to remove
    public func deleteSong(playlist: Playlist, at: Int) {
        Task {
            try? await mpdConnector.playlist.playlistdelete(name: playlist.id, songpos: UInt(at))
        }
    }
    
    /// Save the current playqueue as a playlist
    ///
    /// - Parameter name: name for the playlist
    public func savePlaylist(_ name: String) {
        Task {
            try? await mpdConnector.playlist.save(name: name)
        }
    }
    
    /// Clear the active playqueue
    public func clearPlayqueue(from: Int?, to: Int?) {
        Task {
            if from == nil && to == nil {
                try? await mpdConnector.queue.clear()
            }
            else {
                _ = runAsyncCommand { mpdConnector, playerStatus in
                    try? await mpdConnector.queue.delete(range: UInt((from ?? 0))...UInt((to ?? playerStatus.playqueue.length)))
                }
                .subscribe()
            }
        }
    }
    
    /// Play a station
    ///
    /// - Parameter station: the station that has to be played
    public func playStation(_ station: Station) {
        Task {
            var executors = [any CommandExecutor]()
            executors.append(mpdConnector.playback.stopExecutor())
            executors.append(mpdConnector.queue.clearExecutor())
            if station.url.hasSuffix(".m3u") || station.url.hasSuffix(".pls") || station.url.contains(".pls?") || station.url.contains(".m3u?") {
                executors.append(mpdConnector.playlist.loadExecutor(playlist: station.url))
            }
            else {
                executors.append(mpdConnector.queue.addExecutor(station.url))
            }
            executors.append(mpdConnector.playback.playExecutor())
            
            try? await mpdConnector.batchCommand(executors)
        }
    }
    
    /// Enable or disable an output
    ///
    /// - Parameters:
    ///   - output: the output to set
    ///   - enabled: true to enable the output, false to disable it
    public func setOutput(_ output: Output, enabled: Bool) {
        Task {
            if let output_id = Int(output.id) {
                if enabled {
                    _ = try? await mpdConnector.output.enableoutput(output_id)
                }
                else {
                    _ = try? await mpdConnector.output.disableoutput(output_id)
                }
            }
        }
    }
    
    /// Toggle an output on or off
    ///
    /// - Parameter output: the output to toggle
    public func toggleOutput(_ output: Output) {
        Task {
            if let output_id = Int(output.id) {
                _ = try? await mpdConnector.output.toggleoutput(output_id)
            }
        }
    }
        
    private func runAsyncCommand(command: @escaping (SwiftMPD.MPDConnector, PlayerStatus) async -> Void) -> Observable<PlayerStatus> {
        let mpdConnector = self.mpdConnector
        let mpdStatus = MPDStatus(connectionProperties: connectionProperties, userDefaults: userDefaults, mpdConnector: mpdConnector)
        
        return Observable<PlayerStatus>.fromAsync {
            guard let playerStatus = try? await mpdStatus.fetchPlayerStatus(mpdConnector) else { return PlayerStatus() }
            await command(mpdConnector, playerStatus)
            
            return PlayerStatus()
        }
        .observe(on: MainScheduler.instance)
    }
    
    private func runAsyncCommand(command: @escaping (SwiftMPD.MPDConnector) async -> Void) -> Observable<PlayerStatus> {
        let mpdConnector = self.mpdConnector

        return Observable<PlayerStatus>.fromAsync {
            await command(mpdConnector)
            
            return PlayerStatus()
        }
        .observe(on: MainScheduler.instance)
    }
}

public extension Observable {
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
