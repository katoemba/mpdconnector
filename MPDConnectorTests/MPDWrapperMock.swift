//
//  MPDWrapperMock.swift
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
import MPDConnector
import libmpdclient
import RxSwift
import RxTest

class MPDWrapperMock: MockBase, MPDProtocol {
    /// Dictionary of calls (functionName as key) and parameters as value.
    /// Values is an array of dictionaries, where key=parameter-name, value=parameter-value
    var volume = Int32(0)
    var elapsedTime = UInt32(0)
    var trackTime = UInt32(0)
    var songTitle = ""
    var album = ""
    var artist = ""
    var repeatValue = false
    var singleValue = false
    var random = false
    var consumeMode = false
    var state = MPD_STATE_UNKNOWN
    var connectionErrorCount = 0
    var connectionError = MPD_ERROR_SUCCESS
    var connectionErrorMessage = ""
    var connectionServerError = MPD_SERVER_ERROR_UNK
    var password = ""
    var queueLength = UInt32(0)
    var queueVersion = UInt32(0)
    var songIndex = Int32(0)
    var songDuration = UInt32(0)
    var songUri = ""
    var songLastModifiedDate = Date(timeIntervalSince1970: 0)
    var searchName = ""
    var searchValue = ""
    var testScheduler: TestScheduler?
    var noidle: PublishSubject<Int>?
    var currentSong: [String:String]?
    var songs = [[String:String]]()
    var currentPlaylist: [String:String]?
    var playlists = [[String:String]]()
    var playlistPath = ""
    var playlistLastModified = Date(timeIntervalSince1970: 0)
    var playerVersion = "0.0.0"
    var samplerate = UInt32(128000)
    var encoding = UInt8(16)
    var channels = UInt8(2)
    var updateId = UInt32(5)
    var mpdEntityType = MPD_ENTITY_TYPE_UNKNOWN
    var dbUpdateTime = Date(timeIntervalSince1970: 0)
    var entities = [mpd_entity_type]()
    var currentEntity: mpd_entity_type?
    var directories = [[String:String]]()
    var currentDirectory: [String:String]?
    var outputs = [(UInt32, String, Bool)]()
    var tagTypes = [String]()

    func stringFromMPDString(_ mpdString: UnsafePointer<Int8>?) -> String {
        if let string = mpdString {
            let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: string), count: Int(strlen(string)), deallocator: .none)
            return String(data: data, encoding: .utf8) ?? ""
        }
        return ""
    }
    
    func connection_new(_ host: UnsafePointer<Int8>!, _ port: UInt32, _ timeout_ms: UInt32) -> OpaquePointer! {
        registerCall("connection_new", ["host": stringFromMPDString(host), "port": "\(port)", "timeout": "\(timeout_ms)"])
        
        if connectionErrorCount > 0 {
            connectionErrorCount -= 1
            connectionError = MPD_ERROR_RESOLVER
            connectionErrorMessage = "Error"
        }
        else {
            connectionError = MPD_ERROR_SUCCESS
            connectionErrorMessage = ""
        }
        
        return OpaquePointer.init(bitPattern: 1)
    }
    
    func connection_free(_ connection: OpaquePointer!) {
        registerCall("connection_free", ["connection": "\(connection)"])
    }
    
    public func connection_get_error(_ connection: OpaquePointer!) -> mpd_error {
        registerCall("connection_get_error", [:])
        return connectionError
    }
    
    public func connection_get_error_message(_ connection: OpaquePointer!) -> String {
        registerCall("connection_get_error_message", [:])
        return connectionErrorMessage
    }
    
    public func connection_get_server_error(_ connection: OpaquePointer!) -> mpd_server_error {
        registerCall("connection_get_server_error", [:])
        return connectionServerError
    }
    
    public func connection_clear_error(_ connection: OpaquePointer!) -> Bool {
        registerCall("connection_clear_error", [:])
        
        connectionError = MPD_ERROR_SUCCESS
        connectionErrorMessage = ""

        return true
    }
    
    public func run_password(_ connection: OpaquePointer!, password: UnsafePointer<Int8>!) -> Bool {
        registerCall("run_password", ["password": stringFromMPDString(password)])
        if self.password == stringFromMPDString(password) {
            connectionError = MPD_ERROR_SUCCESS
        }
        else {
            connectionError = MPD_ERROR_SERVER
            connectionServerError = MPD_SERVER_ERROR_PASSWORD
        }
        return true
    }
    
    func run_play(_ connection: OpaquePointer!) -> Bool {
        registerCall("run_play", [:])
        self.state = MPD_STATE_PLAY
        return true
    }
    
    func run_stop(_ connection: OpaquePointer!) -> Bool {
        registerCall("run_stop", [:])
        self.state = MPD_STATE_STOP
        return true
    }
    
    func run_play_pos(_ connection: OpaquePointer!, _ song_pos: UInt32) -> Bool {
        registerCall("run_play_pos", ["song_pos": "\(song_pos)"])
        self.state = MPD_STATE_PLAY
        self.songIndex = Int32(song_pos)
        return true
    }
    
    func run_pause(_ connection: OpaquePointer!, _ mode: Bool) -> Bool {
        registerCall("run_pause", ["mode": "\(mode)"])
        self.state = MPD_STATE_PAUSE
        return true
    }
    
    func run_toggle_pause(_ connection: OpaquePointer!) -> Bool {
        registerCall("run_toggle_pause", [:])
        self.state = (self.state == MPD_STATE_PLAY) ? MPD_STATE_PAUSE : MPD_STATE_PLAY
        return true
    }
    
    func run_next(_ connection: OpaquePointer!) -> Bool {
        registerCall("run_next", [:])
        self.songIndex += 1
        return true
    }
    
    func run_previous(_ connection: OpaquePointer!) -> Bool {
        registerCall("run_previous", [:])
        self.songIndex -= 1
        return true
    }
    
    func run_random(_ connection: OpaquePointer!, _ mode: Bool) -> Bool {
        registerCall("run_random", ["mode": "\(mode)"])
        self.random = mode
        return true
    }
    
    func run_shuffle(_ connection: OpaquePointer!) -> Bool {
        registerCall("run_shuffle", [:])
        self.queueVersion += 1
        return true
    }
    
    func run_repeat(_ connection: OpaquePointer!, _ mode: Bool) -> Bool {
        registerCall("run_repeat", ["mode": "\(mode)"])
        self.repeatValue = mode
        return true
    }
    
    func run_single(_ connection: OpaquePointer!, _ mode: Bool) -> Bool {
        registerCall("run_single", ["mode": "\(mode)"])
        self.singleValue = mode
        return true
    }
    
    func run_consume(_ connection: OpaquePointer!, _ mode: Bool) -> Bool {
        registerCall("run_consume", ["mode": "\(mode)"])
        self.consumeMode = mode
        return true
    }
    
    func run_set_volume(_ connection: OpaquePointer!, _ volume: UInt32) -> Bool {
        registerCall("run_set_volume", ["volume": "\(volume)"])
        return true
    }
    
    func run_status(_ connection: OpaquePointer!) -> OpaquePointer! {
        registerCall("run_status", [:])
        return OpaquePointer.init(bitPattern: 2)
    }
    
    func status_free(_ status: OpaquePointer!) {
        registerCall("status_free", ["status": "\(status)"])
    }
    
    func run_current_song(_ connection: OpaquePointer!) -> OpaquePointer! {
        registerCall("run_current_song", [:])
        currentSong = ["title": songTitle, "album": album, "artist": artist]
        return OpaquePointer.init(bitPattern: 5)
    }
    
    func run_seek(_ connection: OpaquePointer!, pos: UInt32, t: UInt32) -> Bool {
        registerCall("run_seek", ["pos": "\(pos)", "t": "\(t)"])
        return true
    }
    
    func song_free(_ song: OpaquePointer!) {
        registerCall("song_free", ["song": "\(song)"])
    }
    
    func status_get_volume(_ status: OpaquePointer!) -> Int32 {
        registerCall("status_get_volume", ["status": "\(status)"])
        return volume
    }
    
    func status_get_repeat(_ status: OpaquePointer!) -> Bool {
        registerCall("status_get_repeat", ["status": "\(status)"])
        return repeatValue
    }
    
    func status_get_single(_ status: OpaquePointer!) -> Bool {
        registerCall("status_get_single", ["status": "\(status)"])
        return singleValue
    }
    
    func status_get_random(_ status: OpaquePointer!) -> Bool {
        registerCall("status_get_random", ["status": "\(status)"])
        return random
    }
    
    func status_get_consume(_ status: OpaquePointer!) -> Bool {
        registerCall("status_get_consume", ["status": "\(status)"])
        return consumeMode
    }
    
    func status_get_state(_ status: OpaquePointer!) -> mpd_state {
        registerCall("status_get_state", ["status": "\(status)"])
        return state
    }
    
    func status_get_song_pos(_ status: OpaquePointer!) -> Int32 {
        registerCall("status_get_song_pos", ["status": "\(status)"])
        return songIndex
    }
    
    func status_get_elapsed_time(_ status: OpaquePointer!) -> UInt32 {
        registerCall("status_get_elapsed_time", ["status": "\(status)"])
        return elapsedTime
    }
    
    func status_get_total_time(_ status: OpaquePointer!) -> UInt32 {
        registerCall("status_get_total_time", ["status": "\(status)"])
        return trackTime
    }
    
    func status_get_queue_length(_ status: OpaquePointer!) -> UInt32 {
        registerCall("status_get_queue_length", ["status": "\(status)"])
        return queueLength
    }
    
    func status_get_queue_version(_ status: OpaquePointer!) -> UInt32 {
        registerCall("status_get_queue_version", ["status": "\(status)"])
        return queueVersion
    }
    
    func status_get_kbit_rate(_ status: OpaquePointer!) -> UInt32 {
        registerCall("status_get_kbit_rate", ["status": "\(status)"])
        return samplerate
    }
    
    func status_get_audio_format(_ status: OpaquePointer!) -> (UInt32, UInt8, UInt8)? {
        registerCall("status_get_audio_format", ["status": "\(status)"])
        return (samplerate, encoding, channels)
    }

    func song_get_tag(_ song: OpaquePointer!, _ type: mpd_tag_type, _ idx: UInt32) -> String {
        registerCall("song_get_tag", ["song": "\(song)", "type": "\(type)", "idx": "\(idx)"])
        switch type {
        case MPD_TAG_TITLE:
            return currentSong!["title"]!
        case MPD_TAG_ALBUM:
            return currentSong!["album"]!
        case MPD_TAG_ARTIST:
            return currentSong!["artist"]!
        default:
            return "Unknown"
        }
    }
    
    func song_get_uri(_ song: OpaquePointer!) -> String {
        registerCall("song_get_uri", ["song": "\(song)"])
        return songUri
    }

    
    func song_get_duration(_ song: OpaquePointer!) -> UInt32 {
        registerCall("song_get_tag", ["song": "\(song)"])
        return songDuration
    }
    
    func song_get_last_modified(_ song: OpaquePointer!) -> Date {
        registerCall("song_get_last_modified", ["song": "\(song)"])
        return songLastModifiedDate
    }

    func send_list_queue_range_meta(_ connection: OpaquePointer!, start: UInt32, end: UInt32) -> Bool {
        registerCall("send_list_queue_range_meta", ["start": "\(start)", "end": "\(end)"])
        return true
    }
    
    func send_list_files(_ connection: OpaquePointer!, path: UnsafePointer<Int8>!) -> Bool {
        registerCall("send_list_files", ["path": "\(stringFromMPDString(path))"])
        return true
    }

    func recv_song(_ connection: OpaquePointer!) -> OpaquePointer! {
        registerCall("recv_song", [:])
        if songs.count > 0 {
            currentSong = songs[0]
            songs.removeFirst()
            return OpaquePointer.init(bitPattern: 6)
        }
        else {
            currentSong = nil
            return nil
        }
    }
    
    func response_finish(_ connection: OpaquePointer!) -> Bool {
        registerCall("response_finish", [:])
        return true
    }

    func run_save(_ connection: OpaquePointer!, name: UnsafePointer<Int8>!) -> Bool {
        registerCall("run_save", ["name": stringFromMPDString(name)])
        return true
    }
    
    func run_load(_ connection: OpaquePointer!, name: UnsafePointer<Int8>!) -> Bool {
        registerCall("run_load", ["name": stringFromMPDString(name)])
        return true
    }

    func run_playlist_add(_ connection: OpaquePointer!, name: UnsafePointer<Int8>!, path: UnsafePointer<Int8>!) -> Bool {
        registerCall("run_playlist_add", ["name": stringFromMPDString(name), "path": stringFromMPDString(path)])
        return true
    }
    
    func search_db_tags(_ connection: OpaquePointer!, tagType: mpd_tag_type) throws {
        registerCall("search_db_tags", ["tagType": "\(tagType)"])
    }
    
    func search_add_tag_constraint(_ connection: OpaquePointer!, oper: mpd_operator, tagType: mpd_tag_type, value: UnsafePointer<Int8>!) throws {
        registerCall("search_add_tag_constraint", ["oper": "\(oper)", "tagType": "\(tagType)", "value": stringFromMPDString(value)])
    }
    
    func search_add_sort_tag(_ connection: OpaquePointer!, tagType: mpd_tag_type) throws {
        registerCall("search_add_sort_tag", ["tagType": "\(tagType)"])
    }
    
    func search_add_window(_ connection: OpaquePointer!, start: UInt32, end: UInt32) throws {
        registerCall("search_add_window", ["start": "\(start)", "end": "\(end)"])
    }
    
    func search_add_group_tag(_ connection: OpaquePointer!, tagType: mpd_tag_type) throws {
        registerCall("search_add_group_tag", ["tagType": "\(tagType)"])
    }
    
    func search_add_db_songs(_ connection: OpaquePointer!, exact: Bool) throws {
        registerCall("search_add_db_songs", ["exact": "\(exact)"])
    }
    
    func search_add_modified_since_constraint(_ connection: OpaquePointer!, oper: mpd_operator, since: Date) throws {
        registerCall("search_add_modified_since_constraint", ["oper": "\(oper)", "since": "\(since)"])
    }

    func search_commit(_ connection: OpaquePointer!) throws  {
        registerCall("search_commit", [:])
    }
    
    func search_cancel(_ connection: OpaquePointer!) {
        registerCall("search_cancel", [:])
    }
    
    public func send_list_tag_types(_ connection: OpaquePointer!) -> Bool {
        registerCall("send_list_tag_types", [:])
        return true
    }
    
    public func recv_tag_type_pair(_ connection: OpaquePointer!) -> (String, String)? {
        registerCall("recv_tag_type_pair", [:])
        if tagTypes.count > 0 {
            let currentTagType = tagTypes[0]
            tagTypes.removeFirst()
            return ("tagtype", currentTagType)
        }
        else {
            return nil
        }
    }

    func recv_pair_tag(_ connection: OpaquePointer!, tagType: mpd_tag_type) -> (String, String)? {
        registerCall("recv_pair_tag", ["tagType": "\(tagType)"])
        return (searchName, searchValue)
    }

    func recv_pair(_ connection: OpaquePointer!) -> (String, String)? {
        registerCall("recv_pair", [:])
        return (searchName, searchValue)
    }
    
    func tag_name_parse(_ name: UnsafePointer<Int8>!) -> mpd_tag_type {
        registerCall("tag_name_parse", ["name": "\(stringFromMPDString(name))"])
        return mpd_tag_name_parse(name)
    }
    
    func tag_name(tagType: mpd_tag_type) -> String {
        registerCall("tag_name", ["tag": "\(tagType)"])
        return stringFromMPDString(mpd_tag_name(tagType))
    }

    func search_db_songs(_ connection: OpaquePointer!, exact: Bool) throws {
        registerCall("search_db_songs", ["exact": "\(exact)"])
    }

    func status_get_update_id(_ status: OpaquePointer!) -> UInt32 {
        registerCall("status_get_update_id", [:])
        return updateId
    }
    
    func send_list_meta(_ connection: OpaquePointer!, path: UnsafePointer<Int8>!) -> Bool {
        registerCall("send_list_meta", ["path": "\(stringFromMPDString(path))"])
        return true
    }
    
    func recv_entity(_ connection: OpaquePointer!) -> OpaquePointer! {
        registerCall("recv_entity", [:])
        if entities.count > 0 {
            currentEntity = entities[0]
            entities.removeFirst()
            return OpaquePointer.init(bitPattern: 6)
        }
        else {
            currentEntity = nil
            return nil
        }
    }
    
    func entity_get_type(_ entity: OpaquePointer!) -> mpd_entity_type {
        registerCall("entity_get_type", [:])
        if currentEntity! == MPD_ENTITY_TYPE_SONG {
            currentSong = songs[0]
            songs.removeFirst()
        }
        else if currentEntity! == MPD_ENTITY_TYPE_DIRECTORY {
            currentDirectory = directories[0]
            directories.removeFirst()
        }
        else if currentEntity! == MPD_ENTITY_TYPE_PLAYLIST {
            currentPlaylist = playlists[0]
            playlists.removeFirst()
        }
        return currentEntity!
    }
    
    func entity_get_directory(_ entity: OpaquePointer!) -> OpaquePointer! {
        registerCall("entity_get_directory", [:])
        return OpaquePointer.init(bitPattern: 6)
    }
    
    func entity_get_song(_ entity: OpaquePointer!) -> OpaquePointer! {
        registerCall("entity_get_song", [:])
        return OpaquePointer.init(bitPattern: 6)
    }
    
    func entity_get_playlist(_ entity: OpaquePointer!) -> OpaquePointer! {
        registerCall("entity_get_playlist", [:])
        return OpaquePointer.init(bitPattern: 6)
    }
    
    func entity_free(_ entity: OpaquePointer!) {
        registerCall("entity_free", [:])
    }
    
    func directory_get_path(_ directory: OpaquePointer!) -> String {
        registerCall("directory_get_path", [:])
        return currentDirectory!["path"]!
    }
    
    func directory_free(_ directory: OpaquePointer!) {
        registerCall("directory_free", [:])
    }
    
    func run_update(_ connection: OpaquePointer!, path: UnsafePointer<Int8>!) -> UInt32 {
        registerCall("run_update", ["path": "\(stringFromMPDString(path))"])
        return updateId
    }
    
    func run_stats(_ connection: OpaquePointer!) -> OpaquePointer! {
        registerCall("run_stats", [:])
        return OpaquePointer.init(bitPattern: 6)
    }
    
    func stats_free(_ stats: OpaquePointer!) {
        registerCall("stats_free", [:])
    }
    
    func stats_get_db_update_time(_ stats: OpaquePointer!) -> Date {
        registerCall("stats_get_db_update_time", [:])
        return dbUpdateTime
    }
    
    func run_add(_ connection: OpaquePointer!, uri: UnsafePointer<Int8>!) -> Bool {
        registerCall("run_add", ["uri": "\(stringFromMPDString(uri))"])
        return true
    }
    
    func run_add_id_to(_ connection: OpaquePointer!, uri: UnsafePointer<Int8>!, to: UInt32) -> Int32 {
        registerCall("run_add_id_to", ["uri": "\(stringFromMPDString(uri))", "to": "\(to)"])
        return Int32(to)
    }
    
    func send_add(_ connection: OpaquePointer!, uri: UnsafePointer<Int8>!) -> Bool {
        registerCall("send_add", ["uri": "\(stringFromMPDString(uri))"])
        return true
    }
    
    func send_add_id_to(_ connection: OpaquePointer!, uri: UnsafePointer<Int8>!, to: UInt32) -> Bool {
        registerCall("send_add_id_to", ["uri": "\(stringFromMPDString(uri))", "to": "\(to)"])
        return true
    }

    func run_move(_ connection: OpaquePointer!, from: UInt32, to: UInt32) -> Bool {
        registerCall("run_move", ["from": "\(from)", "to": "\(to)"])
        return true
    }

    public func run_move_range(_ connection: OpaquePointer!, start: UInt32, end: UInt32, to: UInt32) -> Bool {
        registerCall("run_move_range", ["start": "\(start)", "end": "\(end)", "to": "\(to)"])
        return true
    }

    func run_delete(_ connection: OpaquePointer!, pos: UInt32) -> Bool {
        registerCall("run_delete", ["pos": "\(pos)"])
        return true
    }
    
    func run_clear(_ connection: OpaquePointer!) -> Bool {
        registerCall("run_clear", [:])
        return true
    }
    
    func send_list_playlists(_ connection: OpaquePointer!) -> Bool {
        registerCall("send_list_playlists", [:])
        return true
    }
    
    func recv_playlist(_ connection: OpaquePointer!) -> OpaquePointer! {
        registerCall("recv_playlist", [:])
        if playlists.count > 0 {
            currentPlaylist = playlists[0]
            playlists.removeFirst()
            return OpaquePointer.init(bitPattern: 6)
        }
        else {
            currentPlaylist = nil
            return nil
        }
    }
    
    func playlist_free(_ playlist: OpaquePointer!) {
        registerCall("playlist_free", [:])
    }
    
    func playlist_get_path(_ playlist: OpaquePointer!) -> String {
        registerCall("playlist_get_path", [:])
        return currentPlaylist!["id"]!
    }
    
    func playlist_get_last_modified(_ playlist: OpaquePointer!) -> Date {
        registerCall("playlist_get_last_modified", [:])
        return playlistLastModified
    }
    
    func send_list_playlist_meta(_ connection: OpaquePointer!, name: UnsafePointer<Int8>!) -> Bool {
        registerCall("send_list_playlist_meta", ["name": "\(stringFromMPDString(name))"])
        return true
    }
    
    func run_rename(_ connection: OpaquePointer!, from: UnsafePointer<Int8>!, to: UnsafePointer<Int8>!) -> Bool {
        registerCall("run_rename", ["from": "\(stringFromMPDString(from))", "to": "\(stringFromMPDString(to))"])
        return true
    }
    
    func run_rm(_ connection: OpaquePointer!, name: UnsafePointer<Int8>!) -> Bool {
        registerCall("run_rm", ["name": "\(stringFromMPDString(name))"])
        return true
    }
    
    func run_playlist_move(_ connection: OpaquePointer!, name: UnsafePointer<Int8>!, from: UInt32, to: UInt32) -> Bool {
        registerCall("run_playlist_move", ["name": "\(stringFromMPDString(name))", "from": "\(from)", "to": "\(to)"])
        return true
    }
    
    func run_playlist_delete(_ connection: OpaquePointer!, name: UnsafePointer<Int8>!, pos: UInt32) -> Bool {
        registerCall("run_playlist_delete", ["name": "\(stringFromMPDString(name))", "pos": "\(pos)"])
        return true
    }
    
    func command_list_begin(_ connection: OpaquePointer!, discrete_ok: Bool) -> Bool {
        registerCall("command_list_begin", ["discrete_ok": "\(discrete_ok)"])
        return true
    }
    
    func command_list_end(_ connection: OpaquePointer!) -> Bool {
        registerCall("command_list_end", [:])
        return true
    }
    
    public func connection_get_server_version(_ connection: OpaquePointer!) -> String {
        registerCall("connection_get_server_version", [:])
        return playerVersion
    }
    
    public func run_enable_output(_ connection: OpaquePointer!, output_id: UInt32) -> Bool {
        registerCall("run_enable_output", ["output_id": "\(output_id)"])
        return true
    }
    
    public func run_disable_output(_ connection: OpaquePointer!, output_id: UInt32) -> Bool {
        registerCall("run_disable_output", ["output_id": "\(output_id)"])
        return true
    }
    
    public func run_toggle_output(_ connection: OpaquePointer!, output_id: UInt32) -> Bool {
        registerCall("run_toggle_output", ["output_id": "\(output_id)"])
        return true
    }

    public func send_outputs(_ connection: OpaquePointer!) -> Bool {
        registerCall("send_outputs", [:])
        return true
    }
    
    public func recv_output(_ connection: OpaquePointer!) -> OpaquePointer! {
        registerCall("recv_output", [:])
        if outputs.count > 0 {
            return OpaquePointer.init(bitPattern: 7)
        }
        else {
            return nil
        }
    }
    
    public func output_get_id(_ output: OpaquePointer!) -> UInt32 {
        registerCall("output_get_id", [:])
        return outputs[0].0
    }
    
    public func output_get_name(_ output: OpaquePointer!) -> String {
        registerCall("output_get_name", [:])
        return outputs[0].1
    }
    
    public func output_get_enabled(_ output: OpaquePointer!) -> Bool {
        registerCall("output_get_enabled", [:])
        return outputs[0].2
    }
    
    public func output_free(_ output: OpaquePointer!) {
        outputs.removeFirst()
        registerCall("output_free", [:])
    }

    func run_idle_mask(_ connection: OpaquePointer!, mask: mpd_idle) -> mpd_idle {
        registerCall("run_idle_mask", ["mask": "\(mask)"])
        let _volume = volume
        let _songTitle = songTitle
        let _album = album
        let _artist = artist
        let _repeatValue = repeatValue
        let _singleValue = singleValue
        let _random = random
        let _state = state
        let _queueLength = queueLength
        let _queueVersion = queueVersion
        let _songIndex = songIndex
        
        
        noidle = PublishSubject<Int>()
        _ = try! noidle!.asObservable().toBlocking().first()
        
        if _volume != volume ||
            _songTitle != songTitle ||
            _album != album ||
            _artist != artist ||
            _repeatValue != repeatValue ||
            _singleValue != singleValue ||
            _random != random ||
            _state != state ||
            _queueLength != queueLength ||
            _queueVersion != queueVersion ||
            _songIndex != songIndex {
            return MPD_IDLE_QUEUE
        }

        return mpd_idle(rawValue: 0)
    }
    
    func send_noidle(_ connection: OpaquePointer!) -> Bool {
        registerCall("send_noidle", [:])
        noidle?.onNext(1)

        return true
    }
    
    func statusChanged() {
        noidle?.onNext(1)
    }
}
