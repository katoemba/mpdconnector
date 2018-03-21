//
//  MPDProtocol.swift
//  MPDConnector
//
//  Created by Berrie Kremers on 09-08-17.
//  Copyright © 2017 Katoemba Software. All rights reserved.
//

import Foundation
import libmpdclient

enum MPDError: Error {
    case commandFailed
    case noDataFound
}

/// MPDProtocol created to support unit testing on the MPDPlayer object.
public protocol MPDProtocol {
    func connection_new(_ host: UnsafePointer<Int8>!, _ port: UInt32, _ timeout_ms: UInt32) -> OpaquePointer!
    func connection_free(_ connection: OpaquePointer!)
    func connection_get_error(_ connection: OpaquePointer!) -> mpd_error
    func connection_get_error_message(_ connection: OpaquePointer!) -> String
    func connection_get_server_error(_ connection: OpaquePointer!) -> mpd_server_error
    func connection_clear_error(_ connection: OpaquePointer!) -> Bool
    func run_password(_ connection: OpaquePointer!, password: UnsafePointer<Int8>!) -> Bool
    func run_play(_ connection: OpaquePointer!) -> Bool
    func run_play_pos(_ connection: OpaquePointer!, _ song_pos: UInt32) -> Bool
    func run_pause(_ connection: OpaquePointer!, _ mode: Bool) -> Bool
    func run_toggle_pause(_ connection: OpaquePointer!) -> Bool
    func run_next(_ connection: OpaquePointer!) -> Bool
    func run_previous(_ connection: OpaquePointer!) -> Bool
    func run_random(_ connection: OpaquePointer!, _ mode: Bool) -> Bool
    func run_shuffle(_ connection: OpaquePointer!) -> Bool
    func run_repeat(_ connection: OpaquePointer!, _ mode: Bool) -> Bool
    func run_single(_ connection: OpaquePointer!, _ mode: Bool) -> Bool
    func run_set_volume(_ connection: OpaquePointer!, _ volume: UInt32) -> Bool
    func run_status(_ connection: OpaquePointer!) -> OpaquePointer!
    func status_free(_ status: OpaquePointer!)
    func run_current_song(_ connection: OpaquePointer!) -> OpaquePointer!
    func song_free(_ song: OpaquePointer!)
    func status_get_volume(_ status: OpaquePointer!) -> Int32
    func status_get_repeat(_ status: OpaquePointer!) -> Bool
    func status_get_single(_ status: OpaquePointer!) -> Bool
    func status_get_random(_ status: OpaquePointer!) -> Bool
    func status_get_state(_ status: OpaquePointer!) -> mpd_state
    func status_get_song_pos(_ status: OpaquePointer!) -> Int32
    func status_get_elapsed_time(_ status: OpaquePointer!) -> UInt32
    func status_get_total_time(_ status: OpaquePointer!) -> UInt32
    func status_get_queue_length(_ status: OpaquePointer!) -> UInt32
    func status_get_queue_version(_ status: OpaquePointer!) -> UInt32
    func song_get_tag(_ song: OpaquePointer!, _ type: mpd_tag_type, _ idx: UInt32) -> String
    func song_get_duration(_ song: OpaquePointer!) -> UInt32
    func song_get_uri(_ song: OpaquePointer!) -> String
    func song_get_last_modified(_ song: OpaquePointer!) -> Date
    func send_list_queue_range_meta(_ connection: OpaquePointer!, start: UInt32, end: UInt32) -> Bool
    func recv_song(_ connection: OpaquePointer!) -> OpaquePointer!
    func response_finish(_ connection: OpaquePointer!) -> Bool
    func run_save(_ connection: OpaquePointer!, name: UnsafePointer<Int8>!) -> Bool
    func run_load(_ connection: OpaquePointer!, name: UnsafePointer<Int8>!) -> Bool
    func search_db_songs(_ connection: OpaquePointer!, exact: Bool) throws
    func search_add_db_songs(_ connection: OpaquePointer!, exact: Bool) throws
    func search_db_tags(_ connection: OpaquePointer!, tagType: mpd_tag_type) throws
    func search_add_tag_constraint(_ connection: OpaquePointer!, oper: mpd_operator, tagType: mpd_tag_type, value: UnsafePointer<Int8>!) throws
    func search_add_modified_since_constraint(_ connection: OpaquePointer!, oper: mpd_operator, since: Date) throws
    func search_add_sort_tag(_ connection: OpaquePointer!, tagType: mpd_tag_type) throws
    func search_add_window(_ connection: OpaquePointer!, start: UInt32, end: UInt32) throws
    func search_add_group_tag(_ connection: OpaquePointer!, tagType: mpd_tag_type) throws
    func search_commit(_ connection: OpaquePointer!) throws
    func search_cancel(_ connection: OpaquePointer!)
    func recv_pair_tag(_ connection: OpaquePointer!, tagType: mpd_tag_type) -> (String, String)?
    func run_add(_ connection: OpaquePointer!, uri: UnsafePointer<Int8>!) -> Bool
    func run_add_id_to(_ connection: OpaquePointer!, uri: UnsafePointer<Int8>!, to: UInt32) -> Int32
    func send_add(_ connection: OpaquePointer!, uri: UnsafePointer<Int8>!) -> Bool
    func send_add_id_to(_ connection: OpaquePointer!, uri: UnsafePointer<Int8>!, to: UInt32) -> Bool
    func run_seek(_ connection: OpaquePointer!, pos: UInt32, t: UInt32) -> Bool
    func run_clear(_ connection: OpaquePointer!) -> Bool
    func run_idle_mask(_ connection: OpaquePointer!, mask: mpd_idle) -> mpd_idle
    func send_noidle(_ connection: OpaquePointer!) -> Bool
    func run_move(_ connection: OpaquePointer!, from: UInt32, to: UInt32) -> Bool
    func run_delete(_ connection: OpaquePointer!, pos: UInt32) -> Bool
    func send_list_playlists(_ connection: OpaquePointer!) -> Bool
    func recv_playlist(_ connection: OpaquePointer!) -> OpaquePointer!
    func playlist_free(_ playlist: OpaquePointer!)
    func playlist_get_path(_ playlist: OpaquePointer!) -> String
    func playlist_get_last_modified(_ playlist: OpaquePointer!) -> Date
    func send_list_playlist_meta(_ connection: OpaquePointer!, name: UnsafePointer<Int8>!) -> Bool
    func run_rename(_ connection: OpaquePointer!, from: UnsafePointer<Int8>!, to: UnsafePointer<Int8>!) -> Bool
    func command_list_begin(_ connection: OpaquePointer!, discrete_ok: Bool) -> Bool
    func command_list_end(_ connection: OpaquePointer!) -> Bool
    func run_rm(_ connection: OpaquePointer!, name: UnsafePointer<Int8>!) -> Bool
}
