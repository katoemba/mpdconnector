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
import libmpdclient
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
    /// Connection to a MPD Player
    private let mpd: MPDProtocol
    private var identification = ""
    private var connectionProperties: [String: Any]
    private let mpdConnector: SwiftMPD.MPDConnector

    private var scheduler: SchedulerType
    
    public init(mpd: MPDProtocol? = nil,
                connectionProperties: [String: Any],
                identification: String = "NoID",
                scheduler: SchedulerType? = nil,
                mpdConnector: SwiftMPD.MPDConnector) {
        self.mpd = mpd ?? MPDWrapper()
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
        switch artist.type {
        case .artist, .albumArtist:
            tag = .albumArtist
        case .composer:
            tag = .composer
        case .performer:
            tag = .performer
        }

        return try await mpdConnector.database.search(filter: .tagEquals(tag: tag, value: artist.name))
            .filter {
                album == nil || $0.album == album!
            }
            .map {
                Song(mpdSong: $0, connectionProperties: connectionProperties)
            }
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
        let version = connectionProperties[MPDConnectionProperties.version.rawValue] as! String
        guard MPDHelper.compareVersion(leftVersion: version, rightVersion: "0.20.19") == .orderedDescending else {
            return fetchRecentAlbums_below_0_20_20(numberOfDays: 183)
        }

        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observe(on: scheduler)
            .flatMap({ (mpdConnection) -> Observable<[Album]> in
                guard let connection = mpdConnection?.connection else { return Observable.just([]) }

                do {
                    var albums = [Album]()
                    
                    try self.mpd.search_db_songs(connection, exact: true)
                    try self.mpd.search_add_modified_since_constraint(connection, oper: MPD_OPERATOR_DEFAULT, since:Date(timeIntervalSince1970: TimeInterval(0)))
                    try self.mpd.search_add_sort_name(connection, name: "Last-Modified", descending: true)
                    try self.mpd.search_add_window(connection, start: 0, end: UInt32(numberOfAlbums * 24))
                    try self.mpd.search_commit(connection)
                    
                    var count = 0
                    var albumIDs = [String: Int]()
                    while let mpdSong = self.mpd.recv_song(connection) {
                        if let song = MPDHelper.songFromMpdSong(mpd: self.mpd, connectionProperties: self.connectionProperties, mpdSong: mpdSong), song.length > 0 {
                            let albumartist = (song.albumartist == "") ? song.artist : song.albumartist
                            let albumID = "\(albumartist):\(song.album)"
                            count += 1
                            if albumIDs[albumID] == nil {
                                albumIDs[albumID] = 1
                                albums.append(self.createAlbumFromSong(song))
                            }
                        }

                        self.mpd.song_free(mpdSong)
                    }
                    _ = self.mpd.response_finish(connection)
                    
                    return Observable.just(albums)
                }
                catch {
                    print(self.mpd.connection_get_error_message(connection))
                    _ = self.mpd.connection_clear_error(connection)
                    
                    return Observable.just([])
                }
            })
            .catchAndReturn([])
            .observe(on: MainScheduler.instance)
    }
    
    func fetchRecentAlbums_below_0_20_20(numberOfDays: Int = 0) -> Observable<[Album]> {
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observe(on: scheduler)
            .flatMap({ (mpdConnection) -> Observable<[Album]> in
                guard let connection = mpdConnection?.connection else { return Observable.just([]) }

                do {
                    var albums = [Album]()
                    
                    try self.mpd.search_db_songs(connection, exact: true)
                    try self.mpd.search_add_modified_since_constraint(connection, oper: MPD_OPERATOR_DEFAULT, since:Date(timeIntervalSinceNow: TimeInterval(-1 * (numberOfDays > 0 ? numberOfDays : 180) * 24 * 60 * 60)))
                    try self.mpd.search_commit(connection)
                    
                    var albumIDs = [String: Int]()
                    while let mpdSong = self.mpd.recv_song(connection) {
                        if let song = MPDHelper.songFromMpdSong(mpd: self.mpd, connectionProperties: self.connectionProperties, mpdSong: mpdSong), song.length > 0 {
                            let albumartist = (song.albumartist == "") ? song.artist : song.albumartist
                            let albumID = "\(albumartist):\(song.album)"
                            if albumIDs[albumID] == nil {
                                albumIDs[albumID] = 1
                                albums.append(self.createAlbumFromSong(song))
                            }
                        }

                        self.mpd.song_free(mpdSong)
                    }
                    _ = self.mpd.response_finish(connection)
                    
                    return Observable.just(albums.sorted(by: { (lhs, rhs) -> Bool in
                        return lhs.lastModified > rhs.lastModified
                    }))
                }
                catch {
                    print(self.mpd.connection_get_error_message(connection))
                    _ = self.mpd.connection_clear_error(connection)
                    
                    return Observable.just([])
                }
            })
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

    fileprivate func completeCoverURI(_ connection: OpaquePointer, _ coverURI: CoverURI) -> CoverURI {
        if case let .filenameOptionsURI(baseURI, path, filenames) = coverURI {
            var coverFiles = [String]()
            _ = self.mpd.send_list_files(connection, path: path)
            while let entity = self.mpd.recv_entity(connection) {
                if self.mpd.entity_get_type(entity) == MPD_ENTITY_TYPE_SONG {
                    let mpdSong = self.mpd.entity_get_song(entity)
                    let uri = self.mpd.song_get_uri(mpdSong)
                    
                    let components = uri.split(separator: "/")
                    if components.count > 0 {
                        let lastComponent = components[components.count - 1]
                        if (lastComponent.contains(".jpg") || lastComponent.contains(".png")) && lastComponent.starts(with: ".") == false {
                            coverFiles.append(String(lastComponent))
                        }
                    }
                }
                self.mpd.entity_free(entity)
            }
            _ = self.mpd.response_finish(connection)
            
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
    
    public func completeAlbums(_ albums: [Album]) -> Observable<[Album]> {
        Observable<[Album]>.fromAsync {
            var originalAlbums = albums
            var results = [Album]()
            
            var commands = [any CommandExecutor]()
            for album in albums {
                let expression = MPDDatabase.Expression.and(.tagEquals(tag: .album, value: album.title), .tagEquals(tag: .albumArtist, value: album.artist))
                commands.append(self.mpdConnector.database.findExecutor(filter: expression, range: 0..<1))
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
                commands.append(self.mpdConnector.database.findExecutor(filter: expression, range: 0..<1))
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
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observe(on: scheduler)
            .flatMap({ (mpdConnection) -> Observable<[Artist]> in
                guard let connection = mpdConnection?.connection else { return Observable.just([]) }

                do {
                    var artists = Set<Artist>()
                    
                    switch type {
                    case .artist:
                        try self.mpd.search_db_tags(connection, tagType: MPD_TAG_ARTIST)
                        try self.mpd.search_add_group_tag(connection, tagType: MPD_TAG_ARTIST_SORT)
                    case .albumArtist:
                        try self.mpd.search_db_tags(connection, tagType: MPD_TAG_ALBUM_ARTIST)
                        try self.mpd.search_add_group_tag(connection, tagType: MPD_TAG_ALBUM_ARTIST_SORT)
                    case .performer:
                        try self.mpd.search_db_tags(connection, tagType: MPD_TAG_PERFORMER)
                    case .composer:
                        try self.mpd.search_db_tags(connection, tagType: MPD_TAG_COMPOSER)
                    }
                    if let genre = genre, genre.id != "" {
                        try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_GENRE, value: genre.id)
                    }
                    try self.mpd.search_commit(connection)
                    
                    // Get pairs instead of looking by tag name, to ensure we also get the sort values if present.
                    var artist = ""
                    var sortArtist = ""
                    while let result = self.mpd.recv_pair(connection) {
                        let tagName = result.0
                        let value = result.1
                        let tag = self.mpd.tag_name_parse(tagName)
                        
                        if [MPD_TAG_ARTIST, MPD_TAG_ALBUM_ARTIST, MPD_TAG_PERFORMER, MPD_TAG_COMPOSER].contains(tag) {
                            artist = value
                            if artist != "" {
                                artists.insert(Artist(id: artist, type: type, source: .Local, name: artist, sortName: sortArtist))
                                artist = ""
                                sortArtist = ""
                            }
                        }
                        else if [MPD_TAG_ARTIST_SORT, MPD_TAG_ALBUM_ARTIST_SORT].contains(tag) {
                            sortArtist = value
                        }
                    }
                    
                    _ = self.mpd.response_finish(connection)

                    return Observable.just(artists.sorted(by: { (lhs, rhs) -> Bool in
                        let sortOrder = lhs.sortName.caseInsensitiveCompare(rhs.sortName)
                        if sortOrder == .orderedSame {
                            return lhs.name.caseInsensitiveCompare(rhs.name) == .orderedAscending
                        }
                        else {
                            return sortOrder == .orderedAscending
                        }
                    }))
                }
                catch {
                    print(self.mpd.connection_get_error_message(connection))
                    _ = self.mpd.connection_clear_error(connection)
                    
                    return Observable.just([])
                }
            })
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
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observe(on: scheduler)
            .flatMap({ (mpdConnection) -> Observable<[Playlist]> in
                guard let connection = mpdConnection?.connection else { return Observable.just([]) }

                var playlists = [Playlist]()
                
                if self.mpd.send_list_playlists(connection) == true {
                    var mpdPlaylist = self.mpd.recv_playlist(connection)
                    while mpdPlaylist != nil {
                        if let playlist = MPDHelper.playlistFromMpdPlaylist(mpd: self.mpd, mpdPlaylist: mpdPlaylist!) {
                            playlists.append(playlist)
                        }
                    
                        self.mpd.playlist_free(mpdPlaylist)
                        mpdPlaylist = self.mpd.recv_playlist(connection)
                    }
                }
                
                return Observable.just(playlists.sorted(by: { (lhs, rhs) -> Bool in
                    return lhs.name.caseInsensitiveCompare(rhs.name) == .orderedAscending
                }))
            })
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
            if let songs = try await mpdConnector.playlist.listplaylistinfo(name: playlist.name) {
                return songs
                    .map {
                        Song(mpdSong: $0, connectionProperties: connectionProperties)
                    }
            }
            return []
        }
        .catchAndReturn([])
        .observe(on: MainScheduler.instance)
    }
    
    /// Return a view model for a list of songs in an album, which can return songs in batches.
    ///
    /// - Parameter album: album to filter on
    /// - Returns: a SongBrowseViewModel instance
    public func songBrowseViewModel(_ album: Album, artist: Artist?) -> SongBrowseViewModel {
        if let artist = artist {
            return MPDSongBrowseViewModel(browse: self, filter: .album(album), subFilter: .artist(artist))
        }
        else {
            return MPDSongBrowseViewModel(browse: self, filter: .album(album))
        }
    }
    
    /// Return an array of songs for an artist and optional album. This will search through both artist and albumartist.
    ///
    /// - Parameters:
    ///   - connection: an active mpd connection
    ///   - playlist: the name of the playlist to get songs for
    /// - Returns: an array of Song objects
    private func songsForPlaylist(connection: OpaquePointer, playlist: String) -> [Song] {
        var songs = [Song]()
        
        if self.mpd.send_list_playlist_meta(connection, name: playlist) == true {
            var mpdSong = mpd.recv_song(connection)
            while mpdSong != nil {
                if var song = MPDHelper.songFromMpdSong(mpd: mpd, connectionProperties: connectionProperties, mpdSong: mpdSong) {
                    song.playqueueId = UUID().uuidString
                    songs.append(song)
                }
                self.mpd.song_free(mpdSong)
                mpdSong = mpd.recv_song(connection)
            }
            
            _ = self.mpd.response_finish(connection)
        }
        
        return songs
    }
    
    func fetchSongs(start: Int, count: Int) -> Observable<[Song]> {
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observe(on: scheduler)
            .flatMap({ (mpdConnection) -> Observable<[Song]> in
                guard let connection = mpdConnection?.connection else { return Observable.just([]) }

                do {
                    var songs = [Song]()
                    
                    try self.mpd.search_db_songs(connection, exact: true)
                    try self.mpd.search_add_modified_since_constraint(connection, oper: MPD_OPERATOR_DEFAULT, since:Date(timeIntervalSince1970: TimeInterval(0)))
                    try self.mpd.search_add_sort_name(connection, name: "Last-Modified", descending: true)
                    try self.mpd.search_add_window(connection, start: UInt32(start), end: UInt32(start + count))
                    try self.mpd.search_commit(connection)
                    
                    while let mpdSong = self.mpd.recv_song(connection) {
                        if let song = MPDHelper.songFromMpdSong(mpd: self.mpd, connectionProperties: self.connectionProperties, mpdSong: mpdSong), song.length > 0 {
                            songs.append(song)
                        }

                        self.mpd.song_free(mpdSong)
                    }
                    _ = self.mpd.response_finish(connection)
                    
                    return Observable.just(songs)
                }
                catch {
                    print(self.mpd.connection_get_error_message(connection))
                    _ = self.mpd.connection_clear_error(connection)
                    
                    return Observable.just([])
                }
            })
            .catchAndReturn([])
            .observe(on: MainScheduler.instance)
    }

    
    /// Delete a playlist
    ///
    /// - Parameter playlist: the playlist to delete
    func deletePlaylist(_ playlist: Playlist) {
        _ = MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observe(on: scheduler)
            .subscribe(onNext: { (mpdConnection) in
                guard let connection = mpdConnection?.connection else { return }

                _ = self.mpd.run_rm(connection, name: playlist.id)
            })
    }
    
    /// Rename a playlist
    ///
    /// - Parameters:
    ///   - playlist: the playlist to rename
    ///   - newName: the new name to give to the playlist
    func renamePlaylist(_ playlist: Playlist, newName: String) {
        _ = MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observe(on: scheduler)
            .subscribe(onNext: { (mpdConnection) in
                guard let connection = mpdConnection?.connection else { return }

                _ = self.mpd.run_rename(connection, from: playlist.id, to: newName)
            })
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
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observe(on: scheduler)
            .flatMap({ (mpdConnection) -> Observable<[Genre]> in
                guard let connection = mpdConnection?.connection else { return Observable.just([]) }

                do {
                    var genres = [Genre]()
                    
                    try self.mpd.search_db_tags(connection, tagType: MPD_TAG_GENRE)
                    try self.mpd.search_commit(connection)
                    
                    while let result = self.mpd.recv_pair_tag(connection, tagType: MPD_TAG_GENRE) {
                        let genreName = result.1
                        if genreName != "" {
                            genres.append(Genre(id: genreName, source: .Local, name: genreName))
                        }
                    }
                    _ = self.mpd.response_finish(connection)
                    
                    return Observable.just(genres)
                    //return Observable.just(genres.sorted(by: { (lhs, rhs) -> Bool in
                    //    return lhs.caseInsensitiveCompare(rhs) == .orderedAscending
                    //}))
                }
                catch {
                    print(self.mpd.connection_get_error_message(connection))
                    _ = self.mpd.connection_clear_error(connection)
                    
                    return Observable.just([])
                }
            })
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
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observe(on: scheduler)
            .flatMap({ (mpdConnection) -> Observable<[FolderContent]> in
                guard let connection = mpdConnection?.connection else { return Observable.just([]) }

                do {
                    var folderContents = [FolderContent]()
                    
                    if self.mpd.send_list_meta(connection, path: parentFolder?.path ?? "") == true {
                        var mpdEntity = self.mpd.recv_entity(connection)
                        while mpdEntity != nil {
                            switch self.mpd.entity_get_type(mpdEntity) {
                            case MPD_ENTITY_TYPE_SONG:
                                if let mpdSong = self.mpd.entity_get_song(mpdEntity) {
                                    if let song = MPDHelper.songFromMpdSong(mpd: self.mpd, connectionProperties: self.connectionProperties, mpdSong: mpdSong), song.length > 0 {
                                        folderContents.append(FolderContent.song(song))
                                    }
                                }
                                break
                            case MPD_ENTITY_TYPE_DIRECTORY:
                                if let mpdDirectory = self.mpd.entity_get_directory(mpdEntity) {
                                    if let folder = MPDHelper.folderFromMPDDirectory(mpd: self.mpd, mpdDirectory: mpdDirectory) {
                                        folderContents.append(FolderContent.folder(folder))
                                    }
                                }
                                break
                            case MPD_ENTITY_TYPE_PLAYLIST:
                                if let mpdPlaylist = self.mpd.entity_get_playlist(mpdEntity) {
                                    if let playlist = MPDHelper.playlistFromMpdPlaylist(mpd: self.mpd, mpdPlaylist: mpdPlaylist) {
                                        folderContents.append(FolderContent.playlist(playlist))                                        
                                    }
                                }
                                break
                            case MPD_ENTITY_TYPE_UNKNOWN:
                                break
                            default:
                                break
                            }
                            
                            self.mpd.entity_free(mpdEntity)
                            mpdEntity = self.mpd.recv_entity(connection)
                        }
                    }
                    
                    return Observable.just(folderContents)
                }
            })
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
        let mpd = self.mpd
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observe(on: scheduler)
            .flatMap({ (mpdConnection) -> Observable<[String]> in
                guard let connection = mpdConnection?.connection else { return Observable.just([]) }

                var tagTypes = [String]()
                _ = mpd.send_list_tag_types(connection)
                while let pair = mpd.recv_tag_type_pair(connection) {
                    tagTypes.append(pair.1)
                }
                
                _ = mpd.response_finish(connection)
                
                return Observable.just(tagTypes)
            })
    }
    
    /// Return the commands that are supported by a player
    ///
    /// - Returns: an array of commands (strings)
    public func availableCommands() -> Observable<[String]> {
        let mpd = self.mpd
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observe(on: scheduler)
            .flatMap({ (mpdConnection) -> Observable<[String]> in
                guard let connection = mpdConnection?.connection else { return Observable.just([]) }

                var commands = [String]()
                _ = mpd.send_allowed_commands(connection)
                while let pair = mpd.recv_pair_named(connection, name: "command") {
                    commands.append(pair.1)
                }
                
                _ = mpd.response_finish(connection)
                
                return Observable.just(commands)
            })
            .catchAndReturn([])
    }
    
    /// Preprocess a CoverURI. This allows additional processing of base URI data.
    ///
    /// - Parameter coverURI: the CoverURI to pre-process
    /// - Returns: the processed cover URI
    public func preprocessCoverURI(_ coverURI: CoverURI) -> Observable<CoverURI> {
        let mpd = self.mpd
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observe(on: scheduler)
            .flatMap({ [weak self] (mpdConnection) -> Observable<CoverURI> in
                guard let connection = mpdConnection?.connection else { return Observable.just(coverURI) }

                guard let weakSelf = self else {
                    return Observable.just(coverURI)
                }

                let updatedCoverURI = weakSelf.completeCoverURI(connection, coverURI)
                return Observable.just(updatedCoverURI)
            })
    }
    
    /// Filter artists that exist in the library
    /// - Parameter artist: the set of artists to check
    /// - Returns: an observable of the filtered array of artists
    public func existingArtists(artists: [Artist]) -> Observable<[Artist]> {
        return fetchExistingArtists(artists: artists)
            .flatMap { [weak self] (artists) -> Observable<[Artist]> in
                guard let weakSelf = self else { return Observable.just([]) }
                return weakSelf.completeArtists(artists)
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
        _ = MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observe(on: scheduler)
            .subscribe(onNext: { (mpdConnection) in
                guard let connection = mpdConnection?.connection else { return }

                _ = self.mpd.run_update(connection, path: nil)
            })
    }
    
    func databaseStatus() -> Observable<String> {
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observe(on: scheduler)
            .flatMapFirst({ (mpdConnection) -> Observable<String> in
                guard let connection = mpdConnection?.connection else { return Observable.just("") }

                var updateId = UInt32(0)
                var lastUpdateDate = Date(timeIntervalSince1970: 0)
                if let status = self.mpd.run_status(connection) {
                    defer {
                        self.mpd.status_free(status)
                    }
                    
                    updateId = self.mpd.status_get_update_id(status)
                    if let mpdStats = self.mpd.run_stats(connection) {
                        defer {
                            self.mpd.stats_free(mpdStats)
                        }
                        lastUpdateDate = self.mpd.stats_get_db_update_time(mpdStats)
                    }
                }
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                dateFormatter.timeStyle = .short
                if updateId > 0 {
                    return Observable.just("Updating...")
                }
                return Observable.just("Last updated: \(dateFormatter.string(from: lastUpdateDate))")
            })
            .catchAndReturn("Couldn't read status.")
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
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observe(on: scheduler)
            .flatMap({ (mpdConnection) -> Observable<[FoundItem]> in
                guard let connection = mpdConnection?.connection else { return Observable.just([]) }

                var foundItems = Set<FoundItem>()
                do {
                    switch searchItem {
                    case let .artist(artist):
                        try self.mpd.search_db_songs(connection, exact: false)
                        try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_ARTIST, value: artist)
                        try self.mpd.search_add_window(connection, start: 0, end: 100)
                        try self.mpd.search_commit(connection)
                        while let mpdSong = self.mpd.recv_song(connection) {
                            if let song = MPDHelper.songFromMpdSong(mpd: self.mpd, connectionProperties: self.connectionProperties, mpdSong: mpdSong) {
                                foundItems.insert(.artist(self.createArtistFromSong(song)))
                            }
                            self.mpd.song_free(mpdSong)
                        }
                        _ = self.mpd.response_finish(connection)
                    case let .artistAlbum(artist: artist, sort: sort):
                        try self.mpd.search_db_songs(connection, exact: false)
                        try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_ALBUM_ARTIST, value: artist)
                        if sort == .year || sort == .yearReverse {
                            try self.mpd.search_add_sort_tag(connection, tagType: MPD_TAG_DATE, descending: sort == .yearReverse)
                        }
                        // When sorting, only pick the first match
                        try self.mpd.search_add_window(connection, start: 0, end: 1)
                        try self.mpd.search_commit(connection)
                        while let mpdSong = self.mpd.recv_song(connection) {
                            if let song = MPDHelper.songFromMpdSong(mpd: self.mpd, connectionProperties: self.connectionProperties, mpdSong: mpdSong) {
                                foundItems.insert(.album(self.createAlbumFromSong(song)))
                            }
                            self.mpd.song_free(mpdSong)
                        }
                        _ = self.mpd.response_finish(connection)
                    case let .album(album, artist):
                        try self.mpd.search_db_songs(connection, exact: false)
                        try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_ALBUM, value: album)
                        if artist != nil {
                            try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_ALBUM_ARTIST, value: artist!)
                        }
                        try self.mpd.search_add_window(connection, start: 0, end: 100)
                        try self.mpd.search_commit(connection)
                        while let mpdSong = self.mpd.recv_song(connection) {
                            if let song = MPDHelper.songFromMpdSong(mpd: self.mpd, connectionProperties: self.connectionProperties, mpdSong: mpdSong) {
                                foundItems.insert(.album(self.createAlbumFromSong(song)))
                            }
                            self.mpd.song_free(mpdSong)
                        }
                        _ = self.mpd.response_finish(connection)
                    case let .genre(genre):
                        try self.mpd.search_db_tags(connection, tagType: MPD_TAG_GENRE)
                        try self.mpd.search_commit(connection)
                        while let result = self.mpd.recv_pair_tag(connection, tagType: MPD_TAG_GENRE) {
                            if result.1.lowercased() == genre.lowercased() {
                                foundItems.insert(.genre(Genre(id: result.1, source: .Local, name: result.1)))
                            }
                        }
                        _ = self.mpd.response_finish(connection)
                    case let .song(title, artist):
                        try self.mpd.search_db_songs(connection, exact: false)
                        try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_TITLE, value: title)
                        if artist != nil {
                            try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_ARTIST, value: artist!)
                        }
                        try self.mpd.search_add_window(connection, start: 0, end: 100)
                        try self.mpd.search_commit(connection)
                        while let mpdSong = self.mpd.recv_song(connection) {
                            if let song = MPDHelper.songFromMpdSong(mpd: self.mpd, connectionProperties: self.connectionProperties, mpdSong: mpdSong) {
                                foundItems.insert(.song(song))
                            }
                            self.mpd.song_free(mpdSong)
                        }
                        _ = self.mpd.response_finish(connection)
                    default:
                        break
                    }
                }
                
                return Observable.just(Array(foundItems))
            })
    }
}
