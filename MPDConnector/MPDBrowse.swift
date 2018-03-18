//
//  MPDBrowse.swift
//  MPDConnector_iOS
//
//  Created by Berrie Kremers on 30-09-17.
//  Copyright © 2017 Katoemba Software. All rights reserved.
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
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties)
            .observeOn(scheduler)
            .flatMap({ (connection) -> Observable<SearchResult> in
                let artistSearchResult = self.searchType(search, connection: connection, tagType: MPD_TAG_ARTIST, filter: filter)
                let albumSearchResult = self.searchType(search, connection: connection, tagType: MPD_TAG_ALBUM, filter: filter)
                let songSearchResult = self.searchType(search, connection: connection, tagType: MPD_TAG_TITLE, filter: filter)
                
                self.mpd.connection_free(connection)
                
                var searchResult = SearchResult()
                searchResult.artists = (artistSearchResult.artists + albumSearchResult.artists + songSearchResult.artists).orderedSet
                searchResult.albums = (albumSearchResult.albums + artistSearchResult.albums + songSearchResult.albums).orderedSet
                searchResult.songs = (songSearchResult.songs + artistSearchResult.songs + albumSearchResult.songs).orderedSet
                
                return Observable.just(searchResult)
            })
    }
    
    private func searchType(_ search: String, connection: OpaquePointer, tagType: mpd_tag_type, filter: [SourceType] = []) -> SearchResult {
        var songs = [Song]()
        var albums = [Album]()
        var artists = [Artist]()
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
                                var album = Album(id: "\(song.artist):\(song.album)", source: .Local, location: "", title: song.album, artist: song.artist, year: song.year, genre: song.genre, length: 0)
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

        return searchResult
    }
    
    /// Return an array of songs for an artist and optional album. This will search through both artist and albumartist.
    ///
    /// - Parameters:
    ///   - connection: an active mpd connection
    ///   - artist: the artist name to search for
    ///   - album: optionally an album title to search for
    /// - Returns: an array of Song objects
    private func songsForArtistAndOrAlbum(connection: OpaquePointer, artist: String, album: String? = nil) -> [Song] {
        var songs = [Song]()
        var songIDs = [String: Int]()
        for tagType in [MPD_TAG_ARTIST, MPD_TAG_ALBUM_ARTIST] {
            do {
                try self.mpd.search_db_songs(connection, exact: true)
                try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: tagType, value: artist)
                if let album = album {
                    try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_ALBUM, value: album)
                }
                try self.mpd.search_commit(connection)
                
                var mpdSong = self.mpd.recv_song(connection)
                while mpdSong != nil {
                    if let song = MPDHelper.songFromMpdSong(mpd: self.mpd, connectionProperties: self.connectionProperties, mpdSong: mpdSong) {
                        if songIDs[song.id] == nil {
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
        
        return songs
    }
    
    /// Asynchronously get all songs on an album
    ///
    /// - Parameter album: the album to get the songs for
    /// - Returns: an observable array of Song objects
    public func songsOnAlbum(_ album: Album) -> Observable<[Song]> {
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties)
            .observeOn(scheduler)
            .flatMap({ (connection) -> Observable<[Song]> in
                let songs = self.songsForArtistAndOrAlbum(connection: connection, artist: album.artist, album: album.title)
                
                // Cleanup
                self.mpd.connection_free(connection)
                
                return Observable.just(songs)
            })
    }

    /// Asynchronously get all songs for an artist
    ///
    /// - Parameters:
    ///   - artist: the artist to get the songs for
    /// - Returns: an observable array of Song objects
    public func songsByArtist(_ artist: Artist) -> Observable<[Song]> {
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties)
            .observeOn(scheduler)
            .flatMap({ (connection) -> Observable<[Song]> in
                let songs = self.songsForArtistAndOrAlbum(connection: connection, artist: artist.name)
                
                // Cleanup
                self.mpd.connection_free(connection)
                
                return Observable.just(songs)
            })
    }
    
    private func albumFromSong(_ song: Song) -> Album {
        let artist = song.albumartist != "" ? song.albumartist : song.artist
        var album = Album(id: "\(song.artist):\(song.album)", source: .Local, location: "", title: song.album, artist: artist, year: song.year, genre: song.genre, length: 0)
        album.coverURI = song.coverURI
        album.lastModified = song.lastModified
    
        return album
    }
    
    private func albumsFromSongs(_ songs: [Song]) -> [Album] {
        var albums = [Album]()
        for song in songs {
            let album = albumFromSong(song)
            if albums.contains(album) == false {
                albums.append(album)
            }
        }
        
        return albums
    }
    
    public func albumsByArtist(_ artist: Artist) -> Observable<[Album]> {
        return songsByArtist(artist)
            .flatMap({ [weak self] (songs) -> Observable<[Album]> in
                guard let weakself = self else { return Observable.empty() }
                
                return Observable.just(weakself.albumsFromSongs(songs))
            })
    }
    
    func fetchRecentAlbums(numberOfDays: Int = 0) -> Observable<[Album]> {
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties)
            .observeOn(scheduler)
            .flatMap({ (connection) -> Observable<[Album]> in
                do {
                    var albums = [Album]()
                    
                    try self.mpd.search_db_songs(connection, exact: true)
                    try self.mpd.search_add_modified_since_constraint(connection, oper: MPD_OPERATOR_DEFAULT, since:Date(timeIntervalSinceNow: TimeInterval(-1 * (numberOfDays > 0 ? numberOfDays : 180) * 24 * 60 * 60)))
                    try self.mpd.search_commit(connection)
                    
                    var albumIDs = [String: Int]()
                    while let mpdSong = self.mpd.recv_song(connection) {
                        if let song = MPDHelper.songFromMpdSong(mpd: self.mpd, connectionProperties: self.connectionProperties, mpdSong: mpdSong) {
                            let albumartist = (song.albumartist == "") ? song.artist : song.albumartist
                            let albumID = "\(albumartist):\(song.album)"
                            if albumIDs[albumID] == nil {
                                albumIDs[albumID] = 1
                                albums.append(self.albumFromSong(song))
                            }
                        }

                        self.mpd.song_free(mpdSong)
                    }
                    _ = self.mpd.response_finish(connection)
                    
                    // Cleanup
                    self.mpd.connection_free(connection)
                    
                    return Observable.just(albums.sorted(by: { (lhs, rhs) -> Bool in
                        return lhs.lastModified > rhs.lastModified
                    }))
                }
                catch {
                    print(self.mpd.connection_get_error_message(connection))
                    _ = self.mpd.connection_clear_error(connection)
                    self.mpd.connection_free(connection)
                    
                    return Observable.empty()
                }
            })
    }

    func fetchAlbums(genre: String?, sort: SortType) -> Observable<[Album]> {
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties)
            .observeOn(scheduler)
            .flatMap({ (connection) -> Observable<[Album]> in
                do {
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
                                let album = Album(id: albumID, source: .Local, location: "", title: title, artist: albumArtist, year: year, genre: "", length: 0)
                                albums.append(album)
                            }
                        }
                    }
                    _ = self.mpd.response_finish(connection)
                    
                    // Cleanup
                    self.mpd.connection_free(connection)
                    
                    return Observable.just(albums.sorted(by: { (lhs, rhs) -> Bool in
                        if sort == .year || sort == .yearReverse {
                            if lhs.year < rhs.year {
                                return sort == .year
                            }
                            else if lhs.year > rhs.year {
                                return sort == .yearReverse
                            }
                        }

                        let artistCompare = lhs.artist.caseInsensitiveCompare(rhs.artist)
                        if artistCompare == .orderedAscending {
                            return true
                        }
                        if artistCompare == .orderedDescending {
                            return false
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
                    self.mpd.connection_free(connection)
                    
                    return Observable.empty()
                }
            })
    }
    
    public func completeAlbums(_ albums: [Album]) -> Observable<[Album]> {
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties)
            .observeOn(scheduler)
            .flatMap({ (connection) -> Observable<[Album]> in
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
                        completeAlbums.append(self.albumFromSong(song!))
                    }
                    else {
                        completeAlbums.append(album)
                    }
                }
                
                self.mpd.connection_free(connection)
                return Observable.just(completeAlbums)
            })
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

    public func fetchArtists(genre: String?) -> Observable<[Artist]> {
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties)
            .observeOn(scheduler)
            .flatMap({ (connection) -> Observable<[Artist]> in
                do {
                    var artists = [Artist]()
                    
                    try self.mpd.search_db_tags(connection, tagType: MPD_TAG_ARTIST)
                    if let genre = genre, genre != "" {
                        try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_GENRE, value: genre)
                    }
                    try self.mpd.search_commit(connection)
                    
                    while let result = self.mpd.recv_pair_tag(connection, tagType: MPD_TAG_ARTIST) {
                        let title = result.1
                        if title != "" {
                            let artist = Artist(id: title, source: .Local, name: title)
                            artists.append(artist)
                        }
                    }
                    _ = self.mpd.response_finish(connection)
                    
                    // Cleanup
                    self.mpd.connection_free(connection)
                    
                    return Observable.just(artists.sorted(by: { (lhs, rhs) -> Bool in
                        return lhs.name.caseInsensitiveCompare(rhs.name) == .orderedAscending
                    }))
                }
                catch {
                    print(self.mpd.connection_get_error_message(connection))
                    _ = self.mpd.connection_clear_error(connection)
                    self.mpd.connection_free(connection)
                    
                    return Observable.empty()
                }
            })
    }
    
    /// Return a view model for a list of artists, which can return artists in batches.
    ///
    /// - Returns: an ArtistBrowseViewModel instance
    public func artistBrowseViewModel() -> ArtistBrowseViewModel {
        return MPDArtistBrowseViewModel(browse: self)
    }
    
    /// Return a view model for a list of artists filtered by genre, which can return artist in batches.
    ///
    /// - Parameter genre: genre to filter on
    /// - Returns: an ArtistBrowseViewModel instance
    public func artistBrowseViewModel(_ genre: String) -> ArtistBrowseViewModel {
        return MPDArtistBrowseViewModel(browse: self, filters: [.genre(genre)])
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
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties)
            .observeOn(scheduler)
            .flatMap({ (connection) -> Observable<[Playlist]> in
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
                
                self.mpd.connection_free(connection)

                return Observable.just(playlists.sorted(by: { (lhs, rhs) -> Bool in
                    return lhs.name.caseInsensitiveCompare(rhs.name) == .orderedAscending
                }))
            })
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
        return MPDSongBrowseViewModel(browse: self, filters: [.playlist(playlist)])
    }
    
    /// Asynchronously get all songs in a playlist
    ///
    /// - Parameter playlist: the playlst to get the songs for
    /// - Returns: an observable array of Song objects
    public func songsInPlaylist(_ playlist: Playlist) -> Observable<[Song]> {
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties)
            .observeOn(scheduler)
            .flatMap({ (connection) -> Observable<[Song]> in
                let songs = self.songsForPlaylist(connection: connection, playlist: playlist.id)
                
                // Cleanup
                self.mpd.connection_free(connection)
                
                return Observable.just(songs)
            })
    }
    
    /// Return a view model for a list of songs in an album, which can return songs in batches.
    ///
    /// - Parameter album: album to filter on
    /// - Returns: a SongBrowseViewModel instance
    public func songBrowseViewModel(_ album: Album) -> SongBrowseViewModel {
        return MPDSongBrowseViewModel(browse: self, filters: [.album(album)])
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
        _ = MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties)
            .observeOn(scheduler)
            .subscribe(onNext: { (connection) in
                _ = self.mpd.run_rm(connection, name: playlist.id)
                self.mpd.connection_free(connection)
            })
    }
    
    /// Rename a playlist
    ///
    /// - Parameters:
    ///   - playlist: the playlist to rename
    ///   - newName: the new name to give to the playlist
    func renamePlaylist(_ playlist: Playlist, newName: String) {
        _ = MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties)
            .observeOn(scheduler)
            .subscribe(onNext: { (connection) in
                _ = self.mpd.run_rename(connection, from: playlist.id, to: newName)
                self.mpd.connection_free(connection)
            })
    }

    /*
    private func getAllAlbumNames(artist: String = "", genre: String = "") -> [String] {
        var albumNames = [String]()
        do {
            try mpd.search_db_tags(connection, tagType: MPD_TAG_ALBUM)
            if artist != "" {
                try mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_ARTIST, value: artist)
            }
            else if genre != "" {
                try mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_GENRE, value: genre)
            }
            try mpd.search_commit(connection)
            
            while let result = mpd.recv_pair_tag(connection, tagType: MPD_TAG_ALBUM) {
                if result.1 != "" {
                    albumNames.append(result.1)
                }
            }
        }
        catch {
            print(mpd.connection_get_error_message(connection))
            _ = mpd.connection_clear_error(connection)
        }
        
        // Cleanup
        _ = mpd.response_finish(connection)
        
        return albumNames.sorted
            { $0.caseInsensitiveCompare($1) == .orderedAscending }
    }
    
    private func albumNames(artist: String = "", genre: String = "") -> Observable<String> {
        return Observable.create { observer in
            do {
                try self.mpd.search_db_tags(self.connection, tagType: MPD_TAG_ALBUM)
                if artist != "" {
                    try self.mpd.search_add_tag_constraint(self.connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_ARTIST, value: artist)
                }
                else if genre != "" {
                    try self.mpd.search_add_tag_constraint(self.connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_GENRE, value: genre)
                }
                try self.mpd.search_commit(self.connection)
                
                while let result = self.mpd.recv_pair_tag(self.connection, tagType: MPD_TAG_ALBUM) {
                    observer.on(.next(result.1))
                }
            }
            catch  {
                print(self.mpd.connection_get_error_message(self.connection))
                _ = self.mpd.connection_clear_error(self.connection)
                observer.on(.error(MPDError.commandFailed))
            }
            
            observer.on(.completed)

            return Disposables.create()
        }
     }

    private func getAllArtistNames(genre: String = "") -> [String] {
        var artistNames = [String]()
        do {
            try mpd.search_db_tags(connection, tagType: MPD_TAG_ARTIST)
            if genre != "" {
                try mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_GENRE, value: genre)
            }
            try mpd.search_commit(connection)
            
            while let result = mpd.recv_pair_tag(connection, tagType: MPD_TAG_ALBUM) {
                artistNames.append(result.1)
            }
        }
        catch {
            print(mpd.connection_get_error_message(connection))
            _ = mpd.connection_clear_error(connection)
        }
        
        // Cleanup
        _ = mpd.response_finish(connection)
        
        return artistNames.sorted
            { $0.caseInsensitiveCompare($1) == .orderedAscending }
    }
     */
}
