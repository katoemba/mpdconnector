//
//  MPDHelper.swift
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
import RxSwift
import libmpdclient
import ConnectorProtocol

public class MPDHelper {
    /// Connect to a MPD Player
    ///
    /// - Parameters:
    ///   - mpd: the MPDProtocol object to run commands on
    ///   - host: Host ip-address to connect to.
    ///   - port: Port to connect to.
    ///   - password: Password to use after connecting.
    ///   - timeout: The timeout value for run any commands.
    /// - Returns: A mpd_connection object, or nil if any kind of error was detected.
    public static func connect(mpd: MPDProtocol, host: String, port: Int, password: String, timeout: Int = 5000) -> OpaquePointer? {
        if Thread.current.isMainThread {
            print("Warning: connecting to MPD on the main thread could cause blocking")
        }
        
        guard let connection = mpd.connection_new(host, UInt32(port), UInt32(timeout)) else {
            return nil
        }
        
        guard mpd.connection_get_error(connection) == MPD_ERROR_SUCCESS else {
            mpd.connection_free(connection)
            return nil
        }
        
        if password != "" {
            guard mpd.run_password(connection, password: password) == true,
                mpd.connection_get_error(connection) == MPD_ERROR_SUCCESS else {
                    mpd.connection_free(connection)
                    return nil
            }
        }
        
        return connection
    }
    
    /// Connect to a MPD Player using a connectionProperties dictionary
    ///
    /// - Parameters:
    ///   - mpd: the MPDProtocol object to run commands on
    ///   - connectionProperties: dictionary of connection properties (host, port, password)
    ///   - timeout: The timeout value for run any commands.
    /// - Returns: A mpd_connection object, or nil if any kind of error was detected.
    public static func connect(mpd: MPDProtocol, connectionProperties: [String: Any], timeout: Int = 5000) -> OpaquePointer? {
        return connect(mpd: mpd,
                       host: connectionProperties[ConnectionProperties.Host.rawValue] as! String,
                       port: connectionProperties[ConnectionProperties.Port.rawValue] as! Int,
                       password: connectionProperties[ConnectionProperties.Password.rawValue] as! String,
                       timeout: timeout)
    }
    
    /// Reactive connection function
    ///
    /// - Parameters:
    ///   - mpd: the MPDProtocol object to run commands on
    ///   - host: Host ip-address to connect to.
    ///   - port: Port to connect to.
    ///   - password: Password to use after connecting, default = "".
    ///   - timeout: The timeout value for run any commands, default = 3000ms.
    /// - Returns: An observable for a new connection. Will raise an error if connecting is not successful.
    public static func connectToMPD(mpd: MPDProtocol, host: String, port: Int, password: String = "", timeout: Int = 5000) -> Observable<OpaquePointer> {
        return Observable<OpaquePointer>.create { observer in
            if let connection = connect(mpd: mpd, host: host, port: port, password: password, timeout: timeout) {
                observer.onNext(connection)
                observer.onCompleted()
            }
            else {
                observer.onError(ConnectionError.internalError)
            }
            
            return Disposables.create()
        }
    }
    
    /// Reactive connection function using a connectionProperties dictionary
    ///
    /// - Parameters:
    ///   - mpd: the MPDProtocol object to run commands on
    ///   - connectionProperties: dictionary of connection properties (host, port, password)
    ///   - timeout: The timeout value for run any commands, default = 3000ms.
    /// - Returns: An observable for a new connection. Will raise an error if connecting is not successful.
    public static func connectToMPD(mpd: MPDProtocol, connectionProperties: [String: Any], timeout: Int = 5000) -> Observable<OpaquePointer> {
        return connectToMPD(mpd: mpd,
                            host: connectionProperties[ConnectionProperties.Host.rawValue] as! String,
                            port: connectionProperties[ConnectionProperties.Port.rawValue] as! Int,
                            password: connectionProperties[ConnectionProperties.Password.rawValue] as! String,
                            timeout: timeout)
    }
    
    /// Fill a generic Song object from an mpdSong
    ///
    /// - Parameters:
    ///   - mpd: MPDProtocol object
    ///   - mpdSong: pointer to a mpdSong data structure
    /// - Returns: the filled Song object
    public static func songFromMpdSong(mpd: MPDProtocol, connectionProperties: [String: Any], mpdSong: OpaquePointer!) -> Song? {
        guard mpdSong != nil else  {
            return nil
        }
        
        var song = Song()
        
        song.id = mpd.song_get_uri(mpdSong)
        if song.id.starts(with: "spotify:") {
            song.source = .Spotify
        }
        else if song.id.starts(with: "tunein:") {
            song.source = .TuneIn
        }
        else if song.id.starts(with: "podcast+") {
            song.source = .Podcast
        }
        else {
            song.source = .Local
        }
        song.title = mpd.song_get_tag(mpdSong, MPD_TAG_TITLE, 0)
        song.album = mpd.song_get_tag(mpdSong, MPD_TAG_ALBUM, 0)
        song.artist = mpd.song_get_tag(mpdSong, MPD_TAG_ARTIST, 0)
        song.albumartist = mpd.song_get_tag(mpdSong, MPD_TAG_ALBUM_ARTIST, 0)
        song.composer = mpd.song_get_tag(mpdSong, MPD_TAG_COMPOSER, 0)
        song.genre = mpd.song_get_tag(mpdSong, MPD_TAG_GENRE, 0)
        song.length = Int(mpd.song_get_duration(mpdSong))
        song.name = mpd.song_get_tag(mpdSong, MPD_TAG_NAME, 0)
        song.date = mpd.song_get_tag(mpdSong, MPD_TAG_DATE, 0)
        song.year = Int(String(song.date.prefix(4))) ?? 0
        song.performer = mpd.song_get_tag(mpdSong, MPD_TAG_PERFORMER, 0)
        song.comment = mpd.song_get_tag(mpdSong, MPD_TAG_COMMENT, 0)
        song.disc = mpd.song_get_tag(mpdSong, MPD_TAG_DISC, 0)
        song.musicbrainzArtistId = mpd.song_get_tag(mpdSong, MPD_TAG_MUSICBRAINZ_ARTISTID, 0)
        song.musicbrainzAlbumId = mpd.song_get_tag(mpdSong, MPD_TAG_MUSICBRAINZ_ALBUMID, 0)
        song.musicbrainzAlbumArtistId = mpd.song_get_tag(mpdSong, MPD_TAG_MUSICBRAINZ_ALBUMARTISTID, 0)
        song.musicbrainzTrackId = mpd.song_get_tag(mpdSong, MPD_TAG_MUSICBRAINZ_TRACKID, 0)
        song.musicbrainzReleaseId = mpd.song_get_tag(mpdSong, MPD_TAG_MUSICBRAINZ_RELEASETRACKID, 0)
        song.originalDate = mpd.song_get_tag(mpdSong, MPD_TAG_ORIGINAL_DATE, 0)
        song.sortArtist = mpd.song_get_tag(mpdSong, MPD_TAG_ARTIST_SORT, 0)
        song.sortAlbumArtist = mpd.song_get_tag(mpdSong, MPD_TAG_ALBUM_ARTIST_SORT, 0)
        song.sortAlbum = mpd.song_get_tag(mpdSong, MPD_TAG_ALBUM_SORT, 0)
        song.lastModified = mpd.song_get_last_modified(mpdSong)
        
        // Get a sensible coverURI
        let sections = song.id.split(separator: ":")
        guard let path = sections.last else {
            return song
        }
        let pathSections = path.split(separator: "/")
        
        var newPath = ""
        for index in 0..<(pathSections.count - 1) {
            newPath.append(contentsOf: pathSections[index])
            newPath.append(contentsOf: "/")
        }
        
        let coverURI = newPath.removingPercentEncoding?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        let host = connectionProperties[ConnectionProperties.Host.rawValue] as! String
        let prefix = connectionProperties[MPDConnectionProperties.coverPrefix.rawValue] as! String
        let postfix = connectionProperties[MPDConnectionProperties.coverPostfix.rawValue] as! String
        let alternativePostfix = connectionProperties[MPDConnectionProperties.alternativeCoverPostfix.rawValue] as! String

        if postfix == "" && alternativePostfix == "" {
            song.coverURI = CoverURI.fullPathURI("http://\(host)/\(prefix)\(coverURI)")
        }
        else if alternativePostfix == "" {
            song.coverURI = CoverURI.filenameOptionsURI("http://\(host)/\(prefix)\(coverURI)", [postfix])
        }
        else {
            song.coverURI = CoverURI.filenameOptionsURI("http://\(host)/\(prefix)\(coverURI)", [postfix, alternativePostfix])
        }

        return song
    }
    
    /// Fill a generic Playlist object from an mpdPlaylist
    ///
    /// - Parameters:
    ///   - mpd: MPDProtocol object
    ///   - mpdPlaylist: pointer to a mpdPlaylist data structure
    /// - Returns: the filled Playlist object
    public static func playlistFromMpdPlaylist(mpd: MPDProtocol, mpdPlaylist: OpaquePointer!) -> Playlist? {
        guard mpdPlaylist != nil else  {
            return nil
        }
        
        var playlist = Playlist()
        
        playlist.id = mpd.playlist_get_path(mpdPlaylist)
        if playlist.id.starts(with: "spotify:") {
            playlist.source = .Spotify
        }
        else {
            playlist.source = .Local
        }
        
        let elements = playlist.id.split(separator: "/")
        if let name = elements.last {
            playlist.name = String(name)
        }
        else {
            playlist.name = "Unknown"
        }
        playlist.lastModified = mpd.playlist_get_last_modified(mpdPlaylist)

        return playlist
    }
}
