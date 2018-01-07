//
//  MPDBrowse.swift
//  MPDConnector_iOS
//
//  Created by Berrie Kremers on 30-09-17.
//  Copyright © 2017 Kaotemba Software. All rights reserved.
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

    public init(mpd: MPDProtocol? = nil,
                connectionProperties: [String: Any],
                identification: String = "NoID") {
        self.mpd = mpd ?? MPDWrapper()
        self.identification = identification
        self.connectionProperties = connectionProperties

        HelpMePlease.allocUp(name: "MPDBrowse")
    }
    
    /// Cleanup connection object
    deinit {
        HelpMePlease.allocDown(name: "MPDBrowse")
    }

    public func search(_ search: String, limit: Int = 20, filter: [SourceType] = []) -> Observable<SearchResult> {
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties)
            .observeOn(ConcurrentDispatchQueueScheduler(qos: .background))
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
            
            while let song = MPDHelper.songFromMpdSong(mpd: mpd, mpdSong: mpd.get_song(connection)) {
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
    
    public func songsOnAlbum(_ album: Album) -> Observable<[Song]> {
        return MPDHelper.connectToMPD(mpd: mpd, connectionProperties: connectionProperties)
            .observeOn(ConcurrentDispatchQueueScheduler(qos: .background))
            .flatMap({ (connection) -> Observable<[Song]> in
                var songs = [Song]()
                do {
                    try self.mpd.search_db_songs(connection, exact: true)
                    try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_ALBUM, value: album.title)
                    try self.mpd.search_add_tag_constraint(connection, oper: MPD_OPERATOR_DEFAULT, tagType: MPD_TAG_ARTIST, value: album.artist)
                    try self.mpd.search_commit(connection)
                    
                    while let song = MPDHelper.songFromMpdSong(mpd: self.mpd, mpdSong: self.mpd.get_song(connection)) {
                        songs.append(song)
                    }
                }
                catch {
                    print(self.mpd.connection_get_error_message(connection))
                    _ = self.mpd.connection_clear_error(connection)
                }
                
                // Cleanup
                _ = self.mpd.response_finish(connection)
                self.mpd.connection_free(connection)
                
                return Observable.just(songs)
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
