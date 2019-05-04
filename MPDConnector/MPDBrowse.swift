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
import RxCocoa

extension Array where Element:Hashable {
    var orderedSet: Array {
        var unique = Set<Element>()
        return filter { element in
            return unique.insert(element).inserted
        }
    }
}

public class MPDBrowse: BrowseProtocol {
    private static var operationQueue: OperationQueue?
    /// Connection to a MPD Player
    private let mpd: MPDProtocol
    private var identification = ""
    private var connectionProperties: [String: Any]
    
    private var scheduler: SchedulerType
    
    public init(mpd: MPDProtocol? = nil,
                connectionProperties: [String: Any],
                identification: String = "NoID",
                scheduler: SchedulerType? = nil) {
        self.mpd = mpd ?? MPDWrapper()
        self.identification = identification
        self.connectionProperties = connectionProperties

        self.scheduler = scheduler ?? ConcurrentDispatchQueueScheduler(qos: .background)
        HelpMePlease.allocUp(name: "MPDBrowse")
    }
    
    /// Cleanup connection object
    deinit {
        HelpMePlease.allocDown(name: "MPDBrowse")
    }

    public func search(_ search: String, limit: Int = 20, filter: [SourceType] = []) -> Observable<SearchResult> {
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observeOn(scheduler)
            .flatMap({ (mpdConnection) -> Observable<SearchResult> in
                guard let connection = mpdConnection?.connection else { return Observable.just(SearchResult()) }

                let artistSearchResult = self.searchType(search, connection: connection, tagType: MPD_TAG_ARTIST, filter: filter)
                let albumSearchResult = self.searchType(search, connection: connection, tagType: MPD_TAG_ALBUM, filter: filter)
                let songSearchResult = self.searchType(search, connection: connection, tagType: MPD_TAG_TITLE, filter: filter)
                let performerSearchResult = self.searchType(search, connection: connection, tagType: MPD_TAG_PERFORMER, filter: filter)
                let composerSearchResult = self.searchType(search, connection: connection, tagType: MPD_TAG_COMPOSER, filter: filter)

                var searchResult = SearchResult()
                searchResult.artists = (artistSearchResult.artists + albumSearchResult.artists + songSearchResult.artists).orderedSet
                searchResult.albums = (albumSearchResult.albums + artistSearchResult.albums + songSearchResult.albums).orderedSet
                searchResult.songs = (songSearchResult.songs + artistSearchResult.songs + albumSearchResult.songs).orderedSet
                searchResult.performers = performerSearchResult.performers.orderedSet
                searchResult.composers = composerSearchResult.composers.orderedSet

                return Observable.just(searchResult)
            })
    }
    
    private func searchType(_ search: String, connection: OpaquePointer, tagType: mpd_tag_type, filter: [SourceType] = []) -> SearchResult {
        var songs = [Song]()
        var albums = [Album]()
        var artists = [Artist]()
        var performers = [Artist]()
        var composers = [Artist]()
        do {
            try mpd.search_db_songs(connection, exact: false)
            try mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: tagType, value: search)
            try mpd.search_commit(connection)
            
            var mpdSong = mpd.recv_song(connection)
            while mpdSong != nil {
                if let song = MPDHelper.songFromMpdSong(mpd: mpd, connectionProperties: connectionProperties, mpdSong: mpdSong) {
                    if song.id.starts(with: "podcast+") {
                        if filter.count == 0 || filter.contains(.Podcast) == true {
                            // Process podcast
                        }
                    }
                    else if song.id.contains("spotify") {
                        if filter.count == 0 || filter.contains(.Spotify) == true {
                            if song.id.contains(":album:") {
                                var album = Album(id: song.id, source: song.source, location: "", title: song.album, artist: song.artist, year: song.year, genre: song.genre, length: song.length)
                                album.coverURI = song.coverURI
                                albums.append(album)
                            }
                            else if song.id.contains(":artist:") {
                                artists.append(Artist(id: song.id, source: song.source, name: song.artist))
                            }
                            else {
                                songs.append(song)
                            }
                        }
                    }
                    else {
                        if filter.count == 0 || filter.contains(.Local) == true {
                            if (tagType == MPD_TAG_TITLE) {
                                songs.append(song)
                            }
                            else if (tagType == MPD_TAG_ALBUM) {
                                var album = Album(id: "\(song.albumartist):\(song.album)", source: .Local, location: "", title: song.album, artist: song.albumartist, year: song.year, genre: song.genre, length: 0)
                                album.coverURI = song.coverURI
                                if albums.contains(album) == false {
                                    albums.append(album)
                                }
                            }
                            else if (tagType == MPD_TAG_ARTIST) {
                                let artist = Artist(id: song.artist, source: .Local, name: song.artist)
                                if artists.contains(artist) == false {
                                    artists.append(artist)
                                }
                            }
                            else if (tagType == MPD_TAG_PERFORMER) {
                                let performer = Artist(id: song.performer, type: .performer, source: .Local, name: song.performer)
                                if performers.contains(performer) == false {
                                    performers.append(performer)
                                }
                            }
                            else if (tagType == MPD_TAG_COMPOSER) {
                                let composer = Artist(id: song.composer, type: .composer, source: .Local, name: song.composer)
                                if composers.contains(composer) == false {
                                    composers.append(composer)
                                }
                            }
                        }
                    }
                }
                
                mpd.song_free(mpdSong)
                mpdSong = mpd.recv_song(connection)
            }
        }
        catch {
            print(mpd.connection_get_error_message(connection))
            _ = mpd.connection_clear_error(connection)
        }
        
        // Cleanup
        _ = mpd.response_finish(connection)
        
        var searchResult = SearchResult.init()
        
        searchResult.songs = songs
        searchResult.albums = albums
        searchResult.artists = artists
        searchResult.performers = performers
        searchResult.composers = composers

        return searchResult
    }
    
    /// Return an array of songs for an artist and optional album. This will search through both artist and albumartist.
    ///
    /// - Parameters:
    ///   - connection: an active mpd connection
    ///   - artist: the artist name to search for
    ///   - album: optionally an album title to search for
    /// - Returns: an array of Song objects
    private func songsForArtistAndOrAlbum(connection: OpaquePointer, artist: Artist, album: String? = nil) -> [Song] {
        var songs = [Song]()
        var songIDs = [String: Int]()
        var tagTypes = [MPD_TAG_ARTIST, MPD_TAG_ALBUM_ARTIST]
        if artist.type == .composer {
            tagTypes = [MPD_TAG_COMPOSER]
        }
        else if artist.type == .performer {
            tagTypes = [MPD_TAG_PERFORMER]
        }
        for tagType in tagTypes {
            do {
                try self.mpd.search_db_songs(connection, exact: true)
                try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: tagType, value: artist.name)
                // Some mpd versions (on Bryston) don't pick up the album correctly for wav files.
                // Therefor don't add the album as search constraint, instead filter when the songs are retrieved.
                //if let album = album {
                //    try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_ALBUM, value: album)
                //}
                try self.mpd.search_commit(connection)
                
                var mpdSong = self.mpd.recv_song(connection)
                while mpdSong != nil {
                    if let song = MPDHelper.songFromMpdSong(mpd: self.mpd, connectionProperties: self.connectionProperties, mpdSong: mpdSong) {
                        if album == nil || album == song.album, songIDs[song.id] == nil {
                            songIDs[song.id] = 1
                            songs.append(song)
                        }
                    }
                    
                    self.mpd.song_free(mpdSong)
                    mpdSong = self.mpd.recv_song(connection)
                }
            }
            catch {
                print(self.mpd.connection_get_error_message(connection))
                _ = self.mpd.connection_clear_error(connection)
            }
            
            _ = self.mpd.response_finish(connection)
        }
        
        if songs.count == 0 || album == nil {
            do {
                try self.mpd.search_db_songs(connection, exact: true)
                try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_ALBUM, value: "")
                try self.mpd.search_commit(connection)
                
                while let mpdSong = self.mpd.recv_song(connection) {
                    if let song = MPDHelper.songFromMpdSong(mpd: self.mpd, connectionProperties: self.connectionProperties, mpdSong: mpdSong), song.length > 0 {
                        let albumartist = (song.albumartist == "") ? song.artist : song.albumartist
                        if artist.name == albumartist && (album == nil || album == song.album) {
                            songs.append(song)
                        }
                    }
                    self.mpd.song_free(mpdSong)
                }
                _ = self.mpd.response_finish(connection)
            }
            catch {
                print(self.mpd.connection_get_error_message(connection))
                _ = self.mpd.connection_clear_error(connection)
            }
        }
        
        return songs
    }
    
    /// Asynchronously get all songs on an album
    ///
    /// - Parameter album: the album to get the songs for
    /// - Parameter artist: An optional Artist object, allowing to filter the songs by a specific artist
    /// - Returns: an observable array of Song objects
    public func songsOnAlbum(_ album: Album) -> Observable<[Song]> {
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observeOn(scheduler)
            .flatMap({ (mpdConnection) -> Observable<[Song]> in
                guard let connection = mpdConnection?.connection else { return Observable.just([]) }

                let artist = Artist(id: album.artist, type: .artist, source: .Local, name: album.artist)
                let songs = self.songsForArtistAndOrAlbum(connection: connection, artist: artist, album: album.title)
                
                return Observable.just(songs)
            })
            .observeOn(MainScheduler.instance)
    }

    /// Asynchronously get all songs for an artist
    ///
    /// - Parameters:
    ///   - artist: the artist to get the songs for
    /// - Returns: an observable array of Song objects
    public func songsByArtist(_ artist: Artist) -> Observable<[Song]> {
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observeOn(scheduler)
            .flatMap({ (mpdConnection) -> Observable<[Song]> in
                guard let connection = mpdConnection?.connection else { return Observable.just([]) }

                let songs = self.songsForArtistAndOrAlbum(connection: connection, artist: artist)
                
                return Observable.just(songs)
            })
            .observeOn(MainScheduler.instance)
    }
    
    public func randomSongs(count: Int) -> Observable<[Song]> {
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observeOn(scheduler)
            .flatMap({ (mpdConnection) -> Observable<[Song]> in
                guard let connection = mpdConnection?.connection else { return Observable.just([]) }
                
                var songIds = [String]()
                _ = self.mpd.send_list_all(connection, path: "")
                
                while let pair = self.mpd.recv_pair(connection) {
                    if pair.0 == "file" {
                        songIds.append(pair.1)
                    }
                }
                _ = self.mpd.response_finish(connection)

                var randomSongs = [Song]()
                for _ in 0..<count {
                    if let songId = songIds.randomElement() {
                        var song = Song()
                        song.id = songId
                        randomSongs.append(song)
                    }
                }
                return Observable.just(randomSongs)
            })
            .observeOn(MainScheduler.instance)
    }
    
    private func createArtistFromSong(_ song: Song) -> Artist {
        return Artist(id: song.artist, source: song.source, name: song.artist)
    }
    
    private func createAlbumFromSong(_ song: Song) -> Album {
        let artist = song.albumartist != "" ? song.albumartist : song.artist
        var album = Album(id: "\(artist):\(song.album)", source: song.source, location: "", title: song.album, artist: artist, year: song.year, genre: song.genre, length: 0)
        album.coverURI = song.coverURI
        album.lastModified = song.lastModified
    
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
        
        return albums.sorted(by: { (lhs, rhs) -> Bool in
            if sort == .year || sort == .yearReverse {
                if lhs.year < rhs.year {
                    return sort == .year
                }
                else if lhs.year > rhs.year {
                    return sort == .yearReverse
                }
            }
            
            let albumCompare = lhs.title.caseInsensitiveCompare(rhs.title)
            if albumCompare == .orderedAscending {
                return true
            }
            
            return false
        })
    }
    /// - Parameters:
    ///   - artist: An Artist object.
    ///   - sort: How to sort the albums.
    /// - Returns: An observable array of fully populated Album objects.
    public func albumsByArtist(_ artist: Artist, sort: SortType) -> Observable<[Album]> {
        return songsByArtist(artist)
            .flatMap({ [weak self] (songs) -> Observable<[Album]> in
                guard let weakself = self else { return Observable.empty() }
                
                return Observable.just(weakself.albumsFromSongs(songs, sort: sort))
            })
            .observeOn(MainScheduler.instance)
    }
    
    func fetchRecentAlbums(numberOfDays: Int = 0) -> Observable<[Album]> {
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observeOn(scheduler)
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
                    
                    return Observable.empty()
                }
            })
            .observeOn(MainScheduler.instance)
    }

    func fetchAlbums(genre: String?, sort: SortType) -> Observable<[Album]> {
        let version = connectionProperties[MPDConnectionProperties.version.rawValue] as! String
        if MPDHelper.compareVersion(leftVersion: version, rightVersion: "0.20.22") == .orderedAscending {
            return fetchAlbums_below_20_22(genre: genre, sort: sort)
        }
        else {
            return fetchAlbums_20_22_and_above(genre: genre, sort: sort)
        }
    }
    
    // This is the old-fashioned way of getting data, using a double group by.
    func fetchAlbums_below_20_22(genre: String?, sort: SortType) -> Observable<[Album]> {
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observeOn(scheduler)
            .flatMap({ (mpdConnection) -> Observable<[Album]> in
                guard let connection = mpdConnection?.connection else { return Observable.just([]) }

                do {
                    var foundEmptyAlbum = false
                    var albums = [Album]()
                    
                    try self.mpd.search_db_tags(connection, tagType: MPD_TAG_ALBUM)
                    if let genre = genre, genre != "" {
                        try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_GENRE, value: genre)
                    }
                    try self.mpd.search_add_group_tag(connection, tagType: MPD_TAG_ALBUM_ARTIST)
                    if sort == .year || sort == .yearReverse {
                        try self.mpd.search_add_group_tag(connection, tagType: MPD_TAG_DATE)
                    }
                    try self.mpd.search_commit(connection)
                    
                    var albumIDs = [String: Int]()
                    while let result = self.mpd.recv_pair_tag(connection, tagType: MPD_TAG_ALBUM) {
                        let title = result.1
                        if title != "" {
                            let albumArtist = self.mpd.recv_pair_tag(connection, tagType: MPD_TAG_ALBUM_ARTIST)?.1 ?? "Unknown"
                            var year = 0
                            if sort == .year || sort == .yearReverse {
                                let yearString = self.mpd.recv_pair_tag(connection, tagType: MPD_TAG_DATE)?.1 ?? "0"
                                year = Int(String(yearString.prefix(4))) ?? 0
                            }
                            
                            let albumID = "\(albumArtist):\(title)"
                            // Ensure that every album only gets added once. When grouping on year it might appear multiple times.
                            if albumIDs[albumID] == nil {
                                albumIDs[albumID] = 1
                                let album = Album(id: albumID, source: .Local, location: "", title: title, artist: albumArtist, year: year, genre: [], length: 0)
                                albums.append(album)
                            }
                        }
                            //else if genre != nil {
                        else {
                            foundEmptyAlbum = true
                        }
                    }
                    _ = self.mpd.response_finish(connection)
                    
                    // Some mpd versions (on Bryston) don't pick up the album correctly for wav files.
                    // If an empty album is found, do an additional search empty albums within the genre, and get the album via the song.
                    if foundEmptyAlbum {
                        try self.mpd.search_db_songs(connection, exact: true)
                        if let genre = genre, genre != "" {
                            try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_GENRE, value: genre)
                        }
                        try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_ALBUM, value: "")
                        try self.mpd.search_commit(connection)
                        
                        while let mpdSong = self.mpd.recv_song(connection) {
                            if let song = MPDHelper.songFromMpdSong(mpd: self.mpd, connectionProperties: self.connectionProperties, mpdSong: mpdSong), song.length > 0 {
                                let albumartist = (song.albumartist == "") ? song.artist : song.albumartist
                                if albumartist != "" {
                                    let albumID = "\(albumartist):\(song.album)"
                                    if albumIDs[albumID] == nil {
                                        albumIDs[albumID] = 1
                                        albums.append(self.createAlbumFromSong(song))
                                    }
                                }
                            }
                            self.mpd.song_free(mpdSong)
                        }
                        _ = self.mpd.response_finish(connection)
                    }
                    
                    return Observable.just(albums.sorted(by: { (lhs, rhs) -> Bool in
                        if sort == .year || sort == .yearReverse {
                            if lhs.year < rhs.year {
                                return sort == .year
                            }
                            else if lhs.year > rhs.year {
                                return sort == .yearReverse
                            }
                        }
                        
                        if sort == .artist {
                            let artistCompare = lhs.sortArtist.caseInsensitiveCompare(rhs.sortArtist)
                            if artistCompare == .orderedAscending {
                                return true
                            }
                            if artistCompare == .orderedDescending {
                                return false
                            }
                        }
                        
                        let albumCompare = lhs.title.caseInsensitiveCompare(rhs.title)
                        if albumCompare == .orderedAscending {
                            return true
                        }
                        
                        return false
                    }))
                }
                catch {
                    print(self.mpd.connection_get_error_message(connection))
                    _ = self.mpd.connection_clear_error(connection)
                    
                    return Observable.empty()
                }
            })
            .observeOn(MainScheduler.instance)
    }
    
    // The grouping was changed in 0.20.22 and above. It works more consistently it seems,
    // but because of mpd bug https://github.com/MusicPlayerDaemon/MPD/issues/408 multiple group-by's are not possible
    func fetchAlbums_20_22_and_above(genre: String?, sort: SortType) -> Observable<[Album]> {
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observeOn(scheduler)
            .flatMap({ (mpdConnection) -> Observable<[Album]> in
                guard let connection = mpdConnection?.connection else { return Observable.just([]) }

                do {
                    var foundEmptyAlbum = false
                    var albums = [Album]()
                    
                    try self.mpd.search_db_tags(connection, tagType: MPD_TAG_ALBUM)
                    if let genre = genre, genre != "" {
                        try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_GENRE, value: genre)
                    }
                    try self.mpd.search_add_group_tag(connection, tagType: MPD_TAG_ALBUM_ARTIST)
                    try self.mpd.search_commit(connection)
                    
                    var albumIDs = [String: Int]()
                    
                    var albumArtist = ""
                    let year = 0
                    while let result = self.mpd.recv_pair(connection) {
                        let tagName = result.0
                        let value = result.1
                        let tag = self.mpd.tag_name_parse(tagName)
                        
                        if value != "" {
                            if tag == MPD_TAG_ALBUM_ARTIST {
                                albumArtist = value
                            }
                            else if tag == MPD_TAG_ALBUM {
                                let title = value
                                let albumID = "\(albumArtist):\(title)"
                                // Ensure that every album only gets added once. When grouping on year it might appear multiple times.
                                if albumIDs[albumID] == nil {
                                    albumIDs[albumID] = 1
                                    let album = Album(id: albumID, source: .Local, location: "", title: title, artist: albumArtist, year: year, genre: [], length: 0)
                                    albums.append(album)
                                }
                            }
                            else {
                                print("Unknown tagName \(tagName) tag \(tag)")
                            }
                        }
                        else {
                            foundEmptyAlbum = true
                        }
                    }

                    _ = self.mpd.response_finish(connection)

                    // Some mpd versions (on Bryston) don't pick up the album correctly for wav files.
                    // If an empty album is found, do an additional search empty albums within the genre, and get the album via the song.
                    if foundEmptyAlbum {
                        try self.mpd.search_db_songs(connection, exact: true)
                        if let genre = genre, genre != "" {
                            try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_GENRE, value: genre)
                        }
                        try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_ALBUM, value: "")
                        try self.mpd.search_commit(connection)
                        
                        while let mpdSong = self.mpd.recv_song(connection) {
                            if let song = MPDHelper.songFromMpdSong(mpd: self.mpd, connectionProperties: self.connectionProperties, mpdSong: mpdSong), song.length > 0 {
                                let albumartist = (song.albumartist == "") ? song.artist : song.albumartist
                                if albumartist != "" {
                                    let albumID = "\(albumartist):\(song.album)"
                                    if albumIDs[albumID] == nil {
                                        albumIDs[albumID] = 1
                                        albums.append(self.createAlbumFromSong(song))
                                    }
                                }
                            }
                            self.mpd.song_free(mpdSong)
                        }
                        _ = self.mpd.response_finish(connection)
                    }
                    
                    return Observable.just(albums.sorted(by: { (lhs, rhs) -> Bool in
                        if sort == .year || sort == .yearReverse {
                            if lhs.year < rhs.year {
                                return sort == .year
                            }
                            else if lhs.year > rhs.year {
                                return sort == .yearReverse
                            }
                        }

                        if sort == .artist {
                            let artistCompare = lhs.sortArtist.caseInsensitiveCompare(rhs.sortArtist)
                            if artistCompare == .orderedAscending {
                                return true
                            }
                            if artistCompare == .orderedDescending {
                                return false
                            }
                        }
                        
                        let albumCompare = lhs.title.caseInsensitiveCompare(rhs.title)
                        if albumCompare == .orderedAscending {
                            return true
                        }

                        return false
                    }))
                }
                catch {
                    print(self.mpd.connection_get_error_message(connection))
                    _ = self.mpd.connection_clear_error(connection)
                    
                    return Observable.empty()
                }
            })
            .observeOn(MainScheduler.instance)
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
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observeOn(scheduler)
            .flatMap({ (mpdConnection) -> Observable<[Album]> in
                guard let connection = mpdConnection?.connection else { return Observable.just([]) }

                var completeAlbums = [Album]()
                for album in albums {
                    var song : Song?

                    do {
                        try self.mpd.search_db_songs(connection, exact: true)
                        try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_ALBUM, value: album.title)
                        try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_ALBUM_ARTIST, value: album.artist)
                        try self.mpd.search_commit(connection)
                        
                        if let mpdSong = self.mpd.recv_song(connection) {
                            song = MPDHelper.songFromMpdSong(mpd: self.mpd, connectionProperties: self.connectionProperties, mpdSong: mpdSong)
                            self.mpd.song_free(mpdSong)
                        }
                    }
                    catch {
                        print(self.mpd.connection_get_error_message(connection))
                        _ = self.mpd.connection_clear_error(connection)
                    }
                    
                    // Cleanup
                    _ = self.mpd.response_finish(connection)
                    
                    if song != nil {
                        completeAlbums.append(self.createAlbumFromSong(song!))
                    }
                    else {
                        completeAlbums.append(album)
                    }
                }
                
                return Observable.just(completeAlbums)
            })
            .observeOn(MainScheduler.instance)
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
    
    /// Return a view model for a list of albums filtered by artist, which can return albums in batches.
    ///
    /// - Parameter genre: genre to filter on
    /// - Returns: an AlbumBrowseViewModel instance
    public func albumBrowseViewModel(_ genre: String) -> AlbumBrowseViewModel {
        return MPDAlbumBrowseViewModel(browse: self, filters: [.genre(genre)])
    }
    
    /// Return a view model for a preloaded list of albums.
    ///
    /// - Parameter albums: list of albums to show
    /// - Returns: an AlbumBrowseViewModel instance
    public func albumBrowseViewModel(_ albums: [Album]) -> AlbumBrowseViewModel {
        return MPDAlbumBrowseViewModel(browse:self, albums: albums)
    }

    public func fetchArtists(genre: String?, type: ArtistType) -> Observable<[Artist]> {
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observeOn(scheduler)
            .flatMap({ (mpdConnection) -> Observable<[Artist]> in
                guard let connection = mpdConnection?.connection else { return Observable.just([]) }

                do {
                    var artists = [Artist]()
                    
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
                    if let genre = genre, genre != "" {
                        try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_GENRE, value: genre)
                    }
                    try self.mpd.search_commit(connection)
                    
                    // Get pairs instead of looking by tag name, to ensure we also get the sort values if present.
                    var title = ""
                    var sortTitle = ""
                    while let result = self.mpd.recv_pair(connection) {
                        let tagName = result.0
                        let value = result.1
                        let tag = self.mpd.tag_name_parse(tagName)
                        
                        if [MPD_TAG_ARTIST, MPD_TAG_ALBUM_ARTIST, MPD_TAG_PERFORMER, MPD_TAG_COMPOSER].contains(tag) {
                            title = value
                            if title != "" {
                                artists.append(Artist(id: title, type: type, source: .Local, name: title, sortName: sortTitle))
                            }
                        }
                        else if [MPD_TAG_ARTIST_SORT, MPD_TAG_ALBUM_ARTIST_SORT].contains(tag) {
                            sortTitle = value
                        }
                    }
                    if title != "" {
                        artists.append(Artist(id: title, type: type, source: .Local, name: title, sortName: sortTitle))
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
                    
                    return Observable.empty()
                }
            })
            .observeOn(MainScheduler.instance)
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
    public func artistBrowseViewModel(_ genre: String, type: ArtistType) -> ArtistBrowseViewModel {
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
            .observeOn(scheduler)
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
            .observeOn(MainScheduler.instance)
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
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observeOn(scheduler)
            .flatMap({ (mpdConnection) -> Observable<[Song]> in
                guard let connection = mpdConnection?.connection else { return Observable.just([]) }

                let songs = self.songsForPlaylist(connection: connection, playlist: playlist.id)
                
                return Observable.just(songs)
            })
            .observeOn(MainScheduler.instance)
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
                if let song = MPDHelper.songFromMpdSong(mpd: mpd, connectionProperties: connectionProperties, mpdSong: mpdSong) {
                    songs.append(song)
                }
                self.mpd.song_free(mpdSong)
                mpdSong = mpd.recv_song(connection)
            }
            
            _ = self.mpd.response_finish(connection)
        }
        
        return songs
    }
    
    /// Delete a playlist
    ///
    /// - Parameter playlist: the playlist to delete
    func deletePlaylist(_ playlist: Playlist) {
        _ = MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observeOn(scheduler)
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
            .observeOn(scheduler)
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
            .observeOn(scheduler)
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
                    
                    return Observable.empty()
                }
            })
            .observeOn(MainScheduler.instance)
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
            .observeOn(scheduler)
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
            .observeOn(MainScheduler.instance)
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
            .observeOn(scheduler)
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
    
    /// Preprocess a CoverURI. This allows additional processing of base URI data.
    ///
    /// - Parameter coverURI: the CoverURI to pre-process
    /// - Returns: the processed cover URI
    public func preprocessCoverURI(_ coverURI: CoverURI) -> Observable<CoverURI> {
        let mpd = self.mpd
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observeOn(scheduler)
            .flatMap({ [weak self] (mpdConnection) -> Observable<CoverURI> in
                guard let connection = mpdConnection?.connection else { return Observable.just(coverURI) }

                guard let weakSelf = self else {
                    return Observable.just(coverURI)
                }

                let updatedCoverURI = weakSelf.completeCoverURI(connection, coverURI)
                return Observable.just(updatedCoverURI)
            })
    }
    
    func updateDB() {
        _ = MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observeOn(scheduler)
            .subscribe(onNext: { (mpdConnection) in
                guard let connection = mpdConnection?.connection else { return }

                _ = self.mpd.run_update(connection, path: nil)
            })
    }
    
    func databaseStatus() -> Observable<String> {
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observeOn(scheduler)
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
            .observeOn(MainScheduler.instance)
    }
    
    /// Create a diagnostics string that can help troubleshooting data issues
    ///
    /// - Parameter album: an album for which to get diagnostics
    /// - Returns: an observable String containing the diagnostics data
    public func diagnostics(album: Album) -> Observable<String> {
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
            .observeOn(scheduler)
            .flatMapFirst({ (mpdConnection) -> Observable<String> in
                guard let connection = mpdConnection?.connection else { return Observable.just("") }

                var diagnostics = ""
                
                diagnostics += "player type: \(self.connectionProperties[MPDConnectionProperties.MPDType.rawValue] ?? "Type unknown")\n"
                diagnostics += "mpd version: \(self.connectionProperties[MPDConnectionProperties.version.rawValue] ?? "Version unknown")\n"
                diagnostics += "\nsearch MPD_TAG_ALBUM_ARTIST, album.title = \(album.title)\n"
                try self.mpd.search_db_tags(connection, tagType: MPD_TAG_ALBUM_ARTIST)
                try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_ALBUM, value: album.title)
                try self.mpd.search_commit(connection)
                while let result = self.mpd.recv_pair(connection) {
                    diagnostics += "tag='\(result.0)', value='\(result.1)'\n"
                }
                _ = self.mpd.response_finish(connection)

                diagnostics += "\nsearch MPD_TAG_ARTIST, album.title = \(album.title)\n"
                try self.mpd.search_db_tags(connection, tagType: MPD_TAG_ARTIST)
                try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_ALBUM, value: album.title)
                try self.mpd.search_commit(connection)
                while let result = self.mpd.recv_pair(connection) {
                    diagnostics += "tag='\(result.0)', value='\(result.1)'\n"
                }
                _ = self.mpd.response_finish(connection)

                diagnostics += "\nsearch MPD_TAG_COMPOSER, album.title = \(album.title)\n"
                try self.mpd.search_db_tags(connection, tagType: MPD_TAG_COMPOSER)
                try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_ALBUM, value: album.title)
                try self.mpd.search_commit(connection)
                while let result = self.mpd.recv_pair(connection) {
                    diagnostics += "tag='\(result.0)', value='\(result.1)'\n"
                }
                _ = self.mpd.response_finish(connection)
                
                diagnostics += "\nsearch MPD_TAG_PERFORMER, album.title = \(album.title)\n"
                try self.mpd.search_db_tags(connection, tagType: MPD_TAG_PERFORMER)
                try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_ALBUM, value: album.title)
                try self.mpd.search_commit(connection)
                while let result = self.mpd.recv_pair(connection) {
                    diagnostics += "tag='\(result.0)', value='\(result.1)'\n"
                }
                _ = self.mpd.response_finish(connection)
                
                diagnostics += "\nsearch MPD_TAG_TITLE, album.title = \(album.title),\n"
                try self.mpd.search_db_tags(connection, tagType: MPD_TAG_TITLE)
                try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_ALBUM, value: album.title)
                try self.mpd.search_commit(connection)
                while let result = self.mpd.recv_pair(connection) {
                    diagnostics += "tag='\(result.0)', value='\(result.1)'\n"
                }
                _ = self.mpd.response_finish(connection)
                
                diagnostics += "\nsearch MPD_TAG_TITLE, album.title = \(album.title), album.artist = \(album.artist)\n"
                try self.mpd.search_db_tags(connection, tagType: MPD_TAG_TITLE)
                try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_ALBUM, value: album.title)
                try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_ARTIST, value: album.artist)
                try self.mpd.search_commit(connection)
                while let result = self.mpd.recv_pair(connection) {
                    diagnostics += "tag='\(result.0)', value='\(result.1)'\n"
                }
                _ = self.mpd.response_finish(connection)
                
                diagnostics += "\nsearch MPD_TAG_TITLE, album.title = \(album.title), album.albumartist = \(album.artist)\n"
                try self.mpd.search_db_tags(connection, tagType: MPD_TAG_TITLE)
                try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_ALBUM, value: album.title)
                try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_ALBUM_ARTIST, value: album.artist)
                try self.mpd.search_commit(connection)
                while let result = self.mpd.recv_pair(connection) {
                    diagnostics += "tag='\(result.0)', value='\(result.1)'\n"
                }
                _ = self.mpd.response_finish(connection)
                
                diagnostics += "\nsearch songs, album.title = \(album.title), album.artist = \(album.artist)\n"
                let artist = Artist(id: album.artist, type: .artist, source: .Local, name: album.artist)
                let songs = self.songsForArtistAndOrAlbum(connection: connection, artist: artist, album: album.title)
                for song in songs {
                    diagnostics += "file='\(song.id)'\n"
                    diagnostics += "title='\(song.title)', artist='\(song.artist)', albumartist='\(song.albumartist)', album='\(song.album)', year='\(song.year)', "
                    diagnostics += "sortartist='\(song.sortArtist)', sortalbum='\(song.sortAlbum)', sortalbumartist='\(song.sortAlbumArtist)', performer='\(song.performer)', composer='\(song.composer)'\n"
                }

                return Observable.just(diagnostics)
            })
            .observeOn(MainScheduler.instance)
    }
}
