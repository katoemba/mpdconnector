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
import SwiftMPD

final public class MPDControl: ControlProtocol {
    private var identification = ""
    private var connectionProperties: [String: Any]
    private let userDefaults: UserDefaults
    private let mpdConnector: SwiftMPD.MPDConnector
    
    public init(connectionProperties: [String: Any],
                identification: String = "NoID",
                userDefaults: UserDefaults,
                mpdConnector: SwiftMPD.MPDConnector) {
        self.identification = identification
        self.connectionProperties = connectionProperties
        self.userDefaults = userDefaults
        self.mpdConnector = mpdConnector
    }
    
    /// Start playback.
    public func play() async throws {
        try await mpdConnector.playback.play()
    }
    
    /// Start playback of a specific track.
    ///
    /// - Parameter index: index in the playqueue to play
    public func play(index: Int) async throws {
        try await mpdConnector.playback.play(index)
    }
    
    /// Pause playback.
    public func pause() async throws {
        try await mpdConnector.playback.pause()
    }
    
    /// Stop playback.
    public func stop() async throws {
        try await mpdConnector.playback.seek(songpos: 0, time: 0.0)
        try await mpdConnector.playback.stop()
    }
    
    /// Toggle between play and pause: when paused -> start to play, when playing -> pause.
    public func togglePlayPause(from playerStatus: PlayerStatus) async throws {
        if playerStatus.playing.playPauseMode == .playing {
            try await mpdConnector.playback.pause()
        }
        else {
            try await mpdConnector.playback.play()
        }
    }
    
    /// Skip to the next track.
    public func skip() async throws {
        try await mpdConnector.playback.next()
    }
    
    /// Go back to the previous track.
    public func back() async throws {
        try await mpdConnector.playback.previous()
    }
    
    /// Set the random mode of the player.
    ///
    /// - Parameter randomMode: The random mode to use.
    public func setRandom(_ randomMode: RandomMode) async throws {
        try await mpdConnector.playback.setRandom(randomMode == .on ? .on : .off)
    }
    
    /// Toggle the random mode (off -> on -> off)
    public func toggleRandom(from playerStatus: PlayerStatus) async throws {
        let newState: OnOffState = playerStatus.playing.randomMode == .on ? .off : .on
        try await mpdConnector.playback.setRandom(newState)
    }
    
    /// Shuffle the current playqueue
    public func shufflePlayqueue() async throws {
        try await mpdConnector.queue.shuffle()
    }
    
    /// Set the repeat mode of the player.
    ///
    /// - Parameter repeatMode: The repeat mode to use.
    public func setRepeat(_ repeatMode: RepeatMode) async throws {
        let repeatState: OnOffState
        let singleState: OnOffOneShotState
        
        switch repeatMode {
        case .off:
            repeatState = .off
            singleState = .off
        case .all, .album:
            repeatState = .on
            singleState = .off
        case .single:
            repeatState = .on
            singleState = .on
        }
        
        try await mpdConnector.playback.setRepeat(repeatState)
        try await mpdConnector.playback.setSingle(singleState)
    }
    
    /// Toggle the repeat mode (off -> all -> single -> off)
    public func toggleRepeat(from playerStatus: PlayerStatus) async throws {
        let repeatState: OnOffState
        let singleState: OnOffOneShotState
        
        switch playerStatus.playing.repeatMode {
        case .off:
            repeatState = .on
            singleState = .off
        case .all, .album:
            repeatState = .on
            singleState = .on
        case .single:
            repeatState = .off
            singleState = .off
        }
        
        try await mpdConnector.playback.setRepeat(repeatState)
        try await mpdConnector.playback.setSingle(singleState)
    }
    
    /// Set the consume mode of the player.
    public func setConsume(_ consumeMode: ConsumeMode) async throws {
        try await mpdConnector.playback.setConsume(consumeMode == .on ? .on : .off)
    }
    
    /// Toggle the consume mode (off -> on -> off)
    public func toggleConsume(from playerStatus: PlayerStatus) async throws {
        let newState: OnOffOneShotState = playerStatus.playing.consumeMode == .on ? .off : .on
        try await mpdConnector.playback.setConsume(newState)
    }
    
    /// Set the volume of the player.
    ///
    /// - Parameter volume: The volume to set. Must be a value between 0.0 and 1.0
    public func setVolume(_ volume: Float) async throws {
        try await mpdConnector.playback.setVolume(Int32(volume * 100.0))
    }
    
    /// Adjust the volume of the player.
    ///
    /// - Parameter adjustment: Volume delta to apply.
    public func adjustVolume(_ adjustment: Float, from playerStatus: PlayerStatus) async throws {
        let newVolume = adjustment < 0
        ? max(playerStatus.volume + adjustment, 0.0)
        : min(playerStatus.volume + adjustment, 1.0)
        try await mpdConnector.playback.setVolume(Int32(newVolume * 100.0))
    }
    
    /// Seek to a position in the current song
    ///
    /// - Parameter seconds: Absolute seek position in seconds.
    public func setSeek(seconds: UInt32, from playerStatus: PlayerStatus) async throws {
        guard seconds < playerStatus.currentSong.length else { return }
        try await mpdConnector.playback.seekcur(time: Float(seconds))
    }
    
    /// Seek to a relative position in the current song
    ///
    /// - Parameter percentage: Value between 0.0 and 1.0
    public func setSeek(percentage: Float, from playerStatus: PlayerStatus) async throws {
        let seconds = UInt32(percentage * Float(playerStatus.currentSong.length))
        guard seconds < playerStatus.currentSong.length else { return }
        try await mpdConnector.playback.seekcur(time: Float(seconds))
    }
    
    /// Add a batch of songs to the play queue
    ///
    /// - Parameters:
    ///   - songs: array of songs to add
    ///   - addDetails: how to add the song to the playqueue
    public func add(_ songs: [Song], addDetails: AddDetails) async throws {
        var pos = 0
        var executors: [any CommandExecutor] = []
        
        switch addDetails.addMode {
        case .replace:
            executors.append(mpdConnector.queue.clearExecutor())
        case .addNext, .addNextAndPlay:
            pos = addDetails.playerStatus.playqueue.songIndex + 1
        case .addAtEnd:
            pos = addDetails.playerStatus.playqueue.length
        }
        
        let songsToAdd = addDetails.shuffle ? songs.shuffled() : songs
        for song in songsToAdd {
            executors.append(mpdConnector.queue.addidExecutor(song.id, position: pos))
            pos += 1
        }
        
        if addDetails.addMode == .replace {
            executors.append(mpdConnector.playback.playExecutor(Int(addDetails.startWithSong)))
        } else if addDetails.addMode == .addNextAndPlay {
            executors.append(mpdConnector.playback.playExecutor(Int(addDetails.playerStatus.playqueue.songIndex + 1)))
        }
        
        try await mpdConnector.batchCommand(executors)
    }
    
    /// Add a song to the play queue
    ///
    /// - Parameters:
    ///   - song: the song to add
    ///   - addDetails: how to add the song to the playqueue
    /// - Returns: an observable tuple consisting of song and addResponse.
    public func add(_ song: Song, addDetails: AddDetails) async throws {
        try await add([song], addDetails: addDetails)
    }
    
    /// Add a song to a playlist
    ///
    /// - Parameters:
    ///   - song: the song to add
    ///   - playlist: the playlist to add the song to
    /// - Returns: an observable tuple consisting of song and playlist.
    public func addToPlaylist(_ song: Song, playlist: Playlist) async throws {
        try await self.mpdConnector.playlist.playlistadd(name: playlist.id, uri: song.id)
    }
    
    /// Add an album to the play queue
    ///
    /// - Parameters:
    ///   - album: the album to add
    ///   - addDetails: how to add the song to the playqueue
    /// - Returns: an observable tuple consisting of album and addResponse.
    public func add(_ album: Album, addDetails: AddDetails) async throws {
        // First we need to get all the songs on an album, then add them one by one
        let browse = MPDBrowse.init(connectionProperties: connectionProperties, mpdConnector: mpdConnector)
        let songs = try await browse.songsOnAlbum(album)
        try await add(songs, addDetails: addDetails)
    }
    
    /// Add an album to a playlist
    ///
    /// - Parameters:
    ///   - album: the album to add
    ///   - playlist: the playlist to add the song to
    /// - Returns: an observable tuple consisting of album and playlist.
    public func addToPlaylist(_ album: Album, playlist: Playlist) async throws {
        // First we need to get all the songs on an album, then add them one by one
        let browse = MPDBrowse.init(connectionProperties: connectionProperties, mpdConnector: mpdConnector)
        let songs = try await browse.songsOnAlbum(album)
        var executors = [any CommandExecutor]()
        for song in songs {
            executors.append(mpdConnector.playlist.playlistaddExecutor(name: playlist.id, uri: song.id))
        }
        try await mpdConnector.batchCommand(executors)
    }
    
    /// Add an artist to the play queue
    ///
    /// - Parameters:
    ///   - artist: the artist to add
    ///   - addDetails: how to add the song to the playqueue
    /// - Returns: an observable tuple consisting of artist and addResponse.
    public func add(_ artist: Artist, addDetails: AddDetails) async throws {
        // First we need to get all the songs on an album, then add them one by one
        let browse = MPDBrowse.init(connectionProperties: connectionProperties, mpdConnector: mpdConnector)
        let songs = try await browse.songsByArtist(artist)
        try await add(songs, addDetails: addDetails)
    }
    
    /// Add a playlist to the play queue
    ///
    /// - Parameters:
    ///   - playlist: the playlist to add
    ///   - addDetails: how to add the playlist to the playqueue
    /// - Returns: an observable tuple consisting of playlist and addResponse.
    public func add(_ playlist: Playlist, addDetails: AddDetails) async throws {
        let mpdConnector = self.mpdConnector
        var executors = [any CommandExecutor]()
        executors.append(mpdConnector.queue.clearExecutor())
        executors.append(mpdConnector.playlist.loadExecutor(playlist: playlist.id))
        if addDetails.shuffle {
            executors.append(mpdConnector.queue.shuffleExecutor())
        }
        executors.append(mpdConnector.playback.playExecutor(Int(addDetails.startWithSong)))
        
        try await mpdConnector.batchCommand(executors)
    }
    
    /// Add a genre to the play queue
    ///
    /// - Parameters:
    ///   - genre: the genre to add
    ///   - addDetails: how to add the folder to the playqueue
    public func add(_ genre: Genre, addDetails: AddDetails) async throws {
        var executors = [any CommandExecutor]()
        executors.append(mpdConnector.queue.clearExecutor())
        executors.append(mpdConnector.database.findaddExecutor(filter: .tagEquals(tag: .genre, value: genre.id)))
        if addDetails.shuffle {
            executors.append(mpdConnector.queue.shuffleExecutor())
        }
        executors.append(mpdConnector.playback.playExecutor(0))
        try await mpdConnector.batchCommand(executors)
    }
    
    /// Add a folder to the play queue
    ///
    /// - Parameters:
    ///   - folder: the folder to add
    ///   - addDetails: how to add the folder to the playqueue
    /// - Returns: an observable tuple consisting of folder and addResponse.
    public func add(_ folder: Folder, addDetails: AddDetails) async throws {
        // First we need to get all the songs on an album, then add them one by one
        let browse = MPDBrowse.init(connectionProperties: connectionProperties, mpdConnector: mpdConnector)
        let folderContents = try await browse.fetchFolderContents(parentFolder: folder)
        
        let songs = folderContents.compactMap {
            if case let .song(song) = $0 {
                return song
            }
            return nil
        }
        
        try await add(songs, addDetails: addDetails)
    }
    
    /// Add a folder recursively to the play queue
    ///
    /// - Parameters:
    ///   - folder: the folder to add
    ///   - addDetails: how to add the folder to the playqueue
    /// - Returns: an observable tuple consisting of folder and addResponse.
    public func addRecursive(_ folder: Folder, addDetails: AddDetails) async throws {
        var pos = 0
        
        var executors = [any CommandExecutor]()
        switch addDetails.addMode {
        case .replace:
            executors.append(mpdConnector.queue.clearExecutor())
        case .addNext, .addNextAndPlay:
            pos = addDetails.playerStatus.playqueue.songIndex + 1
        case .addAtEnd:
            pos = addDetails.playerStatus.playqueue.length
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
                executors.append(mpdConnector.queue.moveExecutor(range: UInt(addDetails.playerStatus.playqueue.length)...UInt(end), topos: .absolute(UInt(pos))))
            }
            
            if addDetails.addMode == .addNextAndPlay {
                executors.append(mpdConnector.playback.playExecutor(pos))
            }
        }
        try await mpdConnector.batchCommand(executors)
    }
    
    
    /// Move a song in the playqueue to a different position
    ///
    /// - Parameters:
    ///   - from: the position of the song to change
    ///   - to: the position to move the song to
    public func moveSong(from: Int, to: Int) async throws {
        try await mpdConnector.queue.move(frompos: from, topos: .absolute(UInt(to)))
    }
    
    /// Remove song from the playqueue
    ///
    /// - Parameter at: the position of the song to remove
    public func deleteSong(_ at: Int) async throws {
        try await mpdConnector.queue.delete(at)
    }
    
    /// Move a song in a playlist to a different position
    ///
    /// - Parameters:
    ///   - playlist: the playlist in which to make the move
    ///   - from: the position of the song to change
    ///   - to: the position to move the song to
    public func moveSong(playlist: Playlist, from: Int, to: Int) async throws {
        try await mpdConnector.playlist.playlistmove(name: playlist.id, from: UInt(from), to: UInt(to))
    }
    
    /// Remove song from a playlist
    ///
    /// - Parameters:
    ///   - playlist: the playlist from which to remove the song
    ///   - at: the position of the song to remove
    public func deleteSong(playlist: Playlist, at: Int) async throws {
        try await mpdConnector.playlist.playlistdelete(name: playlist.id, songpos: UInt(at))
    }
    
    /// Save the current playqueue as a playlist
    ///
    /// - Parameter name: name for the playlist
    public func savePlaylist(_ name: String) async throws {
        try await mpdConnector.playlist.save(name: name)
    }
    
    /// Clear the active playqueue
    ///
    /// - Parameters:
    ///   - from: optional start index
    ///   - to: optional end index
    ///   - playerStatus: required when deleting a range
    public func clearPlayqueue(from: Int?, to: Int?, playerStatus: PlayerStatus?) async throws {
        if from == nil && to == nil {
            try await mpdConnector.queue.clear()
        } else if let playerStatus {
            let start = UInt(from ?? 0)
            let end = UInt(to ?? playerStatus.playqueue.length)
            try await mpdConnector.queue.delete(range: start...end)
        }
    }
    
    /// Play a station
    ///
    /// - Parameter station: the station that has to be played
    public func playStation(_ station: Station) async throws {
        var executors = [any CommandExecutor]()
        executors.append(mpdConnector.playback.stopExecutor())
        executors.append(mpdConnector.queue.clearExecutor())
        
        if station.url.hasSuffix(".m3u") || station.url.hasSuffix(".pls") || station.url.contains(".pls?") || station.url.contains(".m3u?") {
            executors.append(mpdConnector.playlist.loadExecutor(playlist: station.url))
        } else {
            executors.append(mpdConnector.queue.addExecutor(station.url))
        }
        
        executors.append(mpdConnector.playback.playExecutor())
        try await mpdConnector.batchCommand(executors)
    }
    
    /// Enable or disable an output
    ///
    /// - Parameters:
    ///   - output: the output to set
    ///   - enabled: true to enable the output, false to disable it
    public func setOutput(_ output: Output, enabled: Bool) async throws {
        guard let output_id = Int(output.id) else { return }
        if enabled {
            try await mpdConnector.output.enableoutput(output_id)
        } else {
            try await mpdConnector.output.disableoutput(output_id)
        }
    }
    
    /// Toggle an output on or off
    ///
    /// - Parameter output: the output to toggle
    public func toggleOutput(_ output: Output) async throws {
        guard let output_id = Int(output.id) else { return }
        try await mpdConnector.output.toggleoutput(output_id)
    }
    
    public func playFavourite(_ favourite: FoundItem) async throws {
    }
}
