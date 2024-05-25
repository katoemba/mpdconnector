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
    public var stopUsing = false
    
    private var uniqueId = UUID()
    private var host: String
    private var port: Int
    private var prio: Priority
    private let forceCleanup: Bool
    
    init(mpd: MPDProtocol, host: String, port: Int, timeout: Int, prio: Priority = .high, forceCleanup: Bool = false) {
        self.mpd = mpd
        self.host = host
        self.port = port
        self.prio = prio
        self.forceCleanup = forceCleanup
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
            if let connection = weakConnection.value, connection.forceCleanup == true {
                connection.disconnect()
            }
        }
        
        Self.playerSemaphoreMutex.wait()
        connections.removeAll()
        Self.playerSemaphoreMutex.signal()
    }
    
    func disconnect() {
        if let connection = _connection {
            stopUsing = true
        
            _connection = nil
            mpd.connection_free(connection)
            //MPDConnection.released(prio: prio)
        }
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
    public static func connect(mpd: MPDProtocol, host: String, port: Int, password: String, timeout: Int = 5000, prio: MPDConnection.Priority = .high, forceCleanup: Bool = false) -> MPDConnection? {
        if Thread.current.isMainThread {
            print("Warning: connecting to MPD on the main thread could cause blocking")
        }
        
        let mpdConnection = MPDConnection(mpd: mpd, host: host, port: port, timeout: timeout, prio: prio, forceCleanup: forceCleanup)
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
    public static func connect(mpd: MPDProtocol, connectionProperties: [String: Any], timeout: Int = 5000, prio: MPDConnection.Priority = .high, forceCleanup: Bool = false) -> MPDConnection? {
        return connect(mpd: mpd,
                       host: hostToUse(connectionProperties),
                       port: connectionProperties[ConnectionProperties.port.rawValue] as! Int,
                       password: connectionProperties[ConnectionProperties.password.rawValue] as! String,
                       timeout: timeout,
                       prio: prio,
                       forceCleanup: forceCleanup)
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
