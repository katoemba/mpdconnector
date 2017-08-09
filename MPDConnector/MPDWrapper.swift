//
//  MPDWrapper.swift
//  MPDConnector
//
//  Created by Berrie Kremers on 09-08-17.
//  Copyright © 2017 Kaotemba Software. All rights reserved.
//

import Foundation
import libmpdclient

/// The functions provided by MPDWrapper will directly call the matching mpd_xxx function. The only conversion
/// that takes places is from UnsafePointer<Int8> to String for return values.
class MPDWrapper: MPDProtocol {
    func connection_new(_ host: UnsafePointer<Int8>!, _ port: UInt32, _ timeout_ms: UInt32) -> OpaquePointer! {
        return mpd_connection_new(host, port, timeout_ms)
    }
    
    func connection_free(_ connection: OpaquePointer!) {
        mpd_connection_free(connection)
    }

    func run_play(_ connection: OpaquePointer!) -> Bool {
        return mpd_run_play(connection)
    }
    
    func run_pause(_ connection: OpaquePointer!, _ mode: Bool) -> Bool {
        return mpd_run_pause(connection, mode)
    }
    
    func run_next(_ connection: OpaquePointer!) -> Bool {
        return mpd_run_next(connection)
    }
    
    func run_previous(_ connection: OpaquePointer!) -> Bool {
        return mpd_run_previous(connection)
    }
    
    func run_random(_ connection: OpaquePointer!, _ mode: Bool) -> Bool {
        return mpd_run_random(connection, mode)
    }

    func run_repeat(_ connection: OpaquePointer!, _ mode: Bool) -> Bool {
        return mpd_run_repeat(connection, mode)
    }
    
    func run_set_volume(_ connection: OpaquePointer!, _ volume: UInt32) -> Bool {
        return mpd_run_set_volume(connection, volume)
    }
    
    func run_status(_ connection: OpaquePointer!) -> OpaquePointer! {
        return mpd_run_status(connection)
    }
    
    func status_free(_ status: OpaquePointer!) {
        mpd_status_free(status)
    }
    
    func run_current_song(_ connection: OpaquePointer!) -> OpaquePointer! {
        return mpd_run_current_song(connection)
    }
    
    func song_free(_ song: OpaquePointer!) {
        mpd_song_free(song)
    }
    
    func status_get_volume(_ status: OpaquePointer!) -> Int32 {
        return mpd_status_get_volume(status)
    }
    
    func status_get_repeat(_ status: OpaquePointer!) -> Bool {
        return mpd_status_get_repeat(status)
    }

    func status_get_random(_ status: OpaquePointer!) -> Bool {
        return mpd_status_get_random(status)
    }
    
    func status_get_state(_ status: OpaquePointer!) -> mpd_state {
        return mpd_status_get_state(status)
    }
    
    func status_get_elapsed_time(_ status: OpaquePointer!) -> UInt32 {
        return mpd_status_get_elapsed_time(status)
    }
    
    func status_get_total_time(_ status: OpaquePointer!) -> UInt32 {
        return mpd_status_get_total_time(status)
    }

    func song_get_tag(_ song: OpaquePointer!, _ type: mpd_tag_type, _ idx: UInt32) -> String {
        return stringFromMPDString(mpd_song_get_tag(song, type, idx))
    }
    
    /// Convert a raw mpd-string to a standard Swift string.
    ///
    /// - Parameter mpdString: Pointer to a null-terminated (unsigned char) string.
    /// - Returns: Converted string, or empty string "" in case conversion failed.
    func stringFromMPDString(_ mpdString: UnsafePointer<Int8>?) -> String {
        if let string = mpdString {
            let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: string), count: Int(strlen(string)), deallocator: .none)
            return String(data: data, encoding: .utf8) ?? ""
        }
        return ""
    }
}
