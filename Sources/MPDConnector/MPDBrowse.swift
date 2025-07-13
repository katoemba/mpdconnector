//
//  MPDBrowse.swift
//  MPDConnector_iOS
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

extension Array where Element:Hashable {
    var orderedSet: Array {
        var unique = Set<Element>()
        return filter { element in
            return unique.insert(element).inserted
        }
    }
}

public class MPDBrowse: BrowseProtocol {
    public var cacheStatus: String?

    public var name = "mpd"
    
    private static var operationQueue: OperationQueue?
    private var identification = ""
    private var connectionProperties: [String: Any]
    private let mpdConnector: SwiftMPD.MPDConnector

    public init(connectionProperties: [String: Any],
                identification: String = "NoID",
                mpdConnector: SwiftMPD.MPDConnector) {
        self.identification = identification
        self.connectionProperties = connectionProperties
        self.mpdConnector = mpdConnector
    }
    
    public func search(_ search: String, limit: Int = 20, filter: [SourceType] = []) async throws -> SearchResult {
        var searchResult = SearchResult()
        let songs = try await mpdConnector.database.search(filter: .tagContains(tag: .title, value: search)).map {
            Song(mpdSong: $0, connectionProperties: connectionProperties)
        }
        searchResult.songs = Array<Song>(songs.prefix(limit))
        
        let albumSongs = try await mpdConnector.database.search(filter: .tagContains(tag: .album, value: search)).map {
            Song(mpdSong: $0, connectionProperties: connectionProperties)
        }
        var albums = Set<Album>()
        for song in albumSongs {
            albums.insert(self.createAlbumFromSong(song))
        }
        searchResult.albums = Array<Album>(albums.prefix(limit))
        
        let artistSongs = try await mpdConnector.database.search(filter: .tagContains(tag: .artist, value: search)).map {
            Song(mpdSong: $0, connectionProperties: connectionProperties)
        }
        var artists = Set<Artist>()
        for song in artistSongs {
            artists.insert(self.createArtistFromSong(song))
        }
        searchResult.artists = Array<Artist>(artists.prefix(limit))
        
        let performerStrings = try await mpdConnector.database.search(filter: .tagContains(tag: .performer, value: search)).compactMap({
            $0.performer
        })
        var performers = Set<Artist>()
        for entry in performerStrings {
            for performer in Artist.splitPerformerString(entry).filter({ $0.lowercased().contains(search.lowercased())}) {
                performers.insert(Artist(id: performer, type: .performer, source: .Local, name: performer))
            }
        }
        searchResult.performers = Array<Artist>(performers.prefix(limit))

        let conductorSongs = try await mpdConnector.database.search(filter: .tagContains(tag: .conductor, value: search)).map {
            Song(mpdSong: $0, connectionProperties: connectionProperties)
        }
        var conductors = Set<Artist>()
        for song in conductorSongs {
            conductors.insert(self.createArtistFromSong(song, type: .conductor))
        }
        searchResult.conductors = Array<Artist>(conductors.prefix(limit))

        let composerSongs = try await mpdConnector.database.search(filter: .tagContains(tag: .composer, value: search)).map {
            Song(mpdSong: $0, connectionProperties: connectionProperties)
        }
        var composers = Set<Artist>()
        for song in composerSongs {
            composers.insert(self.createArtistFromSong(song, type: .composer))
        }
        searchResult.composers = Array<Artist>(composers.prefix(limit))

        return searchResult
    }
    
    /// Return an array of songs for an artist and optional album. This will search through both artist and albumartist.
    ///
    /// - Parameters:
    ///   - connection: an active mpd connection
    ///   - artist: the artist name to search for
    ///   - album: optionally an album title to search for
    /// - Returns: an array of Song objects
    private func songsForArtistAndOrAlbum(artist: Artist, album: String? = nil) async throws -> [Song] {
        var filter: MPDDatabase.Expression
        var alternativeFilter: MPDDatabase.Expression?
        switch artist.type {
        case .artist:
            filter = .tagEquals(tag: .artist, value: artist.name)
            alternativeFilter = .tagEquals(tag: .albumArtist, value: artist.name)
        case .albumArtist:
            filter = .tagEquals(tag: .albumArtist, value: artist.name)
        case .composer:
            filter = .tagEquals(tag: .composer, value: artist.name)
        case .performer:
            filter = .tagContains(tag: .performer, value: artist.name)
        case .conductor:
            filter = .tagEquals(tag: .conductor, value: artist.name)
        }

        var mpdSongs = try await mpdConnector.database.search(filter: filter)
        if let alternativeFilter {
            mpdSongs += try await mpdConnector.database.search(filter: alternativeFilter)
        }
        
        let songs = Array(Set(mpdSongs.filter {
                album == nil || $0.album == album!
            }
            .map {
                Song(mpdSong: $0, connectionProperties: connectionProperties)
            }))
        
        return songs.sorted(by: {
            if $0.album != $1.album {
                return $0.album < $1.album
            }
            if $0.disc != $1.disc {
                return $0.disc < $1.disc
            }
            return $0.track < $1.track
        })
    }
    
    /// Asynchronously get all songs on an album
    ///
    /// - Parameter album: the album to get the songs for
    /// - Parameter artist: An optional Artist object, allowing to filter the songs by a specific artist
    /// - Returns: an observable array of Song objects
    public func songsOnAlbum(_ album: Album) async throws -> [Song] {
        try await self.songsForArtistAndOrAlbum(artist: Artist(id: album.artist, type: .artist, source: .Local, name: album.artist),
                                      album: album.title)
    }

    public func songsByArtist(_ artist: Artist) async throws -> [Song] {
        try await self.songsForArtistAndOrAlbum(artist: artist)
    }
    
    public func randomSongs(count: Int) async throws -> [Song] {
        let uris = try await self.mpdConnector.database.listall(path: "/")
        var songs = [Song]()
        
        while uris.count > 0, songs.count < 100 {
            let item = uris.randomElement()
            
            if case let .file(path) = item {
                var song = Song()
                song.id = path
                songs.append(song)
            }
        }
        
        return songs
    }
    
    private func createArtistFromSong(_ song: Song, type: ArtistType = .artist) -> Artist {
        let sortName = song.sortArtist != "" ? song.sortArtist : song.sortAlbumArtist
        var artist: Artist
        switch type {
        case .albumArtist, .artist:
            artist = Artist(id: song.artist, type: .artist, source: song.source, name: song.artist, sortName: sortName)
        case .conductor:
            artist = Artist(id: song.conductor, type: type, source: song.source, name: song.conductor)
        case .performer:
            artist = Artist(id: song.performer, type: type, source: song.source, name: song.performer)
        case .composer:
            artist = Artist(id: song.composer, type: type, source: song.source, name: song.composer)
        }
        if case let .filenameOptionsURI(baseUri, path, possibleFilenames) = song.coverURI {
            let baseUriComponents = baseUri.components(separatedBy: "/")
            var newBaseUri = ""
            for idx in 0..<baseUriComponents.count - 2 {
                newBaseUri.append(baseUriComponents[idx] + "/")
            }

            let pathComponents = path.components(separatedBy: "/")
            if pathComponents.count > 2 {
                var newPath = ""
                for idx in 0..<pathComponents.count - 2 {
                    newPath.append(pathComponents[idx] + "/")
                }

                artist.coverURI = CoverURI.filenameOptionsURI(newBaseUri, newPath, possibleFilenames)
            }
        }
        
        return artist
    }
    
    private func createAlbumFromSong(_ song: Song) -> Album {
        let artist = song.albumartist != "" ? song.albumartist : song.artist
        let sortArtist = song.sortAlbumArtist != "" ? song.sortAlbumArtist : song.sortArtist
        var album = Album(id: "\(artist):\(song.album)", source: song.source, location: "", title: song.album, artist: artist, year: song.year, genre: song.genre, length: 0, sortArtist: sortArtist)
        album.coverURI = song.coverURI
        album.lastModified = song.lastModified
        album.quality = song.quality
    
        return album
    }
    
    private func albumsFromSongs(_ songs: [Song], sort: SortType) -> [Album] {
        var albums = [Album]()
        for song in songs {
            let album = createAlbumFromSong(song)
            if albums.contains(album) == false {
                albums.append(album)
            }
        }
        
        return albums.sorted(sort: sort)
    }
    
    public func albumsByArtist(_ artist: Artist, sort: SortType) async throws -> [Album] {
        albumsFromSongs(try await songsByArtist(artist), sort: sort)
    }

    public func recentAlbums() async throws -> [Album] {
        try await recentAlbums(numberOfAlbums: 20)
    }

    public func recentAlbums(numberOfAlbums: Int) async throws -> [Album] {
        let connectionProperties = self.connectionProperties
        let mpdConnector = self.mpdConnector

        let songs: [Song] = try await mpdConnector.database.search(filter: .modifiedSince(value: Date(timeIntervalSinceNow: -3600 * 24 * 100))).compactMap {
            guard let title = $0.title, title != "" else { return nil }
            return Song(mpdSong: $0, connectionProperties: connectionProperties)
        }
        
        return self.albumsFromSongs(songs, sort: .title).sorted {
            $0.lastModified > $1.lastModified
        }
    }
        
    public func albums() async throws -> [Album] {
        try await albums(genre: nil)
    }

    public func albums(genre: Genre?) async throws -> [Album] {
        let expression: MPDDatabase.Expression? = (genre != nil) ? .tagEquals(tag: .genre, value: genre!.id) : nil
        let artists = try await self.mpdConnector.database.list(type: .album, filter: expression, groupBy: [.albumArtist, .albumArtistSort, .date])
        var albums = Set<Album>()
        
        for group in artists {
            guard case let .group(artist) = group, let artistValue = artist.value else { continue }
            for group in artist.children {
                guard case let .group(sortArtist) = group, let sortArtistValue = sortArtist.value else { continue }
                for group in sortArtist.children {
                    guard case let .group(year) = group, let yearValue = year.value else { continue }
                    for value in year.children {
                        guard case let .value(album) = value, album != "" && artistValue != "" else { continue }
                        albums.insert(Album(id: "\(artistValue):\(album)", source: .Local, location: "", title: album, artist: artistValue, year: Int(String(yearValue.prefix(4))) ?? 0, genre: [], length: 0, sortArtist: sortArtistValue))
                    }
                }
            }
        }
        
        return Array<Album>(albums)
    }


    // This is the old-fashioned way of getting data, using a double group by.
    private func fetchAlbums_below_20_22(genre: Genre? = nil, sort: SortType) async throws -> [Album] {
        let filter: MPDDatabase.Expression? = (genre == nil) ? nil : MPDDatabase.Expression.tagEquals(tag: .genre, value: genre!.id)
        let keyValuePairs: [KeyValuePair] = try await self.mpdConnector.database.list(type: .album, filter: filter, groupBy: [.albumArtist, .date], raw: true).compactMap {
            switch $0 {
            case let .raw(keyValuePair):
                return keyValuePair
            default:
                return nil
            }
        }
        var albums = Set<Album>()
     
        var idx = 0
        while idx < keyValuePairs.count {
            while idx < keyValuePairs.count, keyValuePairs[idx].key != "album" {
                idx += 1
            }
            guard idx < keyValuePairs.count else { break }
            let title = keyValuePairs[idx].value
            
            idx += 1
            if title != "" {
                var albumArtist = "Unknown"
                if idx < keyValuePairs.count, keyValuePairs[idx].key == "albumartist" {
                    albumArtist = keyValuePairs[idx].value
                    idx += 1
                }
                var year = 0
                if idx < keyValuePairs.count, keyValuePairs[idx].key == "date" {
                    let yearString = keyValuePairs[idx].value
                    year = Int(String(yearString.prefix(4))) ?? 0
                    idx += 1
                }
                
                let albumID = "\(albumArtist):\(title)"
                albums.insert(Album(id: albumID, source: .Local, location: "", title: title, artist: albumArtist, year: year, genre: [], length: 0))
            }
        }

        return Array<Album>(albums).sorted(sort: sort)
    }
    
    // The grouping was changed in 0.20.22 and above. It works more consistently it seems,
    // but because of mpd bug https://github.com/MusicPlayerDaemon/MPD/issues/408 multiple group-by's are not possible
    private func fetchAlbums_20_22_and_above(genre: Genre?, sort: SortType) async throws -> [Album] {
        let expression: MPDDatabase.Expression? = (genre != nil) ? .tagEquals(tag: .genre, value: genre!.id) : nil
        let artists = try await self.mpdConnector.database.list(type: .album, filter: expression, groupBy: [.albumArtist])
        var albums = Set<Album>()
        
        for group in artists {
            guard case let .group(artist) = group, let artistValue = artist.value else { continue }
            for value in artist.children {
                guard case let .value(album) = value, album != "" && artistValue != "" else { continue }
                albums.insert(Album(id: "\(artistValue):\(album)", source: .Local, location: "", title: album, artist: artistValue, year: 0, genre: [], length: 0))
            }
        }

        return Array<Album>(albums).sorted(sort: sort)
    }
    
    // Multiple grouping returns in 0.21.11 and now works consistently.
    private func fetchAlbums_21_11_and_above(genre: Genre?, sort: SortType) async throws -> [Album] {
        let expression: MPDDatabase.Expression? = (genre != nil) ? .tagEquals(tag: .genre, value: genre!.id) : nil
        let artists = try await self.mpdConnector.database.list(type: .album, filter: expression, groupBy: [.albumArtist, .albumArtistSort, .date])
        var albums = Set<Album>()
        
        for group in artists {
            guard case let .group(artist) = group, let artistValue = artist.value else { continue }
            for group in artist.children {
                guard case let .group(sortArtist) = group, let sortArtistValue = sortArtist.value else { continue }
                for group in sortArtist.children {
                    guard case let .group(year) = group, let yearValue = year.value else { continue }
                    for value in year.children {
                        guard case let .value(album) = value, album != "" && artistValue != "" else { continue }
                        albums.insert(Album(id: "\(artistValue):\(album)", source: .Local, location: "", title: album, artist: artistValue, year: Int(String(yearValue.prefix(4))) ?? 0, genre: [], length: 0, sortArtist: sortArtistValue))
                    }
                }
            }
        }
        
        return Array<Album>(albums).sorted(sort: sort)
    }
    
    public func completeAlbums(_ albums: [Album]) async throws -> [Album] {
        if let album = albums.first {
            switch album.coverURI {
            case let .fullPathURI(path):
                if path != "" {
                    return albums
                }
            case let .filenameOptionsURI(_, path, _):
                if path != "" {
                    return albums
                }
            }
        }
        
        var originalAlbums = albums
        var results = [Album]()
        
        var commands = [any CommandExecutor]()
        for album in albums {
            let expression = MPDDatabase.Expression.and(.tagEquals(tag: .album, value: album.title), .tagEquals(tag: .albumArtist, value: album.artist))
            commands.append(self.mpdConnector.database.findExecutor(filter: expression, range: 0...1))
        }
        try await self.mpdConnector.batchCommand(commands)
        
        for command in commands {
            guard let songs = try command.processResults() as? [MPDSong], songs.count > 0 else {
                results.append(originalAlbums.removeFirst())
                continue
            }
            
            let song = Song(mpdSong: songs[0], connectionProperties: self.connectionProperties)
            results.append(self.createAlbumFromSong(song))
            originalAlbums.removeFirst()
        }
        return results
    }

    public func completeArtists(_ artists: [Artist]) async throws -> [Artist] {
        var originalArtist = artists
        var results = [Artist]()
        
        var commands = [any CommandExecutor]()
        for artist in artists {
            let expression = MPDDatabase.Expression.tagEquals(tag: .albumArtist, value: artist.name)
            commands.append(self.mpdConnector.database.findExecutor(filter: expression, range: 0...1))
        }
        try await self.mpdConnector.batchCommand(commands)
        
        for command in commands {
            guard let songs = try command.processResults() as? [MPDSong], songs.count > 0 else {
                results.append(originalArtist.removeFirst())
                continue
            }
            
            let song = Song(mpdSong: songs[0], connectionProperties: self.connectionProperties)
            results.append(self.createArtistFromSong(song))
            originalArtist.removeFirst()
        }
        return results
    }
       
    public func artists(type: ArtistType) async throws -> [Artist] {
        let filter: MPDDatabase.Expression? = nil
        var results: [MPDDatabase.ListExecutor.GroupChild]
        var artists = Set<Artist>()
        
        switch type {
        case .artist:
            results = try await mpdConnector.database.list(type: .artist, filter: filter, groupBy: [.artistSort])
        case .albumArtist:
            results = try await mpdConnector.database.list(type: .albumArtist, filter: filter, groupBy: [.albumArtistSort])
        case .performer:
            results = try await mpdConnector.database.list(type: .performer, filter: filter, raw: true)
        case .composer:
            results = try await mpdConnector.database.list(type: .composer, filter: filter, raw: true)
        case .conductor:
            results = try await mpdConnector.database.list(type: .conductor, filter: filter, raw: true)
        }
        
        var artistStrings: [String] = []
        
        for result in results {
            switch result {
            case .value(let stringValue):
                artistStrings.append(stringValue)
                
            case .raw(let pair):
                artistStrings.append(pair.value)
                
            case .group(let group):
                for child in group.children {
                    switch child {
                    case let .value(value):
                        artistStrings.append(value)
                    default:
                        continue
                    }
                }
            }
        }
        
        if type == .performer {
            for artistString in artistStrings {
                for performer in Artist.splitPerformerString(artistString) {
                    artists.insert(Artist(id: performer, type: type, source: .Local, name: performer))
                }
            }
        }
        else {
            for artistString in artistStrings {
                artists.insert(Artist(id: artistString, type: type, source: .Local, name: artistString))
            }
        }
        
        return Array<Artist>.init(artists).sorted(by: { (lhs, rhs) -> Bool in
            let sortOrder = lhs.sortName.caseInsensitiveCompare(rhs.sortName)
            if sortOrder == .orderedSame {
                return lhs.name.caseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            else {
                return sortOrder == .orderedAscending
            }
        })
    }

    public func artists(genre: Genre) async -> [Artist] {
        return []
    }

    public func existingArtists(artists: [Artist]) async throws -> [Artist] {
        let mpdConnector = mpdConnector
        
        var executors = [MPDDatabase.ListExecutor]()
        
        for artist in artists {
            executors.append(mpdConnector.database.listExecutor(type: .artist, filter: .tagEquals(tag: .artist, value: artist.name)))
        }
        
        try await mpdConnector.batchCommand(executors)
        
        var results = [Artist]()
        for idx in 0..<artists.count {
            if let found = try? executors[idx].processResults(), found.count > 0 {
                results.append(artists[idx])
            }
        }
        
        return results
    }

    public func similarArtists(artist: Artist) async throws -> [Artist] {
        return []
    }
    
    /// Load playlists from mpd.
    ///
    /// - Returns: an observable array of playlists, order by name
    func fetchPlaylists() async throws -> [Playlist] {
        let playlists = try await self.mpdConnector.playlist.listplaylists()
        
        return playlists.map {
            Playlist(id: $0.name, source: .Local, name: $0.name, lastModified: $0.lastmodified)
        }
        .sorted(by: { (lhs, rhs) -> Bool in
            return lhs.name.caseInsensitiveCompare(rhs.name) == .orderedAscending
        })
    }
    
    /// Asynchronously get all songs in a playlist
    ///
    /// - Parameter playlist: the playlst to get the songs for
    /// - Returns: an observable array of Song objects
    public func songsInPlaylist(_ playlist: Playlist) async throws -> [Song] {
        let songs = try await mpdConnector.playlist.listplaylistinfo(name: playlist.name)
        return songs
            .map {
                Song(mpdSong: $0, connectionProperties: connectionProperties, forcePlayqueueId: true)
            }
    }
    
    /// Delete a playlist
    ///
    /// - Parameter playlist: the playlist to delete
    func deletePlaylist(_ playlist: Playlist) async throws {
        try await mpdConnector.playlist.rm(name: playlist.id)
    }
    
    /// Rename a playlist
    ///
    /// - Parameters:
    ///   - playlist: the playlist to rename
    ///   - newName: the new name to give to the playlist
    func renamePlaylist(_ playlist: Playlist, newName: String) async throws {
        try await mpdConnector.playlist.rename(name: playlist.id, newName: newName)
    }
    
    /// Fetch an array of genres
    ///
    /// - Returns: an observable String array of genre names
    public func genres() async throws -> [Genre] {
        let genres = try await mpdConnector.database.list(type: .genre, raw: true)
        return genres.compactMap {
            switch $0 {
            case let .raw(genre):
                return Genre(id: genre.value, source: .Local, name: genre.value)
            default:
                return nil
            }
        }
    }
    
    /// Fetch an array of genres
    ///
    /// - Returns: an observable String array of genre names
    func fetchFolderContents(parentFolder: Folder? = nil) async throws -> [FolderContent] {
        try await mpdConnector.database.lsinfo(uri: parentFolder?.path)
            .compactMap {
                switch $0 {
                case let .song(song):
                    return FolderContent.song(Song(mpdSong: song, connectionProperties: connectionProperties))
                case let .playlist(playlist, lastModified):
                    return FolderContent.playlist(Playlist(id: playlist, source: .Local, name: playlist, lastModified: lastModified ?? Date()))
                case let .directory(directory, _):
                    let components = directory.split(separator: "/")
                    if let folderName = components.last {
                        return FolderContent.folder(Folder(id: directory, source: .Local, path: directory, name: String(folderName)))
                    }
                    return nil
                }
            }
    }
    
    /// Get an Artist object for the artist performing a particular song
    ///
    /// - Parameter song: the song for which to get the artist
    /// - Returns: an observable Artist
    public func artistFromSong(_ song: Song) -> Artist {
        createArtistFromSong(song)
    }
    
    /// Get an Album object for the album on which a particular song appears
    ///
    /// - Parameter song: the song for which to get the album
    /// - Returns: an observable Album
    public func albumFromSong(_ song: Song) -> Album {
        createAlbumFromSong(song)
    }

    /// Return the tagtypes that are supported by a player
    ///
    /// - Returns: an array of tagtypes (strings)
    public func availableTagTypes() async throws -> [String] {
        try await mpdConnector.status.tagtypes()
    }
    
    /// Return the commands that are supported by a player
    ///
    /// - Returns: an array of commands (strings)
    public func availableCommands() async throws -> [String] {
        try await mpdConnector.status.commands()
    }
    
    /// Preprocess a CoverURI. This allows additional processing of base URI data.
    ///
    /// - Parameter coverURI: the CoverURI to pre-process
    /// - Returns: the processed cover URI
    public func preprocessCoverURI(_ coverURI: CoverURI) async throws -> CoverURI {
        if case let .filenameOptionsURI(baseURI, path, filenames) = coverURI {
            if baseURI.contains("coverart.php") {
                return CoverURI.filenameOptionsURI(baseURI, path, [""])
            }
                
            var coverFiles = [String]()
            let folderContents = try await mpdConnector.database.listfiles(uri: path)
            for item in folderContents {
                switch item {
                case let .file(file: file, size: _, lastmodified: _):
                    if let fileExtension = file.split(separator: ".").last, ["jpg", "png"].contains(fileExtension), file.starts(with: "._") == false {
                        coverFiles.append(file)
                    }
                default:
                    continue
                }
            }
            
            for bestOption in filenames {
                if coverFiles.contains(bestOption) {
                    return CoverURI.filenameOptionsURI(baseURI, path, [bestOption])
                }
            }
            if coverFiles.count > 0 {
                return CoverURI.filenameOptionsURI(baseURI, path, [coverFiles[0]])
            }
        }

        return coverURI
    }
    
    /// Complete data for a song
    /// - Parameter song: a song for which data must be completed
    /// - Returns: an observable song
    public func complete(_ song: Song) async throws -> Song {
        song
    }

    /// Complete data for an album
    /// - Parameter album: an album for which data must be completed
    /// - Returns: an observable album
    public func complete(_ album: Album) async throws -> Album {
        album
    }

    /// Complete data for an artist
    /// - Parameter artist: an artist for which data must be completed
    /// - Returns: an observable artist
    public func complete(_ artist: Artist) async throws -> Artist {
        artist
    }
    
    func updateDB() async throws -> Int {
        try await mpdConnector.database.update(path: nil)
    }

    func rescanLibrary() async throws -> Int {
        try await mpdConnector.database.rescan(path: nil)
    }

    func databaseStatus() async throws -> String {
        if let _ = try await mpdConnector.status.getStatus().updating_db {
            return "Updating..."
        }
        else {
            let lastUpdated = Date(timeIntervalSince1970: try await TimeInterval(mpdConnector.status.stats().db_update))
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short

            return "Last updated: \(dateFormatter.string(from: lastUpdated))"

        }
    }
    
    /// Search for the existance a certain item
    /// - Parameter searchItem: what to search for
    /// - Returns: an observable array of results
    public func search(searchItem: SearchItem) async throws -> [FoundItem] {
        var foundItems = Array<FoundItem>()
        switch searchItem {
        case let .artist(artist):
            foundItems = try await mpdConnector.database.search(filter: .tagEquals(tag: .artist, value: artist), range: 0...100)
                .map {
                    FoundItem.artist(self.createArtistFromSong(Song(mpdSong: $0, connectionProperties: connectionProperties)))
                }
        case let .artistAlbum(artist, sort):
            let sortToUse: MPDDatabase.TagSort? = sort == .year ? .ascending(.date) : ((sort == .yearReverse) ? .descending(.date) : nil)
            foundItems = try await mpdConnector.database.search(filter: .tagEquals(tag: .albumArtist, value: artist), sort: sortToUse, range: 0...100)
                .map {
                    FoundItem.album(self.createAlbumFromSong(Song(mpdSong: $0, connectionProperties: connectionProperties)))
                }
        case let .album(album, artist):
            var filter: MPDDatabase.Expression
            if let artist {
                filter = .and(.tagEquals(tag: .album, value: album), .tagEquals(tag: .albumArtist, value: artist))
            }
            else {
                filter = .tagEquals(tag: .album, value: album)
            }
            foundItems = try await mpdConnector.database.search(filter: filter, range: 0...100)
                .map {
                    FoundItem.album(self.createAlbumFromSong(Song(mpdSong: $0, connectionProperties: connectionProperties)))
                }
        case let .genre(genre):
            foundItems = try await mpdConnector.database.search(filter: .tagEquals(tag: .genre, value: genre), range: 0...100)
                .compactMap {
                    guard let genre = $0.genre else { return nil }
                    
                    return FoundItem.genre(Genre(id: genre, source: .Local, name: genre))
                }
        case let .song(title, artist):
            var filter: MPDDatabase.Expression
            if let artist {
                filter = .and(.tagEquals(tag: .title, value: title), .tagEquals(tag: .albumArtist, value: artist))
            }
            else {
                filter = .tagEquals(tag: .title, value: title)
            }
            foundItems = try await mpdConnector.database.search(filter: filter, range: 0...100)
                .map {
                    FoundItem.album(self.createAlbumFromSong(Song(mpdSong: $0, connectionProperties: connectionProperties)))
                }
        default:
            break
        }
        
        return Array(Set(foundItems))
    }
    
    /// Select a number of random songs from the collection
    /// - Parameter count: the number of songs to return
    /// - Returns: an array of songs
    public func randomSongs(_ count: Int) async throws -> [Song] {
        try await randomSongs(count: count)
    }
    
    /// Select a random album from the collection
    /// - Parameter count: the number of albums to return
    /// - Returns: an array of albums
    public func randomAlbums(_ count: Int) async throws -> [Album] {
        try await Array(albums(genre: nil).shuffled().prefix(count))
    }
    
    public func coverData(_ album: Album) async throws -> Data {
        let coverURI = try await preprocessCoverURI(album.coverURI)
        do {
            let data = try await self.mpdConnector.database.getAlbumart(path: coverURI.path)
            if data == Data() {
                return try await self.mpdConnector.database.getReadpicture(path: coverURI.path)
            }
            return data
        }
        catch {
            return try await self.mpdConnector.database.getReadpicture(path: coverURI.path)
        }
    }
    
    public func coverData(_ song: Song) async throws -> Data {
        do {
            let data = try await self.mpdConnector.database.getAlbumart(path: song.coverURI.path)
            if data == Data() {
                return try await self.mpdConnector.database.getReadpicture(path: song.coverURI.path)
            }
            return data
        }
        catch {
            return try await self.mpdConnector.database.getReadpicture(path: song.coverURI.path)
        }
    }
}
