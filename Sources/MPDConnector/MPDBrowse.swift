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
import RxSwift
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
    public var name = "mpd"
    
    private static var operationQueue: OperationQueue?
    private var identification = ""
    private var connectionProperties: [String: Any]
    private let mpdConnector: SwiftMPD.MPDConnector

    private var scheduler: SchedulerType
    
    public init(connectionProperties: [String: Any],
                identification: String = "NoID",
                scheduler: SchedulerType? = nil,
                mpdConnector: SwiftMPD.MPDConnector) {
        self.identification = identification
        self.connectionProperties = connectionProperties
        self.mpdConnector = mpdConnector

        self.scheduler = scheduler ?? ConcurrentDispatchQueueScheduler(qos: .background)
        HelpMePlease.allocUp(name: "MPDBrowse")
    }
    
    /// Cleanup connection object
    deinit {
        HelpMePlease.allocDown(name: "MPDBrowse")
    }

    public func search(_ search: String, limit: Int = 20, filter: [SourceType] = []) -> Observable<SearchResult> {
        let mpdConnector = self.mpdConnector
        let connectionProperties = self.connectionProperties
        
        return Observable<SearchResult>.fromAsync {
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
            
            return searchResult
        }
        .catchAndReturn(SearchResult())
        .observe(on: MainScheduler.instance)
    }
    
    /// Return an array of songs for an artist and optional album. This will search through both artist and albumartist.
    ///
    /// - Parameters:
    ///   - connection: an active mpd connection
    ///   - artist: the artist name to search for
    ///   - album: optionally an album title to search for
    /// - Returns: an array of Song objects
    private func songsForArtistAndOrAlbum(artist: Artist, album: String? = nil) async throws -> [Song] {
        var tag: MPDDatabase.Tag
        var alternativeTag: MPDDatabase.Tag?
        switch artist.type {
        case .artist:
            tag = .artist
            alternativeTag = .albumArtist
        case .albumArtist:
            tag = .albumArtist
        case .composer:
            tag = .composer
        case .performer:
            tag = .performer
        }

        var mpdSongs = try await mpdConnector.database.search(filter: .tagEquals(tag: tag, value: artist.name))
        if let alternativeTag {
            mpdSongs += try await mpdConnector.database.search(filter: .tagEquals(tag: alternativeTag, value: artist.name))
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
    public func songsOnAlbum(_ album: Album) -> Observable<[Song]> {
        Observable<[Song]>.fromAsync {
            try await self.songsForArtistAndOrAlbum(artist: Artist(id: album.artist, type: .artist, source: .Local, name: album.artist),
                                          album: album.title)
        }
        .catchAndReturn([])
        .observe(on: MainScheduler.instance)
    }

    /// Asynchronously get all songs for an artist
    ///
    /// - Parameters:
    ///   - artist: the artist to get the songs for
    /// - Returns: an observable array of Song objects
    public func songsByArtist(_ artist: Artist) -> Observable<[Song]> {
        Observable<[Song]>.fromAsync {
            try await self.songsForArtistAndOrAlbum(artist: artist)
        }
        .catchAndReturn([])
        .observe(on: MainScheduler.instance)
    }
    
    public func randomSongs(count: Int) -> Observable<[Song]> {
        Observable<[Song]>.fromAsync {
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
        .catchAndReturn([])
        .observe(on: MainScheduler.instance)
    }
    
    private func createArtistFromSong(_ song: Song) -> Artist {
        let sortName = song.sortArtist != "" ? song.sortArtist : song.sortAlbumArtist
        var artist = Artist(id: song.artist, source: song.source, name: song.artist, sortName: sortName)
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
    
    /// - Parameters:
    ///   - artist: An Artist object.
    ///   - sort: How to sort the albums.
    /// - Returns: An observable array of fully populated Album objects.
    public func albumsByArtist(_ artist: Artist, sort: SortType) -> Observable<[Album]> {
        return songsByArtist(artist)
            .flatMap({ [weak self] (songs) -> Observable<[Album]> in
                guard let weakself = self else { return Observable.just([]) }
                
                return Observable.just(weakself.albumsFromSongs(songs, sort: sort))
            })
            .catchAndReturn([])
            .observe(on: MainScheduler.instance)
    }
    
    func fetchRecentAlbums(numberOfAlbums: Int) -> Observable<[Album]> {
        let connectionProperties = self.connectionProperties
        let mpdConnector = self.mpdConnector

        return Observable<[Album]>.fromAsync {
            do {
                let songs: [Song] = try await mpdConnector.database.search(filter: .modifiedSince(value: Date(timeIntervalSinceNow: -3600 * 24 * 100))).compactMap {
                    guard let title = $0.title, title != "" else { return nil }
                    return Song(mpdSong: $0, connectionProperties: connectionProperties)
                }
                
                return self.albumsFromSongs(songs, sort: .title).sorted {
                    $0.lastModified > $1.lastModified
                }
            }
            catch {
                throw error
            }
        }
        .catchAndReturn([])
        .observe(on: MainScheduler.instance)
    }
        
    public func recentAlbums() async -> [Album] {
        guard let albums = try? await fetchRecentAlbums(numberOfAlbums: 20).first().value else { return [] }
        
        return albums.count <= 10 ? albums : Array<Album>(albums[0..<10])
    }

    func fetchAlbums(genre: Genre?, sort: SortType) -> Observable<[Album]> {
        let version = connectionProperties[MPDConnectionProperties.version.rawValue] as! String
        if MPDHelper.compareVersion(leftVersion: version, rightVersion: "0.21.10") == .orderedDescending {
            return fetchAlbums_21_11_and_above(genre: genre, sort: sort)
        }
        else if MPDHelper.compareVersion(leftVersion: version, rightVersion: "0.20.22") == .orderedAscending {
            return fetchAlbums_below_20_22(genre: genre, sort: sort)
        }
        else {
            return fetchAlbums_20_22_and_above(genre: genre, sort: sort)
        }
    }

    // This is the old-fashioned way of getting data, using a double group by.
    func fetchAlbums_below_20_22(genre: Genre? = nil, sort: SortType) -> Observable<[Album]> {
        Observable<[Album]>.fromAsync {
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
        .catchAndReturn([])
        .observe(on: MainScheduler.instance)
    }
    
    // The grouping was changed in 0.20.22 and above. It works more consistently it seems,
    // but because of mpd bug https://github.com/MusicPlayerDaemon/MPD/issues/408 multiple group-by's are not possible
    func fetchAlbums_20_22_and_above(genre: Genre?, sort: SortType) -> Observable<[Album]> {
        Observable<[Album]>.fromAsync {
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
        .catchAndReturn([])
        .observe(on: MainScheduler.instance)
    }
    
    // Multiple grouping returns in 0.21.11 and now works consistently.
    func fetchAlbums_21_11_and_above(genre: Genre?, sort: SortType) -> Observable<[Album]> {
        Observable<[Album]>.fromAsync {
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
        .catchAndReturn([])
        .observe(on: MainScheduler.instance)
    }

    public func completeAlbums(_ albums: [Album]) -> Observable<[Album]> {
        Observable<[Album]>.fromAsync {
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
                commands.append(self.mpdConnector.database.findExecutor(filter: expression, range: 0...0))
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
        .catchAndReturn([])
        .observe(on: MainScheduler.instance)
    }

    public func completeArtists(_ artists: [Artist]) -> Observable<[Artist]> {
        Observable<[Artist]>.fromAsync {
            var originalArtist = artists
            var results = [Artist]()
            
            var commands = [any CommandExecutor]()
            for artist in artists {
                let expression = MPDDatabase.Expression.tagEquals(tag: .albumArtist, value: artist.name)
                commands.append(self.mpdConnector.database.findExecutor(filter: expression, range: 0...0))
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
        .catchAndReturn([])
        .observe(on: MainScheduler.instance)
    }
    
    /// Return a view model for a sectioned list of albums.
    ///
    /// - Returns: an AlbumSectionBrowseViewModel instance
    public func albumSectionBrowseViewModel() -> AlbumSectionBrowseViewModel {
        return MPDAlbumSectionBrowseViewModel(browse: self)
    }
    
    /// Return a view model for a list of albums, which can return albums in batches.
    ///
    /// - Returns: an AlbumBrowseViewModel instance
    public func albumBrowseViewModel() -> AlbumBrowseViewModel {
        return MPDAlbumBrowseViewModel(browse: self)
    }
    
    /// Return a view model for a list of albums filtered by artist, which can return albums in batches.
    ///
    /// - Parameter artist: artist to filter on
    /// - Returns: an AlbumBrowseViewModel instance
    public func albumBrowseViewModel(_ artist: Artist) -> AlbumBrowseViewModel {
        return MPDAlbumBrowseViewModel(browse: self, filters: [.artist(artist)])
    }
    
    /// Return a view model for a list of albums related to the current album.
    ///
    /// - Parameter album: related album to filter on
    /// - Returns: an AlbumBrowseViewModel instance
    public func albumBrowseViewModel(_ album: Album) -> AlbumBrowseViewModel {
        return MPDAlbumBrowseViewModel(browse: self, filters: [.related(album)])
    }
    
    /// Return a view model for a list of albums filtered by artist, which can return albums in batches.
    ///
    /// - Parameter genre: genre to filter on
    /// - Returns: an AlbumBrowseViewModel instance
    public func albumBrowseViewModel(_ genre: Genre) -> AlbumBrowseViewModel {
        return MPDAlbumBrowseViewModel(browse: self, filters: [.genre(genre)])
    }
    
    /// Return a view model for a preloaded list of albums.
    ///
    /// - Parameter albums: list of albums to show
    /// - Returns: an AlbumBrowseViewModel instance
    public func albumBrowseViewModel(_ albums: [Album]) -> AlbumBrowseViewModel {
        return MPDAlbumBrowseViewModel(browse:self, albums: albums)
    }

    public func fetchArtists(genre: Genre?, type: ArtistType) -> Observable<[Artist]> {
        let mpdConnector = self.mpdConnector
        
        return Observable<[Artist]>.fromAsync {
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
            }
            
            for result in results {
                switch result {
                case let .raw(pair):
                    artists.insert(Artist(id: pair.value, type: type, source: .Local, name: pair.value))
                case let .group(group):
                    for child in group.children {
                        switch child {
                        case let .value(value):
                            artists.insert(Artist(id: value, type: type, source: .Local, name: value, sortName: group.value ?? ""))
                        default:
                            continue
                        }
                    }
                default:
                    continue
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
        .catchAndReturn([])
        .observe(on: MainScheduler.instance)
    }

    public func fetchExistingArtists(artists: [Artist]) -> Observable<[Artist]> {
        let mpdConnector = mpdConnector
        
        return Observable<[Artist]>.fromAsync {
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
        .catchAndReturn([])
        .observe(on: MainScheduler.instance)
    }

    /// Return a view model for a list of artists, which can return artists in batches.
    ///
    /// - Returns: an ArtistBrowseViewModel instance
    public func artistBrowseViewModel(type: ArtistType) -> ArtistBrowseViewModel {
        return MPDArtistBrowseViewModel(browse: self, filters: [.type(type)])
    }
    
    /// Return a view model for a list of artists filtered by genre, which can return artist in batches.
    ///
    /// - Parameter genre: genre to filter on
    /// - Returns: an ArtistBrowseViewModel instance
    public func artistBrowseViewModel(_ genre: Genre, type: ArtistType) -> ArtistBrowseViewModel {
        return MPDArtistBrowseViewModel(browse: self, filters: [.genre(genre), .type(type)])
    }
    
    /// Return a view model for a preloaded list of artists.
    ///
    /// - Parameter artists: list of artists to show
    /// - Returns: an ArtistBrowseViewModel instance
    public func artistBrowseViewModel(_ artists: [Artist]) -> ArtistBrowseViewModel {
        return MPDArtistBrowseViewModel(browse: self, artists: artists)
    }

    /// Return a view model for a list of playlists, which can return playlists in batches.
    ///
    /// - Returns: an PlaylistBrowseViewModel instance
    public func playlistBrowseViewModel() -> PlaylistBrowseViewModel {
        return MPDPlaylistBrowseViewModel(browse: self)
    }
    
    /// Return a view model for a preloaded list of playlists.
    ///
    /// - Parameter playlists: list of playlists to show
    /// - Returns: an PlaylistBrowseViewModel instance
    public func playlistBrowseViewModel(_ playlists: [Playlist]) -> PlaylistBrowseViewModel {
        return MPDPlaylistBrowseViewModel(browse: self, playlists: playlists)
    }

    /// Load playlists from mpd.
    ///
    /// - Returns: an observable array of playlists, order by name
    func fetchPlaylists() -> Observable<[Playlist]> {
        Observable<[Playlist]>.fromAsync {
            let playlists = try await self.mpdConnector.playlist.listplaylists()
            
            return playlists.map {
                Playlist(id: $0.name, source: .Local, name: $0.name, lastModified: $0.lastmodified)
            }
            .sorted(by: { (lhs, rhs) -> Bool in
                return lhs.name.caseInsensitiveCompare(rhs.name) == .orderedAscending
            })
        }
        .catchAndReturn([])
        .observe(on: MainScheduler.instance)
    }
    
    /// Return a view model for a preloaded list of songs.
    ///
    /// - Returns: a SongBrowseViewModel instance
    public func songBrowseViewModel(random: Int) -> SongBrowseViewModel {
        return MPDSongBrowseViewModel(browse: self, filter: .random(random))
    }
    
    /// Return a view model for a preloaded list of songs.
    ///
    /// - Parameter songs: list of songs to show
    /// - Returns: a SongBrowseViewModel instance
    public func songBrowseViewModel(_ songs: [Song]) -> SongBrowseViewModel {
        return MPDSongBrowseViewModel(browse: self, songs: songs)
    }
    
    /// Return a view model for a list of songs in a playlist, which can return songs in batches.
    ///
    /// - Parameter playlist: playlist to filter on
    /// - Returns: a SongBrowseViewModel instance
    public func songBrowseViewModel(_ playlist: Playlist) -> SongBrowseViewModel {
        return MPDSongBrowseViewModel(browse: self, filter: .playlist(playlist))
    }
    
    /// Asynchronously get all songs in a playlist
    ///
    /// - Parameter playlist: the playlst to get the songs for
    /// - Returns: an observable array of Song objects
    public func songsInPlaylist(_ playlist: Playlist) -> Observable<[Song]> {
        let mpdConnector = self.mpdConnector
        let connectionProperties = self.connectionProperties

        return Observable<[Song]>.fromAsync {
            let songs = try await mpdConnector.playlist.listplaylistinfo(name: playlist.name)
            return songs
                .map {
                    Song(mpdSong: $0, connectionProperties: connectionProperties, forcePlayqueueId: true)
                }
        }
        .catchAndReturn([])
        .observe(on: MainScheduler.instance)
    }
    
    /// Return a view model for a list of songs in an album, which can return songs in batches.
    ///
    /// - Parameter album: album to filter on
    /// - Returns: a SongBrowseViewModel instance
    public func songBrowseViewModel(_ album: Album) -> SongBrowseViewModel {
        return MPDSongBrowseViewModel(browse: self, filter: .album(album))
    }
    
    /// Delete a playlist
    ///
    /// - Parameter playlist: the playlist to delete
    func deletePlaylist(_ playlist: Playlist) {
        Task {
            try? await mpdConnector.playlist.rm(name: playlist.id)
        }
    }
    
    /// Rename a playlist
    ///
    /// - Parameters:
    ///   - playlist: the playlist to rename
    ///   - newName: the new name to give to the playlist
    func renamePlaylist(_ playlist: Playlist, newName: String) {
        Task {
            try? await mpdConnector.playlist.rename(name: playlist.id, newName: newName)
        }
    }
    
    /// Return a view model for a list of genres, which can return genres in batches.
    ///
    /// - Returns: a GenreBrowseViewModel
    public func genreBrowseViewModel() -> GenreBrowseViewModel {
        return MPDGenreBrowseViewModel(browse: self)
    }

    /// Fetch an array of genres
    ///
    /// - Returns: an observable String array of genre names
    func fetchGenres() -> Observable<[Genre]> {
        let mpdConnector = self.mpdConnector
        return Observable<[Genre]>.fromAsync {
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
        .catchAndReturn([])
        .observe(on: MainScheduler.instance)
    }
    
    /// Return a view model for a list of items in the root folder. Contents might be returned in batches.
    ///
    /// - Returns: an observable FolderContent
    public func folderContentsBrowseViewModel() -> FolderBrowseViewModel {
        return MPDFolderBrowseViewModel(browse: self)
    }
    
    /// Return a view model for a list of items in a folder. Contents might be returned in batches.
    ///
    /// - Parameter folder: folder for which to get the contents. May be left empty to start from the root.
    /// - Returns: an observable FolderContent
    public func folderContentsBrowseViewModel(_ parentFolder: Folder) -> FolderBrowseViewModel {
        return MPDFolderBrowseViewModel(browse: self, parentFolder: parentFolder)
    }
    
    /// Fetch an array of genres
    ///
    /// - Returns: an observable String array of genre names
    func fetchFolderContents(parentFolder: Folder? = nil) -> Observable<[FolderContent]> {
        let mpdConnector = self.mpdConnector
        let connectionProperties = self.connectionProperties
        
        return Observable<[FolderContent]>.fromAsync {
            try await mpdConnector.database.lsinfo(uri: parentFolder?.path)
                .compactMap {
                    switch $0 {
                    case let .song(song):
                        return FolderContent.song(Song(mpdSong: song, connectionProperties: connectionProperties))
                    case let .playlist(playlist, lastModified):
                        return FolderContent.playlist(Playlist(id: playlist, source: .Local, name: playlist, lastModified: lastModified))
                    case let .directory(directory, _):
                        let components = directory.split(separator: "/")
                        if let folderName = components.last {
                            return FolderContent.folder(Folder(id: directory, source: .Local, path: directory, name: String(folderName)))
                        }
                        return nil
                    }
                }
        }
        .catchAndReturn([])
        .observe(on: MainScheduler.instance)
    }
    
    /// Get an Artist object for the artist performing a particular song
    ///
    /// - Parameter song: the song for which to get the artist
    /// - Returns: an observable Artist
    public func artistFromSong(_ song: Song) -> Observable<Artist> {
        return Observable.just(createArtistFromSong(song))
    }
    
    /// Get an Album object for the album on which a particular song appears
    ///
    /// - Parameter song: the song for which to get the album
    /// - Returns: an observable Album
    public func albumFromSong(_ song: Song) -> Observable<Album> {
        return Observable.just(createAlbumFromSong(song))
    }

    /// Return the tagtypes that are supported by a player
    ///
    /// - Returns: an array of tagtypes (strings)
    public func availableTagTypes() -> Observable<[String]> {
        let mpdConnector = self.mpdConnector
        
        return Observable<[String]>.fromAsync {
            try await mpdConnector.status.tagtypes()
        }
        .catchAndReturn([])
        .observe(on: MainScheduler.instance)
    }
    
    /// Return the commands that are supported by a player
    ///
    /// - Returns: an array of commands (strings)
    public func availableCommands() -> Observable<[String]> {
        let mpdConnector = self.mpdConnector
        
        return Observable<[String]>.fromAsync {
            try await mpdConnector.status.commands()
        }
        .catchAndReturn([])
        .observe(on: MainScheduler.instance)
    }
    
    /// Preprocess a CoverURI. This allows additional processing of base URI data.
    ///
    /// - Parameter coverURI: the CoverURI to pre-process
    /// - Returns: the processed cover URI
    public func preprocessCoverURI(_ coverURI: CoverURI) -> Observable<CoverURI> {
        let mpdConnector = self.mpdConnector
        
        return Observable<CoverURI>.fromAsync {
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
        .catchAndReturn(coverURI)
        .observe(on: MainScheduler.instance)
    }
    
    /// Filter artists that exist in the library
    /// - Parameter artist: the set of artists to check
    /// - Returns: an observable of the filtered array of artists
    public func existingArtists(artists: [Artist]) -> Observable<[Artist]> {
        fetchExistingArtists(artists: artists)
            .flatMap { [weak self] (artists) -> Observable<[Artist]> in
                guard let self else { 
                    return Observable.just([])
                }
                return self.completeArtists(artists)
            }
            .catchAndReturn([])
    }
    
    /// Complete data for a song
    /// - Parameter song: a song for which data must be completed
    /// - Returns: an observable song
    public func complete(_ song: Song) -> Observable<Song> {
        Observable.just(song)
    }

    /// Complete data for an album
    /// - Parameter album: an album for which data must be completed
    /// - Returns: an observable album
    public func complete(_ album: Album) -> Observable<Album> {
        Observable.just(album)
    }

    /// Complete data for an artist
    /// - Parameter artist: an artist for which data must be completed
    /// - Returns: an observable artist
    public func complete(_ artist: Artist) -> Observable<Artist> {
        Observable.just(artist)
    }
    
    func updateDB() {
        Task {
            _ = try? await mpdConnector.database.update(path: nil)
        }
    }
    
    func databaseStatus() -> Observable<String> {
        let mpdConnector = self.mpdConnector
        
        return Observable<String>.fromAsync {
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
        .catchAndReturn("")
        .observe(on: MainScheduler.instance)
    }
    
    public func imageDataFromCoverURI(_ coverURI: CoverURI) -> Observable<Data?> {
        guard coverURI.path != "" else { return Observable.just(nil) }
        return Observable<[Data?]>.fromAsync {
            return try? await self.mpdConnector.database.getAlbumart(path: coverURI.path)
        }
        .catchAndReturn(nil)
        .observe(on: MainScheduler.instance)

    }

    public func embeddedImageDataFromCoverURI(_ coverURI: CoverURI) -> Observable<Data?> {
        guard let path = coverURI.embeddedUri else { return Observable.just(nil) }
        return Observable<[Data?]>.fromAsync {
            return try? await self.mpdConnector.database.getReadpicture(path: path)
        }
        .catchAndReturn(nil)
        .observe(on: MainScheduler.instance)
    }

    /// Search for the existance a certain item
    /// - Parameter searchItem: what to search for
    /// - Returns: an observable array of results
    public func search(searchItem: SearchItem) -> Observable<[FoundItem]> {
        let mpdConnector = self.mpdConnector
        let connectionProperties = self.connectionProperties
        
        return Observable<[FoundItem]>.fromAsync {
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
        .catchAndReturn([])
        .observe(on: MainScheduler.instance)
    }
}
