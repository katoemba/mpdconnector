//
//  MPDProtocol.swift
//  MPDConnector
//
//  Created by Berrie Kremers on 09-08-17.
//  Copyright © 2017 Kaotemba Software. All rights reserved.
//

import Foundation
import libmpdclient

/// MPDProtocol created to support unit testing on the MPDPlayer object.
public protocol MPDProtocol {
    func connection_new(_ host: UnsafePointer<Int8>!, _ port: UInt32, _ timeout_ms: UInt32) -> OpaquePointer!
    func connection_free(_ connection: OpaquePointer!)
    func connection_get_error(_ connection: OpaquePointer!) -> mpd_error
    func connection_get_error_message(_ connection: OpaquePointer!) -> String
    func connection_get_server_error(_ connection: OpaquePointer!) -> mpd_server_error
    func run_password(_ connection: OpaquePointer!, password: UnsafePointer<Int8>!) -> Bool
    func run_play(_ connection: OpaquePointer!) -> Bool
    func run_pause(_ connection: OpaquePointer!, _ mode: Bool) -> Bool
    func run_toggle_pause(_ connection: OpaquePointer!) -> Bool
    func run_next(_ connection: OpaquePointer!) -> Bool
    func run_previous(_ connection: OpaquePointer!) -> Bool
    func run_random(_ connection: OpaquePointer!, _ mode: Bool) -> Bool
    func run_repeat(_ connection: OpaquePointer!, _ mode: Bool) -> Bool
    func run_set_volume(_ connection: OpaquePointer!, _ volume: UInt32) -> Bool
    func run_status(_ connection: OpaquePointer!) -> OpaquePointer!
    func status_free(_ status: OpaquePointer!)
    func run_current_song(_ connection: OpaquePointer!) -> OpaquePointer!
    func song_free(_ song: OpaquePointer!)
    func status_get_volume(_ status: OpaquePointer!) -> Int32
    func status_get_repeat(_ status: OpaquePointer!) -> Bool
    func status_get_random(_ status: OpaquePointer!) -> Bool
    func status_get_state(_ status: OpaquePointer!) -> mpd_state
    func status_get_elapsed_time(_ status: OpaquePointer!) -> UInt32
    func status_get_total_time(_ status: OpaquePointer!) -> UInt32
    func song_get_tag(_ song: OpaquePointer!, _ type: mpd_tag_type, _ idx: UInt32) -> String
}
