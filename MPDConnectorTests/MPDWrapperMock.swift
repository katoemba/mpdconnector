//
//  MPDWrapperMock.swift
//  MPDConnector
//
//  Created by Berrie Kremers on 09-08-17.
//  Copyright © 2017 Kaotemba Software. All rights reserved.
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
    var state = MPD_STATE_UNKNOWN
    var connectionErrorCount = 0
    var connectionError = MPD_ERROR_SUCCESS
    var connectionErrorMessage = ""
    var connectionServerError = MPD_SERVER_ERROR_UNK
    var password = ""
    var queueLength = UInt32(0)
    var queueVersion = UInt32(0)
    var songIndex = Int32(0)
    var availableSongs = 0
    var songDuration = UInt32(0)
    var songUri = ""
    var searchName = ""
    var searchValue = ""
    var testScheduler: TestScheduler?
    var noidle: PublishSubject<Int>?
    
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
        return OpaquePointer.init(bitPattern: 5)
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
    
    func song_get_tag(_ song: OpaquePointer!, _ type: mpd_tag_type, _ idx: UInt32) -> String {
        registerCall("song_get_tag", ["song": "\(song)", "type": "\(type)", "idx": "\(idx)"])
        switch type {
        case MPD_TAG_TITLE:
            return songTitle
        case MPD_TAG_ALBUM:
            return album
        case MPD_TAG_ARTIST:
            return artist
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

    func send_list_queue_range_meta(_ connection: OpaquePointer!, start: UInt32, end: UInt32) -> Bool {
        registerCall("send_list_queue_range_meta", ["start": "\(start)", "end": "\(end)"])
        availableSongs = Int(end) - Int(start)
        return true
    }
    
    func get_song(_ connection: OpaquePointer!) -> OpaquePointer! {
        registerCall("get_song", [:])
        if availableSongs > 0 {
            availableSongs -= 1
            return OpaquePointer.init(bitPattern: 6)
        }
        else {
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
    
    func search_commit(_ connection: OpaquePointer!) throws  {
        registerCall("search_add_window", [:])
    }
    
    func search_cancel(_ connection: OpaquePointer!) {
        registerCall("search_cancel", [:])
    }
    
    func recv_pair_tag(_ connection: OpaquePointer!, tagType: mpd_tag_type) -> (String, String)? {
        registerCall("recv_pair_tag", ["tagType": "\(tagType)"])
        return (searchName, searchValue)
    }

    func search_db_songs(_ connection: OpaquePointer!, exact: Bool) throws {
        registerCall("search_db_songs", ["exact": "\(exact)"])
    }

    func run_add(_ connection: OpaquePointer!, uri: UnsafePointer<Int8>!) -> Bool {
        registerCall("run_add", ["uri": "\(uri)"])
        return true
    }
    
    func run_add_id_to(_ connection: OpaquePointer!, uri: UnsafePointer<Int8>!, to: UInt32) -> Int32 {
        registerCall("run_add_id_to", ["uri": "\(uri)", "to": "\(to)"])
        return Int32(to)
    }
    
    func run_clear(_ connection: OpaquePointer!) -> Bool {
        registerCall("run_clear", [:])
        return true
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
