//
//  StatusManager.swift
//  MPDConnector
//
//  Created by Berrie Kremers on 05-08-17.
//  Copyright © 2017 Kaotemba Software. All rights reserved.
//

import Foundation
import ConnectorProtocol
import libmpdclient

public class MPDPlayer: PlayerProtocol {
    private var host: String
    private var port: Int
    private var password: String
    private var connectedHandler: ((_ player: MPDPlayer) -> Void)?
    private var disconnectedHandler: ((_ player: MPDPlayer, _ errorNumber: Int, _ errorMessage: String) -> Void)?
    
    /// Connection to a MPD Player
    private let mpd: MPDProtocol
    
    /// Current connection status
    public var connectionStatus = ConnectionStatus.Disconnected
    
    private var mpdController: MPDController
    public var controller: ControlProtocol {
        return mpdController
    }
    
    public var uniqueID: String {
        get {
            return "mpd:\(host):\(port)"
        }
    }
    
    public var connectionProperties: [String: Any] {
        get {
            return ["host": host, "port": port, "password": password]
        }
    }

    // MARK: - Initialization and connecting
    
    /// Initialize a new player object
    ///
    /// - Parameters:
    ///   - host: Host ip-address to connect to.
    ///   - port: Port to connect to.
    ///   - password: Password to use when connection, default is ""
    ///   - connectedHandler: Optional handler that is called when a successful (re)connection is made
    ///   - disconnectedHandler: Optional handler that is called when a connection can't be made or is lost
    public init(mpd: MPDProtocol? = nil,
                host: String, port: Int, password: String = "",
                connectedHandler: ((_ player: MPDPlayer) -> Void)? = nil,
                disconnectedHandler: ((_ player: MPDPlayer, _ errorNumber: Int, _ errorMessage: String) -> Void)? = nil) {
        self.mpd = mpd ?? MPDWrapper()
        self.host = host
        self.port = port
        self.password = password
        self.connectedHandler = connectedHandler
        self.disconnectedHandler = disconnectedHandler
        self.mpdController = MPDController.init(mpd: self.mpd,
                                                connection: nil,
                                                disconnectedHandler: nil)
        
        self.mpdController.disconnectedHandler = { [weak self] (connection, error) in
            if [MPD_ERROR_TIMEOUT, MPD_ERROR_SYSTEM, MPD_ERROR_RESOLVER, MPD_ERROR_MALFORMED, MPD_ERROR_CLOSED].contains(error) {
                self?.connectionStatus = .Disconnected
                
                DispatchQueue.main.async {
                    let errorNumber = Int((self?.mpd.connection_get_error(connection).rawValue)!)
                    let errorMessage = self?.mpd.connection_get_error_message(connection)
                    
                    if let disconnectedHandler = self?.disconnectedHandler  {
                        disconnectedHandler(self!, errorNumber, errorMessage!)
                    }
                    let notification = Notification.init(name: NSNotification.Name.init(ConnectionStatusChangeNotification.Disconnected.rawValue), object: nil, userInfo: ["player": self!])
                    NotificationCenter.default.post(notification)
                    
                    self?.mpd.connection_free(connection)
                }
            }
        }
    }
    
    // MARK: - PlayerProtocol Implementations

    /// Attempt to (re)connect based on the internal variables. When successful an internal connection object will be set.
    ///
    /// - Parameter numberOfTries: Number of times to try connection, default = 3.
    public func connect(numberOfTries: Int = 3) {
        guard connectionStatus == .Disconnected else {
            return
        }

        self.connectionStatus = .Connecting
        DispatchQueue.global(qos: .background).async {
            var connection: OpaquePointer? = nil
            var actualTries = 0
            while actualTries < numberOfTries {
                if connection != nil {
                    self.mpd.connection_free(connection)
                }

                connection = self.connect(host: self.host, port: self.port, password: self.password)
                if connection != nil {
                    if self.mpd.connection_get_error(connection) == MPD_ERROR_SUCCESS {
                        // Successfully connected, call connectedHandler.
                        DispatchQueue.main.async {
                            
                            self.connectionStatus = .Connected
                            self.mpdController.connection = connection
                            if let connectedHandler = self.connectedHandler  {
                                connectedHandler(self)
                            }
                            
                            let notification = Notification.init(name: NSNotification.Name.init(ConnectionStatusChangeNotification.Connected.rawValue), object: nil, userInfo: ["player": self])
                            NotificationCenter.default.post(notification)
                        }
                        return
                    }
                }
                actualTries += 1
            }
            
            // Didn't manage to connect after <numberOfTries>, call disconnectedHandler.
            DispatchQueue.main.async {
                self.connectionStatus = .Disconnected

                if let disconnectedHandler = self.disconnectedHandler  {
                    disconnectedHandler(self, Int(self.mpd.connection_get_error(connection).rawValue), self.mpd.connection_get_error_message(connection))
                }
                let notification = Notification.init(name: NSNotification.Name.init(ConnectionStatusChangeNotification.Disconnected.rawValue), object: nil, userInfo: ["player": self])
                NotificationCenter.default.post(notification)

                if connection != nil {
                    self.mpd.connection_free(connection)
                }
            }
        }
    }

    /// Connect to a MPD Player
    ///
    /// - Parameters:
    ///   - host: Host ip-address to connect to.
    ///   - port: Port to connect to.
    ///   - password: Password to use after connecting, default = "".
    /// - Returns: A mpd_connection object.
    private func connect(host: String, port: Int, password: String = "") -> OpaquePointer? {
        let connection = self.mpd.connection_new(host, UInt32(port), 1000)
        if self.mpd.connection_get_error(connection) == MPD_ERROR_SUCCESS {
            if password != "" {
                _ = self.mpd.run_password(connection, password: password)
            }
        }
        
        return connection
    }
}
