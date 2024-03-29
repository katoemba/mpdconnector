//
//  MPDWrapper.swift
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
import ConnectorProtocol
import libmpdclient

/// The functions provided by MPDWrapper will directly call the matching mpd_xxx function. The only conversion
/// that takes places is from UnsafePointer<Int8> to String for return values.
public class MPDWrapper: MPDProtocol {
    public init() {
        HelpMePlease.allocUp(name: "MPDWrapper")
    }
    
    deinit {
        HelpMePlease.allocDown(name: "MPDWrapper")
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
    
    public func run_stop(_ connection: OpaquePointer!) -> Bool {
        return mpd_run_stop(connection)
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
    
    public func run_consume(_ connection: OpaquePointer!, _ mode: Bool) -> Bool {
        return mpd_run_consume(connection, mode)
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
    
    public func status_get_consume(_ status: OpaquePointer!) -> Bool {
        return mpd_status_get_consume(status)
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
    
    public func status_get_kbit_rate(_ status: OpaquePointer!) -> UInt32 {
        return mpd_status_get_kbit_rate(status)
    }
    
    public func status_get_audio_format(_ status: OpaquePointer!) -> (UInt32, UInt8, UInt8)? {
        if let audio_format = mpd_status_get_audio_format(status) {
            return ((audio_format.pointee.sample_rate, audio_format.pointee.bits, audio_format.pointee.channels))
        }
        else {
            return ((0, 0, 0))
        }
    }

    public func status_get_update_id(_ status: OpaquePointer!) -> UInt32 {
        return mpd_status_get_update_id(status)
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
    
    public func song_get_last_modified(_ song: OpaquePointer!) -> Date {
        return dateFromMPDDate(mpd_song_get_last_modified(song))
    }
    
    public func song_get_audio_format(_ song: OpaquePointer!) -> (UInt32, UInt8, UInt8)? {
        if let audio_format = mpd_song_get_audio_format(song) {
            return ((audio_format.pointee.sample_rate, audio_format.pointee.bits, audio_format.pointee.channels))
        }
        
        return nil
    }
    
    public func song_get_id(_ song: OpaquePointer!) -> UInt32 {
        return mpd_song_get_id(song)
    }

    public func send_list_queue_range_meta(_ connection: OpaquePointer!, start: UInt32, end: UInt32) -> Bool {
        return mpd_send_list_queue_range_meta(connection, start, end)
    }
    
    public func send_list_queue_meta(_ connection: OpaquePointer!) -> Bool {
        return mpd_send_list_queue_meta(connection)
    }
    
    public func run_get_queue_song_pos(_ connection: OpaquePointer!, pos: UInt32) -> OpaquePointer! {
        return mpd_run_get_queue_song_pos(connection, pos)
    }
    
    public func run_get_queue_song_id(_ connection: OpaquePointer!, id: UInt32) -> OpaquePointer! {
        return mpd_run_get_queue_song_id(connection, id)
    }
    
    public func send_queue_changes_meta(_ connection: OpaquePointer!, version: UInt32) -> Bool {
        return mpd_send_queue_changes_meta(connection, version)
    }
    
    public func send_queue_changes_meta_range(_ connection: OpaquePointer!, version: UInt32, start: UInt32, end: UInt32) -> Bool {
        return mpd_send_queue_changes_meta_range(connection, version, start, end)
    }
    
    public func recv_song(_ connection: OpaquePointer!) -> OpaquePointer! {
        return mpd_recv_song(connection)
    }
    
    public func send_queue_changes_brief(_ connection: OpaquePointer!, version: UInt32) -> Bool {
        return mpd_send_queue_changes_brief(connection, version)
    }
    
    public func send_queue_changes_brief_range(_ connection: OpaquePointer!, version: UInt32, start: UInt32, end: UInt32) -> Bool {
        return mpd_send_queue_changes_brief_range(connection, version, start, end)
    }
    
    public func recv_queue_change_brief(_ connection: OpaquePointer!) -> (UInt32, UInt32)? {
        let posPointer = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
        posPointer.initialize(repeating: 0, count: 1)
        defer {
            posPointer.deinitialize(count: 1)
            posPointer.deallocate()
        }
        let idPointer = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
        idPointer.initialize(repeating: 0, count: 1)
        defer {
            idPointer.deinitialize(count: 1)
            idPointer.deallocate()
        }
        
        if mpd_recv_queue_change_brief(connection, posPointer, idPointer) {
            return (posPointer.pointee, idPointer.pointee)
        }
        return nil
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
    
    public func run_playlist_add(_ connection: OpaquePointer!, name: UnsafePointer<Int8>!, path: UnsafePointer<Int8>!) -> Bool {
        return mpd_run_playlist_add(connection, name, path)
    }
    
    public func search_db_songs(_ connection: OpaquePointer!, exact: Bool) throws {
        if mpd_search_db_songs(connection, exact) == false {
            throw MPDError.commandFailed
        }
    }
    
    public func search_add_db_songs(_ connection: OpaquePointer!, exact: Bool) throws {
        if mpd_search_add_db_songs(connection, exact) == false {
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
    
    public func search_add_modified_since_constraint(_ connection: OpaquePointer!, oper: mpd_operator, since: Date) throws {
        //Int(Date(timeIntervalSinceNow: -180 * 24 * 60 * 60).timeIntervalSince1970)
        if mpd_search_add_modified_since_constraint(connection, oper, time_t(since.timeIntervalSince1970)) == false || mpd_connection_get_error(connection) != MPD_ERROR_SUCCESS {
            throw MPDError.commandFailed
        }
    }

    public func search_add_sort_tag(_ connection: OpaquePointer!, tagType: mpd_tag_type, descending: Bool) throws {
        if mpd_search_add_sort_tag(connection, tagType, descending) == false || mpd_connection_get_error(connection) != MPD_ERROR_SUCCESS {
            throw MPDError.commandFailed
        }
    }
    
    public func search_add_sort_name(_ connection: OpaquePointer!, name: UnsafePointer<Int8>!, descending: Bool) throws {
        if mpd_search_add_sort_name(connection, name, descending) == false || mpd_connection_get_error(connection) != MPD_ERROR_SUCCESS {
            throw MPDError.commandFailed
        }
    }
    
    public func search_add_window(_ connection: OpaquePointer!, start: UInt32, end: UInt32) throws {
        if mpd_search_add_window(connection, start, end) == false || mpd_connection_get_error(connection) != MPD_ERROR_SUCCESS {
            throw MPDError.commandFailed
        }
    }
    
    public func search_add_group_tag(_ connection: OpaquePointer!, tagType: mpd_tag_type) throws {
        if mpd_search_add_group_tag(connection, tagType) == false || mpd_connection_get_error(connection) != MPD_ERROR_SUCCESS {
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
    
    public func send_list_tag_types(_ connection: OpaquePointer!) -> Bool {
        return mpd_send_list_tag_types(connection)
    }
    
    public func send_allowed_commands(_ connection: OpaquePointer!) -> Bool {
        return mpd_send_allowed_commands(connection)
    }
    
    public func recv_tag_type_pair(_ connection: OpaquePointer!) -> (String, String)? {
        let mpd_pair = mpd_recv_tag_type_pair(connection)
        
        guard let pointee = mpd_pair?.pointee else {
            return nil
        }
        
        defer {
            mpd_return_pair(connection, mpd_pair)
        }
        
        return (stringFromMPDString(pointee.name), stringFromMPDString(pointee.value))
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
    
    public func recv_pair_named(_ connection: OpaquePointer!, name: UnsafePointer<Int8>!) -> (String, String)? {
        let mpd_pair = mpd_recv_pair_named(connection, name)
        
        guard let pointee = mpd_pair?.pointee else {
            return nil
        }
        
        defer {
            mpd_return_pair(connection, mpd_pair)
        }

        return (stringFromMPDString(pointee.name), stringFromMPDString(pointee.value))
    }
    
    public func recv_pair(_ connection: OpaquePointer!) -> (String, String)? {
        let mpd_pair = mpd_recv_pair(connection)
        
        guard let pointee = mpd_pair?.pointee else {
            return nil
        }
        
        defer {
            mpd_return_pair(connection, mpd_pair)
        }
        
        return (stringFromMPDString(pointee.name), stringFromMPDString(pointee.value))
    }
    
    public func recv_binary(_ connection: OpaquePointer!, length: UInt32) -> Data? {
        guard let data = malloc(Int(length)) else { return nil }
        
        defer {
            free(data)
        }
        if mpd_recv_binary(connection, data, Int(length)) {
            return Data(bytes: data, count: Int(length))
        }
        
        return nil
    }
    
    public func tag_name_parse(_ name: UnsafePointer<Int8>!) -> mpd_tag_type {
        return mpd_tag_name_parse(name)
    }
    
    public func tag_name(tagType: mpd_tag_type) -> String {
        return stringFromMPDString(mpd_tag_name(tagType))
    }
    
    public func send_list_all(_ connection: OpaquePointer!, path: UnsafePointer<Int8>!) -> Bool {
        return mpd_send_list_all(connection, path)
    }
    
    public func send_list_meta(_ connection: OpaquePointer!, path: UnsafePointer<Int8>!) -> Bool {
        return mpd_send_list_meta(connection, path)
    }
    
    public func send_list_files(_ connection: OpaquePointer!, path: UnsafePointer<Int8>!) -> Bool {
        return mpd_send_list_files(connection, path)
    }

    public func recv_entity(_ connection: OpaquePointer!) -> OpaquePointer! {
        return mpd_recv_entity(connection)
    }
    
    public func entity_get_type(_ entity: OpaquePointer!) -> mpd_entity_type {
        return mpd_entity_get_type(entity)
    }
    
    public func entity_get_directory(_ entity: OpaquePointer!) -> OpaquePointer! {
        return mpd_entity_get_directory(entity)
    }
    
    public func entity_get_song(_ entity: OpaquePointer!) -> OpaquePointer! {
        return mpd_entity_get_song(entity)
    }
    
    public func entity_get_playlist(_ entity: OpaquePointer!) -> OpaquePointer! {
        return mpd_entity_get_playlist(entity)
    }
    
    public func entity_free(_ entity: OpaquePointer!) {
        mpd_entity_free(entity)
    }
    
    public func directory_get_path(_ directory: OpaquePointer!) -> String {
        return stringFromMPDString(mpd_directory_get_path(directory))
    }
    
    public func directory_free(_ directory: OpaquePointer!) {
        mpd_directory_free(directory)
    }
    
    public func run_add(_ connection: OpaquePointer!, uri: UnsafePointer<Int8>!) -> Bool {
        return mpd_run_add(connection, uri)
    }
    
    public func run_add_id_to(_ connection: OpaquePointer!, uri: UnsafePointer<Int8>!, to: UInt32) -> Int32 {
        return mpd_run_add_id_to(connection, uri, to)
    }
    
    public func send_add(_ connection: OpaquePointer!, uri: UnsafePointer<Int8>!) -> Bool {
        return mpd_send_add(connection, uri)
    }
    
    public func send_add_id_to(_ connection: OpaquePointer!, uri: UnsafePointer<Int8>!, to: UInt32) -> Bool {
        return mpd_send_add_id_to(connection, uri, to)
    }
    
    public func run_clear(_ connection: OpaquePointer!) -> Bool {
        return mpd_run_clear(connection)
    }
    
    public func run_idle_mask(_ connection: OpaquePointer!, mask: mpd_idle) -> mpd_idle {
        return mpd_run_idle_mask(connection, mask)
    }

    public func send_noidle(_ connection: OpaquePointer!) -> Bool {
        return mpd_send_noidle(connection)
    }

    public func run_move(_ connection: OpaquePointer!, from: UInt32, to: UInt32) -> Bool {
        return mpd_run_move(connection, from, to)
    }
    
    public func run_move_range(_ connection: OpaquePointer!, start: UInt32, end: UInt32, to: UInt32) -> Bool {
        return mpd_run_move_range(connection, start, end, to)
    }
    
    public func run_delete(_ connection: OpaquePointer!, pos: UInt32) -> Bool {
        return mpd_run_delete(connection, pos)
    }
    
    public func run_seek(_ connection: OpaquePointer!, pos: UInt32, t: UInt32) -> Bool {
        return mpd_run_seek_pos(connection, pos, t)
    }
    
    public func send_list_playlists(_ connection: OpaquePointer!) -> Bool {
        return mpd_send_list_playlists(connection)
    }
    
    public func recv_playlist(_ connection: OpaquePointer!) -> OpaquePointer! {
        return mpd_recv_playlist(connection)
    }
    
    public func playlist_free(_ playlist: OpaquePointer!) {
        mpd_playlist_free(playlist)
    }
    
    public func playlist_get_path(_ playlist: OpaquePointer!) -> String {
        return stringFromMPDString(mpd_playlist_get_path(playlist))
    }
    
    public func playlist_get_last_modified(_ playlist: OpaquePointer!) -> Date {
        return dateFromMPDDate(mpd_playlist_get_last_modified(playlist))
    }
    
    public func send_list_playlist_meta(_ connection: OpaquePointer!, name: UnsafePointer<Int8>!) -> Bool {
        return mpd_send_list_playlist_meta(connection, name)
    }
    
    public func run_rename(_ connection: OpaquePointer!, from: UnsafePointer<Int8>!, to: UnsafePointer<Int8>!) -> Bool {
        return mpd_run_rename(connection, from, to)
    }
    
    public func run_playlist_move(_ connection: OpaquePointer!, name: UnsafePointer<Int8>!, from: UInt32, to: UInt32) -> Bool {
        return mpd_run_playlist_move(connection, name, from, to)
    }
    
    public func run_playlist_delete(_ connection: OpaquePointer!, name: UnsafePointer<Int8>!, pos: UInt32) -> Bool {
        return mpd_run_playlist_delete(connection, name, pos)
    }

    public func run_rm(_ connection: OpaquePointer!, name: UnsafePointer<Int8>!) -> Bool {
        return mpd_run_rm(connection, name)
    }
    
    public func command_list_begin(_ connection: OpaquePointer!, discrete_ok: Bool) -> Bool {
        return mpd_command_list_begin(connection, discrete_ok)
    }
    
    public func command_list_end(_ connection: OpaquePointer!) -> Bool {
        return mpd_command_list_end(connection)
    }
    
    public func send_s_u_command(_ connection: OpaquePointer!, command: UnsafePointer<Int8>!, arg1: UnsafePointer<Int8>!, arg2: UInt32) -> Bool {
        return mpd_send_s_u_command(connection, command, arg1, arg2)
    }
    
    public func run_update(_ connection: OpaquePointer!, path: UnsafePointer<Int8>!) -> UInt32 {
        return mpd_run_update(connection, path)
    }
    
    public func run_stats(_ connection: OpaquePointer!) -> OpaquePointer! {
        return mpd_run_stats(connection)
    }

    public func stats_free(_ stats: OpaquePointer!) {
        mpd_stats_free(stats)
    }
    
    public func stats_get_db_update_time(_ stats: OpaquePointer!) -> Date {
        return dateFromMPDDate(time_t(mpd_stats_get_db_update_time(stats)))
    }

    public func connection_get_server_version(_ connection: OpaquePointer!) -> String {
        if let tripleTuple = mpd_connection_get_server_version(connection) {
            return "\(tripleTuple[0]).\(tripleTuple[1]).\(tripleTuple[2])"
        }
        else {
            return "0.0.0"
        }
    }
    
    public func run_enable_output(_ connection: OpaquePointer!, output_id: UInt32) -> Bool {
        return mpd_run_enable_output(connection, output_id)
    }
    
    public func run_disable_output(_ connection: OpaquePointer!, output_id: UInt32) -> Bool {
        return mpd_run_disable_output(connection, output_id)
    }
    
    public func run_toggle_output(_ connection: OpaquePointer!, output_id: UInt32) -> Bool {
        return mpd_run_toggle_output(connection, output_id)
    }
    
    public func send_outputs(_ connection: OpaquePointer!) -> Bool {
        return mpd_send_outputs(connection)
    }
    
    public func recv_output(_ connection: OpaquePointer!) -> OpaquePointer! {
        return mpd_recv_output(connection)
    }
    
    public func output_get_id(_ output: OpaquePointer!) -> UInt32 {
        return mpd_output_get_id(output)
    }
    
    public func output_get_name(_ output: OpaquePointer!) -> String {
        return stringFromMPDString(mpd_output_get_name(output))
    }
    
    public func output_get_enabled(_ output: OpaquePointer!) -> Bool {
        return mpd_output_get_enabled(output)
    }
    
    public func output_free(_ output: OpaquePointer!) {
        mpd_output_free(output)
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
    
    func dateFromMPDDate(_ mpdDate: time_t) -> Date {
        return Date(timeIntervalSince1970: TimeInterval(mpdDate))
    }
}
