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
    var random = false
    var state = MPD_STATE_UNKNOWN
    
    func stringFromMPDString(_ mpdString: UnsafePointer<Int8>?) -> String {
        if let string = mpdString {
            let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: string), count: Int(strlen(string)), deallocator: .none)
            return String(data: data, encoding: .utf8) ?? ""
        }
        return ""
    }
    
    func connection_new(_ host: UnsafePointer<Int8>!, _ port: UInt32, _ timeout_ms: UInt32) -> OpaquePointer! {
        registerCall("connection_new", ["host": stringFromMPDString(host), "port": "\(port)", "timeout": "\(timeout_ms)"])
        return OpaquePointer.init(bitPattern: 1)
    }
    
    func connection_free(_ connection: OpaquePointer!) {
        registerCall("connection_free", ["connection": "\(connection)"])
    }
    
    func run_play(_ connection: OpaquePointer!) -> Bool {
        registerCall("run_play", [:])
        return true
    }
    
    func run_pause(_ connection: OpaquePointer!, _ mode: Bool) -> Bool {
        registerCall("run_pause", ["mode": "\(mode)"])
        return true
    }
    
    func run_next(_ connection: OpaquePointer!) -> Bool {
        registerCall("run_next", [:])
        return true
    }
    
    func run_previous(_ connection: OpaquePointer!) -> Bool {
        registerCall("run_previous", [:])
        return true
    }
    
    func run_random(_ connection: OpaquePointer!, _ mode: Bool) -> Bool {
        registerCall("run_random", ["mode": "\(mode)"])
        return true
    }
    
    func run_repeat(_ connection: OpaquePointer!, _ mode: Bool) -> Bool {
        registerCall("run_repeat", ["mode": "\(mode)"])
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
    
    func status_get_random(_ status: OpaquePointer!) -> Bool {
        registerCall("status_get_random", ["status": "\(status)"])
        return random
    }
    
    func status_get_state(_ status: OpaquePointer!) -> mpd_state {
        registerCall("status_get_state", ["status": "\(status)"])
        return state
    }
    
    func status_get_elapsed_time(_ status: OpaquePointer!) -> UInt32 {
        registerCall("status_get_elapsed_time", ["status": "\(status)"])
        return elapsedTime
    }
    
    func status_get_total_time(_ status: OpaquePointer!) -> UInt32 {
        registerCall("status_get_total_time", ["status": "\(status)"])
        return trackTime
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
}
