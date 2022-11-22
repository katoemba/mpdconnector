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
import RxSwiftExt

class Weak<T: MPDConnection> {
  weak var value : T?
  init (value: T) {
    self.value = value
  }
}

public class MPDConnection {
    public enum Priority: String {
        case low = "Low"
        case high = "High"
    }

    private static let maxConcurrentConnections = 4
    private static var highPrioConnectionCount = 0
    private static var lowPrioConnectionCount = 0
    private static let countSemaphoreMutex = DispatchSemaphore(value: 1)
    private static let playerSemaphoreMutex = DispatchSemaphore(value: 1)
    private static var connections = [UUID: Weak<MPDConnection>]()
    
    private var mpd: MPDProtocol
    private var _connection: OpaquePointer?
    public var connection: OpaquePointer? {
        get {
            return _connection
        }
    }
    
    private var uniqueId = UUID()
    private var host: String
    private var port: Int
    private var prio: Priority
    
    init(mpd: MPDProtocol, host: String, port: Int, timeout: Int, prio: Priority = .high) {
        self.mpd = mpd
        self.host = host
        self.port = port
        self.prio = prio
        _connection = mpd.connection_new(host, UInt32(port), UInt32(timeout))
        //MPDConnection.connected(prio: prio)
        
        Self.playerSemaphoreMutex.wait()
        Self.connections[uniqueId] = Weak<MPDConnection>(value: self)
        Self.playerSemaphoreMutex.signal()
    }
    
    deinit {
        Self.playerSemaphoreMutex.wait()
        Self.connections.removeValue(forKey: uniqueId)
        Self.playerSemaphoreMutex.signal()

        disconnect()
    }
    
    public static func cleanup() {
        for weakConnection in connections.values {
            if let connection = weakConnection.value {
                connection.disconnect()
            }
        }
        
        connections.removeAll()
    }
    
    func disconnect() {
        Self.playerSemaphoreMutex.wait()
        if let connection = _connection {
            mpd.connection_free(connection)
            _connection = nil
            //MPDConnection.released(prio: prio)
        }
        Self.playerSemaphoreMutex.signal()
    }
    
    private static func connected(prio: Priority) {
        countSemaphoreMutex.wait()
        switch prio {
        case .high:
            highPrioConnectionCount += 1
            print("Increment \(prio.rawValue) connection count to \(highPrioConnectionCount)")
        case .low:
            lowPrioConnectionCount += 1
            print("Increment \(prio.rawValue) connection count to \(lowPrioConnectionCount)")
        }
        countSemaphoreMutex.signal()
    }
    
    private static func released(prio: Priority) {
        countSemaphoreMutex.wait()
        switch prio {
        case .high:
            highPrioConnectionCount -= 1
            print("Decrement \(prio.rawValue) connection count to \(highPrioConnectionCount)")
        case .low:
            lowPrioConnectionCount -= 1
            print("Decrement \(prio.rawValue) connection count to \(lowPrioConnectionCount)")
        }
        countSemaphoreMutex.signal()
    }
}

public class MPDHelper {
    private enum ConnectError: Error {
        case error
        case permission
    }
    
    public static func hostToUse(_ connectionProperties: [String: Any]) -> String {
        var host = connectionProperties[ConnectionProperties.host.rawValue] as! String
        if (connectionProperties[MPDConnectionProperties.connectToIpAddress.rawValue] as? Bool) == true,
           let ipAddress = connectionProperties[MPDConnectionProperties.ipAddress.rawValue] as? String {
            host = ipAddress
        }
        return host
    }
    
    /// Connect to a MPD Player
    ///
    /// - Parameters:
    ///   - mpd: the MPDProtocol object to run commands on
    ///   - host: Host ip-address to connect to.
    ///   - port: Port to connect to.
    ///   - password: Password to use after connecting.
    ///   - timeout: The timeout value for run any commands.
    /// - Returns: A mpd_connection object, or nil if any kind of error was detected.
    public static func connect(mpd: MPDProtocol, host: String, port: Int, password: String, timeout: Int = 5000, prio: MPDConnection.Priority = .high) -> MPDConnection? {
        if Thread.current.isMainThread {
            print("Warning: connecting to MPD on the main thread could cause blocking")
        }
        
        let mpdConnection = MPDConnection(mpd: mpd, host: host, port: port, timeout: timeout, prio: prio)
        guard let connection = mpdConnection.connection else {
            return nil
        }
        
        guard mpd.connection_get_error(connection) == MPD_ERROR_SUCCESS else {
            print("Connection error: \(mpd.connection_get_error_message(connection))")
            if mpd.connection_get_error(connection) == MPD_ERROR_SERVER {
                print("Server error: \(mpd_connection_get_server_error(connection))")
            }
            return nil
        }
        
        if password != "" {
            guard mpd.run_password(connection, password: password) == true,
                mpd.connection_get_error(connection) == MPD_ERROR_SUCCESS else {
                    return nil
            }
        }
        
        return mpdConnection
    }
    
    /// Connect to a MPD Player using a connectionProperties dictionary
    ///
    /// - Parameters:
    ///   - mpd: the MPDProtocol object to run commands on
    ///   - connectionProperties: dictionary of connection properties (host, port, password)
    ///   - timeout: The timeout value for run any commands.
    /// - Returns: A mpd_connection object, or nil if any kind of error was detected.
    public static func connect(mpd: MPDProtocol, connectionProperties: [String: Any], timeout: Int = 5000, prio: MPDConnection.Priority = .high) -> MPDConnection? {
        return connect(mpd: mpd,
                       host: hostToUse(connectionProperties),
                       port: connectionProperties[ConnectionProperties.port.rawValue] as! Int,
                       password: connectionProperties[ConnectionProperties.password.rawValue] as! String,
                       timeout: timeout,
                       prio: prio)
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
    public static func connectToMPD(mpd: MPDProtocol, host: String, port: Int, password: String = "", scheduler: SchedulerType, timeout: Int = 5000, prio: MPDConnection.Priority = .high) -> Observable<MPDConnection?> {
        return Observable<MPDConnection?>.create { observer in
            if let mpdConnection = connect(mpd: mpd, host: host, port: port, password: password, timeout: timeout, prio: prio) {
                var allIsWell = true
                // Check if perhaps we need a password
                if password == "" {
                    let mpdStatus = mpd.run_status(mpdConnection.connection)
                    if  mpd.connection_get_error(mpdConnection.connection) == MPD_ERROR_SERVER,
                        mpd.connection_get_server_error(mpdConnection.connection) == MPD_SERVER_ERROR_PERMISSION {
                        print("Connection \(host):\(port) requires a password")
                        allIsWell = false
                    }
                    if mpdStatus != nil {
                        mpd.status_free(mpdStatus)
                    }
                }
                
                if allIsWell {
                    observer.onNext(mpdConnection)
                    observer.onCompleted()
                }
                else {
                    observer.onError(ConnectError.permission)
                }
            }
            else {
                print("Couldn't connect to MPD: \(ConnectionError.internalError).")
                observer.onError(ConnectError.error)
            }

            return Disposables.create()
        }
        .subscribe(on: scheduler)
        .retry(.exponentialDelayed(maxCount: 4, initial: 0.5, multiplier: 1.0), scheduler: scheduler)
        .catchAndReturn(nil)
        .asObservable()
    }
    
    /// Reactive connection function using a connectionProperties dictionary
    ///
    /// - Parameters:
    ///   - mpd: the MPDProtocol object to run commands on
    ///   - connectionProperties: dictionary of connection properties (host, port, password)
    ///   - timeout: The timeout value for run any commands, default = 3000ms.
    /// - Returns: An observable for a new connection. Will raise an error if connecting is not successful.
    public static func connectToMPD(mpd: MPDProtocol, connectionProperties: [String: Any], scheduler: SchedulerType, timeout: Int = 5000, prio: MPDConnection.Priority = .high) -> Observable<MPDConnection?> {
        return connectToMPD(mpd: mpd,
                            host: hostToUse(connectionProperties),
                            port: connectionProperties[ConnectionProperties.port.rawValue] as! Int,
                            password: connectionProperties[ConnectionProperties.password.rawValue] as! String,
                            scheduler: scheduler,
                            timeout: timeout,
                            prio: prio)
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
        // Some mpd versions (on Bryston) don't pick up the title correctly for wav files.
        // In such case, get it from the file path.
        if song.title == "", song.source == .Local {
            let components = song.id.components(separatedBy: "/")
            if components.count >= 1 {
                let filename = components[components.count - 1]
                let filecomponents = filename.components(separatedBy: ".")
                if filecomponents.count >= 1 {
                    song.title = filecomponents[0]
                }
            }
        }
        song.album = mpd.song_get_tag(mpdSong, MPD_TAG_ALBUM, 0)
        // Some mpd versions (on Bryston) don't pick up the album correctly for wav files.
        // In such case, get it from the file path.
        if song.album == "", song.source == .Local {
            let components = song.id.components(separatedBy: "/")
            if components.count >= 2 {
                song.album = components[components.count - 2]
            }
        }
        song.artist = mpd.song_get_tag(mpdSong, MPD_TAG_ARTIST, 0)
        // Some mpd versions (on Bryston) don't pick up the album correctly for wav files.
        // In such case, get it from the file path.
        if song.artist == "", song.source == .Local {
            let components = song.id.components(separatedBy: "/")
            if components.count >= 3 {
                song.artist = components[components.count - 3]
            }
        }
        song.albumartist = mpd.song_get_tag(mpdSong, MPD_TAG_ALBUM_ARTIST, 0)
        song.composer = mpd.song_get_tag(mpdSong, MPD_TAG_COMPOSER, 0)
        song.genre = [mpd.song_get_tag(mpdSong, MPD_TAG_GENRE, 0)]
        song.length = Int(mpd.song_get_duration(mpdSong))
        song.name = mpd.song_get_tag(mpdSong, MPD_TAG_NAME, 0)
        song.date = mpd.song_get_tag(mpdSong, MPD_TAG_DATE, 0)
        song.year = Int(String(song.date.prefix(4))) ?? 0
        song.performer = mpd.song_get_tag(mpdSong, MPD_TAG_PERFORMER, 0)
        song.comment = mpd.song_get_tag(mpdSong, MPD_TAG_COMMENT, 0)
        let playqueueId = Int(mpd.song_get_id(mpdSong))
        if playqueueId > 0 {
            song.playqueueId = "\(playqueueId)"
        }
        
        let trackComponents = mpd.song_get_tag(mpdSong, MPD_TAG_TRACK, 0).components(separatedBy: CharacterSet.decimalDigits.inverted)
        if trackComponents.count > 0 {
            song.track = Int(trackComponents.first!) ?? 0
        }
        else {
            let filenameComponents = song.id.components(separatedBy: CharacterSet.decimalDigits.inverted)
            if song.source == .Local, filenameComponents.count > 0 {
                song.track = Int(trackComponents.first!) ?? 0
            }
            else {
                song.track = 0
            }
        }

        let discComponents = mpd.song_get_tag(mpdSong, MPD_TAG_DISC, 0).components(separatedBy: CharacterSet.decimalDigits.inverted)
        if discComponents.count > 0 {
            song.disc = Int(discComponents.first!) ?? 0
        }
        else {
            song.disc = 0
        }

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
        if let audioFormat = mpd.song_get_audio_format(mpdSong) {
            if audioFormat.0 > 0 {
                song.quality.samplerate = "\(audioFormat.0/1000)kHz"
            }
            else {
                song.quality.samplerate = "-"
            }
            
            if audioFormat.1 == MPD_SAMPLE_FORMAT_FLOAT {
                song.quality.encoding = "FLOAT"
            }
            else if audioFormat.1 == MPD_SAMPLE_FORMAT_DSD {
                song.quality.encoding = "DSD"
            }
            else if audioFormat.1 > 0 {
                song.quality.encoding = "\(audioFormat.1)bit"
            }
            else {
                song.quality.encoding = "???"
            }
            
            song.quality.channels = audioFormat.2 == 1 ? "Mono" : "Stereo"
        }
        
        let components = song.id.components(separatedBy: "/")
        if components.count >= 1 {
            let filename = components[components.count - 1]
            let filecomponents = filename.components(separatedBy: ".")
            if filecomponents.count >= 2 {
                song.quality.filetype = filecomponents[filecomponents.count - 1]
            }
        }
        
        // Get a sensible coverURI
        guard song.source == .Local else { return song }
        
        let pathSections = song.id.split(separator: "/")
        var newPath = ""
        if pathSections.count > 0 {
            for index in 0..<(pathSections.count - 1) {
                newPath.append(contentsOf: pathSections[index])
                newPath.append(contentsOf: "/")
            }
        }
        
        let coverURI = newPath.removingPercentEncoding?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        var coverHost = connectionProperties[MPDConnectionProperties.alternativeCoverHost.rawValue] as? String ?? ""
        if coverHost == "" {
            coverHost = connectionProperties[ConnectionProperties.host.rawValue] as? String ?? ""
        }
        let coverHttpPort = connectionProperties[MPDConnectionProperties.coverHttpPort.rawValue] as? String ?? ""
        let portExtension = coverHttpPort == "" ? coverHttpPort : ":\(coverHttpPort)"
        let prefix = connectionProperties[MPDConnectionProperties.coverPrefix.rawValue] as? String ?? ""
        let postfix = connectionProperties[MPDConnectionProperties.coverPostfix.rawValue] as? String ?? ""
        let alternativePostfix = connectionProperties[MPDConnectionProperties.alternativeCoverPostfix.rawValue] as? String ?? ""

        if postfix == "" && alternativePostfix == "" {
            song.coverURI = CoverURI.fullPathURI("http://\(coverHost)\(portExtension)/\(prefix)\(coverURI)")
        }
        else if postfix == "<track>" {
            song.coverURI = CoverURI.filenameOptionsURI("http://\(coverHost)\(portExtension)/\(prefix)\(song.id)", newPath, ["cover.jpg"])
        }
        else if alternativePostfix == "" {
            song.coverURI = CoverURI.filenameOptionsURI("http://\(coverHost)\(portExtension)/\(prefix)\(coverURI)", newPath, [postfix, CoverURI.embeddedPrefix + song.id])
        }
        else {
            song.coverURI = CoverURI.filenameOptionsURI("http://\(coverHost)\(portExtension)/\(prefix)\(coverURI)", newPath, [postfix, alternativePostfix, CoverURI.embeddedPrefix + song.id])
        }

        return song
    }
    
//    private static func coverFileAtPath(mpd: MPDProtocol, connectionProperties: [String: Any], path: String) -> String? {
//        guard let conn = connect(mpd: mpd, connectionProperties: connectionProperties) else { return nil }
//
//        var coverFile: String? = nil
//        _ = mpd.send_list_files(conn, path: path)
//        while let entity = mpd.recv_entity(conn) {
//            if mpd.entity_get_type(entity) == MPD_ENTITY_TYPE_SONG {
//                let mpdSong = mpd.entity_get_song(entity)
//                let uri = mpd.song_get_uri(mpdSong)
//
//                let components = uri.split(separator: "/")
//                if components.count > 0 {
//                    let lastComponent = components[components.count - 1]
//                    if lastComponent.contains(".jpg") || lastComponent.contains(".jpeg") || lastComponent.contains(".png") {
//                        coverFile = String.init(lastComponent)
//                    }
//                }
//            }
//            mpd.entity_free(entity)
//
//            if coverFile != nil {
//                break
//            }
//        }
//        _ = mpd.response_finish(conn)
//        mpd.connection_free(conn)
//
//        return coverFile
//    }
    
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

    /// Fill a generic Folder object from an mpdFolder
    ///
    /// - Parameters:
    ///   - mpd: MPDProtocol object
    ///   - mpdDirectory: pointer to a mpd directory data structure
    /// - Returns: the filled Folder object
    public static func folderFromMPDDirectory(mpd: MPDProtocol, mpdDirectory: OpaquePointer!) -> Folder? {
        guard mpdDirectory != nil else  {
            return nil
        }
        
        var folder = Folder()
        
        folder.path = mpd.playlist_get_path(mpdDirectory)
        folder.id = folder.path
        folder.source = .Local
        let elements = folder.id.split(separator: "/")
        if let name = elements.last {
            folder.name = String(name)
        }
        else {
            folder.name = "Unknown"
        }
        
        return folder
    }

    /// Fill a generic Output object from an mpdOutput
    ///
    /// - Parameters:
    ///   - mpd: MPDProtocol object
    ///   - mpdOutput: pointer to a mpd output data structure
    /// - Returns: the filled Output object
    public static func outputFromMPDOutput(mpd: MPDProtocol, mpdOutput: OpaquePointer!) -> Output? {
        guard mpdOutput != nil else  {
            return nil
        }
        
        var output = Output()
        
        output.id = "\(mpd.output_get_id(mpdOutput))"
        output.name = mpd.output_get_name(mpdOutput)
        output.enabled = mpd.output_get_enabled(mpdOutput)
        
        return output
    }
    
    /// Compare two mpd version strings
    ///
    /// - Parameters:
    ///   - leftVersion: the left version string to compare
    ///   - rightVersion: the right version string to compare
    /// - Returns: The ordering of the two versions
    public static func compareVersion(leftVersion: String, rightVersion: String) -> ComparisonResult {
        let leftComponents = leftVersion.split(separator: ".")
        let rightComponents = rightVersion.split(separator: ".")
        let numberOfComponents = min(leftComponents.count, rightComponents.count)
        
        for x in 0..<numberOfComponents {
            let leftValue = Int(leftComponents[x]) ?? 0
            let rightValue = Int(rightComponents[x]) ?? 0
            
            if leftValue < rightValue {
                return .orderedAscending
            }
            else if leftValue > rightValue {
                return .orderedDescending
            }
        }
        
        return .orderedSame
    }
    
    private static let volumeAdjustmentKey = "MPDControl.volumeAdjustmentKey"
    public static func playerVolumeAdjustmentKey(_ playerName: String) -> String {
        volumeAdjustmentKey + "." + playerName
    }

    public static func adjustedVolumeToPlayer(_ volume: Float, volumeAdjustment: Float?) -> Float {
        guard let volumeAdjustment = volumeAdjustment else { return volume }
        if volume < 0.5 {
            return volume * volumeAdjustment * 2
        }
        else if volume > 0.5 {
            return volumeAdjustment + ((volume - 0.5) * (1 - volumeAdjustment) * 2)
        }
        
        return volumeAdjustment
    }

    public static func adjustedVolumeFromPlayer(_ volume: Float, volumeAdjustment: Float?) -> Float {
        guard let volumeAdjustment = volumeAdjustment else { return volume }
        
        if volume < volumeAdjustment {
            return (volume / volumeAdjustment) / 2.0
        }
        else if volume > volumeAdjustment {
            return 0.5 + ((volume - volumeAdjustment) * 0.5 ) / (1 - volumeAdjustment)
        }
        
        return volume
    }
}
