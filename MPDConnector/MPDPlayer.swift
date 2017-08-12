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

public class MPDPlayer: ControlProtocol, PlayerProtocol {
    private var host: String
    private var port: Int
    private var password: String
    private var connectedHandler: ((_ player: MPDPlayer) -> Void)?
    private var disconnectedHandler: ((_ player: MPDPlayer, _ errorNumber: Int, _ errorMessage: String) -> Void)?
    
    /// Connection to a MPD Player
    private var connection: OpaquePointer? = nil
    private let mpd: MPDProtocol
    
    private var _statusTimer: Timer?

    /// PlayerStatus object for the player
    public var playerStatus = PlayerStatus()
    
    /// Current connection status
    public var connectionStatus = ConnectionStatus.Disconnected
    
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
    ///   - mpd: MPDWrapper object.
    ///   - host: Host ip-address to connect to.
    ///   - port: Port to connect to.
    ///   - password: Password to use when connection, default is ""
    ///   - connectedHandler: Optional handler that is called when a successful (re)connection is made
    ///   - disconnectedHandler: Optional handler that is called when a connection can't be made or is lost
    public init(mpd: MPDProtocol, host: String, port: Int, password: String = "",
                connectedHandler: ((_ player: MPDPlayer) -> Void)? = nil,
                disconnectedHandler: ((_ player: MPDPlayer, _ errorNumber: Int, _ errorMessage: String) -> Void)? = nil) {
        self.mpd = mpd
        self.host = host
        self.port = port
        self.password = password
        self.connectedHandler = connectedHandler
        self.disconnectedHandler = disconnectedHandler
    }
    
    /// Cleanup connection object
    deinit {
        if let connection = self.connection {
            self.mpd.connection_free(connection)
            self.connection = nil
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
                            self.connection = connection
                            self.connectionStatus = .Connected
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
                self.connection = nil
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
    
    /// Validate if the current connection is valid, and if not try to reconnect.
    ///
    /// - Returns: <#return value description#>
    private func validateConnection() -> Bool {
        guard let connection = self.connection else {
            return false
        }
        
        let error = self.mpd.connection_get_error(connection)

        if [MPD_ERROR_TIMEOUT, MPD_ERROR_SYSTEM, MPD_ERROR_RESOLVER, MPD_ERROR_MALFORMED, MPD_ERROR_CLOSED].contains(error) {
            self.connectionStatus = .Disconnected
            if let disconnectedHandler = self.disconnectedHandler  {
                disconnectedHandler(self, Int(self.mpd.connection_get_error(connection).rawValue), self.mpd.connection_get_error_message(connection))
            }
            let notification = Notification.init(name: NSNotification.Name.init(ConnectionStatusChangeNotification.Disconnected.rawValue), object: nil, userInfo: ["player": self])
            NotificationCenter.default.post(notification)

            self.mpd.connection_free(connection)
            self.connection = nil

            return false
        }
        
        return true
    }

    /// Start listening for status updates on a regular interval (every second). This will also perform an immediate fetchStatus.
    public func startListeningForStatusUpdates() {
        // Start a statusUpdate timer only once
        guard self._statusTimer == nil else {
            return
        }

        self.playerStatus = PlayerStatus()
        self.fetchStatus()
        _statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0 , repeats: true, block: { (timer) in
            self.fetchStatus()
        })
    }

    /// Stop listening for status updates. Must be called before nilling a MPDPlayer object to prevent retain cycles.
    public func stopListeningForStatusUpdates() {
        guard let timer = self._statusTimer else {
            return
        }
        
        timer.invalidate()
        _statusTimer = nil
    }

    // MARK: - ControlProtocol Implementations

    /// Start playback.
    public func play() {
        guard validateConnection() else {
            return
        }
        
        _ = self.mpd.run_play(connection)
        fetchStatus()
    }
    
    /// Start playback.
    public func pause() {
        guard validateConnection() else {
            return
        }

        _ = self.mpd.run_pause(connection, true)
        fetchStatus()
    }
    
    /// Toggle between play and pause: when paused -> start to play, when playing -> pause.
    public func togglePlayPause() {
        guard validateConnection() else {
            return
        }
        _ = self.mpd.run_toggle_pause(connection)
        fetchStatus()
    }
    
    /// Skip to the next track.
    public func skip() {
        guard validateConnection() else {
            return
        }

        _ = self.mpd.run_next(connection)
        fetchStatus()
    }
    
    /// Go back to the previous track.
    public func back() {
        guard validateConnection() else {
            return
        }

        _ = self.mpd.run_previous(connection)
        fetchStatus()
    }
    
    /// Set the shuffle mode of the player.
    ///
    /// - Parameter shuffleMode: The shuffle mode to use.
    public func setShuffle(shuffleMode: ShuffleMode) {
        guard validateConnection() else {
            return
        }

        _ = self.mpd.run_random(connection, (shuffleMode == .On) ? true : false)
        fetchStatus()
    }
    
    /// Set the repeat mode of the player.
    ///
    /// - Parameter repeatMode: The repeat mode to use.
    public func setRepeat(repeatMode: RepeatMode) {
        guard validateConnection() else {
            return
        }

        _ = self.mpd.run_repeat(connection, (repeatMode == .Off) ? false : true)
        fetchStatus()
    }
    
    /// Set the volume of the player.((shuffleMode == .On)?,true:false)
    ///
    /// - Parameter volume: The volume to set. Must be a value between 0.0 and 1.0, values outside this range will be ignored.
    public func setVolume(volume: Float) {
        guard volume >= 0.0, volume <= 1.0 else {
            return
        }
        
        guard validateConnection() else {
            return
        }

        _ = self.mpd.run_set_volume(connection, UInt32(roundf(volume * 100.0)))
        fetchStatus()
    }
    
    /// Retrieve the status from the player and fill all relevant elements in the playerStatus object
    public func fetchStatus() {
        guard validateConnection() else {
            return
        }

        playerStatus.beginUpdate()
        
        if let status = self.mpd.run_status(connection) {
            defer {
                self.mpd.status_free(status)
            }

            playerStatus.volume = Float(self.mpd.status_get_volume(status)) / 100.0
            playerStatus.elapsedTime = Int(self.mpd.status_get_elapsed_time(status))
            playerStatus.trackTime = Int(self.mpd.status_get_total_time(status))
            
            playerStatus.playingStatus = (self.mpd.status_get_state(status) == MPD_STATE_PLAY) ? .Playing : .Paused
            playerStatus.shuffleMode = (self.mpd.status_get_random(status) == true) ? .On : .Off
            playerStatus.repeatMode = (self.mpd.status_get_repeat(status) == true) ? .All : .Off
        }
        
        if let song = self.mpd.run_current_song(connection) {
            defer {
                self.mpd.song_free(song)
            }

            playerStatus.song = self.mpd.song_get_tag(song, MPD_TAG_TITLE, 0)
            playerStatus.album = self.mpd.song_get_tag(song, MPD_TAG_ALBUM, 0)
            playerStatus.artist = self.mpd.song_get_tag(song, MPD_TAG_ARTIST, 0)
        }
        
        playerStatus.endUpdate()
    }
}
