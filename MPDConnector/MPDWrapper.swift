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
public class MPDWrapper: MPDProtocol {
    public init() {
    }
    
    public func connection_new(_ host: UnsafePointer<Int8>!, _ port: UInt32, _ timeout_ms: UInt32) -> OpaquePointer! {
        return mpd_connection_new(host, port, timeout_ms)
    }
    
    public func connection_free(_ connection: OpaquePointer!) {
        mpd_connection_free(connection)
    }

    public func connection_get_error(_ connection: OpaquePointer!) -> mpd_error {
        return mpd_connection_get_error(connection)
    }
    
    public func connection_get_error_message(_ connection: OpaquePointer!) -> String {
        return stringFromMPDString(mpd_connection_get_error_message(connection))
    }
    
    public func connection_get_server_error(_ connection: OpaquePointer!) -> mpd_server_error {
        return mpd_connection_get_server_error(connection)
    }
    
    public func connection_clear_error(_ connection: OpaquePointer!) -> Bool {
        return mpd_connection_clear_error(connection)
    }
    
    public func run_password(_ connection: OpaquePointer!, password: UnsafePointer<Int8>!) -> Bool {
        return mpd_run_password(connection, password)
    }

    public func run_play(_ connection: OpaquePointer!) -> Bool {
        return mpd_run_play(connection)
    }
    
    public func run_play_pos(_ connection: OpaquePointer!, _ song_pos: UInt32) -> Bool {
        return mpd_run_play_pos(connection, song_pos)
    }
    
    public func run_pause(_ connection: OpaquePointer!, _ mode: Bool) -> Bool {
        return mpd_run_pause(connection, mode)
    }
    
    public func run_toggle_pause(_ connection: OpaquePointer!) -> Bool {
        return mpd_run_toggle_pause(connection)
    }
    
    public func run_next(_ connection: OpaquePointer!) -> Bool {
        return mpd_run_next(connection)
    }
    
    public func run_previous(_ connection: OpaquePointer!) -> Bool {
        return mpd_run_previous(connection)
    }
    
    public func run_random(_ connection: OpaquePointer!, _ mode: Bool) -> Bool {
        return mpd_run_random(connection, mode)
    }

    public func run_shuffle(_ connection: OpaquePointer!) -> Bool {
        return mpd_run_shuffle(connection)
    }
    
    public func run_repeat(_ connection: OpaquePointer!, _ mode: Bool) -> Bool {
        return mpd_run_repeat(connection, mode)
    }
    
    public func run_single(_ connection: OpaquePointer!, _ mode: Bool) -> Bool {
        return mpd_run_single(connection, mode)
    }
    
    public func run_set_volume(_ connection: OpaquePointer!, _ volume: UInt32) -> Bool {
        return mpd_run_set_volume(connection, volume)
    }
    
    public func run_status(_ connection: OpaquePointer!) -> OpaquePointer! {
        return mpd_run_status(connection)
    }
    
    public func status_free(_ status: OpaquePointer!) {
        mpd_status_free(status)
    }
    
    public func run_current_song(_ connection: OpaquePointer!) -> OpaquePointer! {
        return mpd_run_current_song(connection)
    }
    
    public func song_free(_ song: OpaquePointer!) {
        mpd_song_free(song)
    }
    
    public func status_get_volume(_ status: OpaquePointer!) -> Int32 {
        return mpd_status_get_volume(status)
    }
    
    public func status_get_repeat(_ status: OpaquePointer!) -> Bool {
        return mpd_status_get_repeat(status)
    }

    public func status_get_random(_ status: OpaquePointer!) -> Bool {
        return mpd_status_get_random(status)
    }
    
    public func status_get_single(_ status: OpaquePointer!) -> Bool {
        return mpd_status_get_single(status)
    }
    
    public func status_get_state(_ status: OpaquePointer!) -> mpd_state {
        return mpd_status_get_state(status)
    }
    
    public func status_get_song_pos(_ status: OpaquePointer!) -> Int32 {
        return mpd_status_get_song_pos(status)
    }
    
    public func status_get_elapsed_time(_ status: OpaquePointer!) -> UInt32 {
        return mpd_status_get_elapsed_time(status)
    }
    
    public func status_get_total_time(_ status: OpaquePointer!) -> UInt32 {
        return mpd_status_get_total_time(status)
    }

    public func status_get_queue_length(_ status: OpaquePointer!) -> UInt32 {
        return mpd_status_get_queue_length(status)
    }
    
    public func status_get_queue_version(_ status: OpaquePointer!) -> UInt32 {
        return mpd_status_get_queue_version(status)
    }
    
    public func song_get_tag(_ song: OpaquePointer!, _ type: mpd_tag_type, _ idx: UInt32) -> String {
        return stringFromMPDString(mpd_song_get_tag(song, type, idx))
    }
    
    public func song_get_duration(_ song: OpaquePointer!) -> UInt32 {
        return mpd_song_get_duration(song)
    }

    public func song_get_uri(_ song: OpaquePointer!) -> String {
        return stringFromMPDString(mpd_song_get_uri(song))
    }
    
    public func send_list_queue_range_meta(_ connection: OpaquePointer!, start: UInt32, end: UInt32) -> Bool {
        return mpd_send_list_queue_range_meta(connection, start, end)
    }
    
    public func get_song(_ connection: OpaquePointer!) -> OpaquePointer! {
        return mpd_recv_song(connection)
    }
    
    public func response_finish(_ connection: OpaquePointer!) -> Bool {
        return mpd_response_finish(connection)
    }
    
    public func run_save(_ connection: OpaquePointer!, name: UnsafePointer<Int8>!) -> Bool {
        return mpd_run_save(connection, name)
    }
    
    public func run_load(_ connection: OpaquePointer!, name: UnsafePointer<Int8>!) -> Bool {
        return mpd_run_load(connection, name)
    }
    
    public func search_db_songs(_ connection: OpaquePointer!, exact: Bool) throws {
        if mpd_search_db_songs(connection, exact) == false {
            throw MPDError.commandFailed
        }
    }
    
    public func search_db_tags(_ connection: OpaquePointer!, tagType: mpd_tag_type) throws {
        if mpd_search_db_tags(connection, tagType) == false || mpd_connection_get_error(connection) != MPD_ERROR_SUCCESS {
            throw MPDError.commandFailed
        }
    }
    
    public func search_add_tag_constraint(_ connection: OpaquePointer!, oper: mpd_operator, tagType: mpd_tag_type, value: UnsafePointer<Int8>!) throws {
        if mpd_search_add_tag_constraint(connection, oper, tagType, value) == false || mpd_connection_get_error(connection) != MPD_ERROR_SUCCESS {
            throw MPDError.commandFailed
        }
    }
    
    public func search_add_sort_tag(_ connection: OpaquePointer!, tagType: mpd_tag_type) throws {
        if mpd_search_add_sort_tag(connection, tagType, false) == false || mpd_connection_get_error(connection) != MPD_ERROR_SUCCESS {
            throw MPDError.commandFailed
        }
    }
    
    public func search_add_window(_ connection: OpaquePointer!, start: UInt32, end: UInt32) throws {
        if mpd_search_add_window(connection, start, end) == false || mpd_connection_get_error(connection) != MPD_ERROR_SUCCESS {
            throw MPDError.commandFailed
        }
    }
    
    public func search_commit(_ connection: OpaquePointer!) throws {
        if mpd_search_commit(connection) == false || mpd_connection_get_error(connection) != MPD_ERROR_SUCCESS {
            throw MPDError.commandFailed
        }
    }
    
    public func search_cancel(_ connection: OpaquePointer!) {
        mpd_search_cancel(connection)
    }
    
    public func recv_pair_tag(_ connection: OpaquePointer!, tagType: mpd_tag_type) -> (String, String)? {
        let mpd_pair = mpd_recv_pair_tag(connection, tagType)
        
        guard let pointee = mpd_pair?.pointee else {
            return nil
        }
        
        defer {
            mpd_return_pair(connection, mpd_pair)
        }

        return (stringFromMPDString(pointee.name), stringFromMPDString(pointee.value))
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
