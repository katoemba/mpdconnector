//
//  PlayerManager.swift
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
#if os(iOS)
import UIKit
#endif
import ConnectorProtocol
import SWXMLHash
import MPDConnector
import SwiftMPD

enum MPDError: Error {
    case invalidData
}

/// Class to monitor mpdPlayers appearing and disappearing from the network.
public class MPDPlayerBrowser: PlayerBrowserProtocol {
    struct MPDConnectionData {
        let name: String
        let host: String
        let ip: String?
        let port: Int
        let type: MPDType
        
        func withType(_ newType: MPDType) -> MPDConnectionData {
            MPDConnectionData(name: name, host: host, ip: ip, port: port, type: newType)
        }

        func withPortAndType(_ newPort: Int, _ newType: MPDType) -> MPDConnectionData {
            MPDConnectionData(name: name, host: host, ip: ip, port: newPort, type: newType)
        }

        func withNameAndPortAndType(_ newName: String, _ newPort: Int, _ newType: MPDType) -> MPDConnectionData {
            MPDConnectionData(name: newName, host: host, ip: ip, port: newPort, type: newType)
        }
    }
    
    public var controllerType: String {
        MPDPlayer.controllerType
    }
    private let mpdNetServiceBrowser : NetServiceBrowser
    private let volumioNetServiceBrowser : NetServiceBrowser
    private let httpNetServiceBrowser : NetServiceBrowser
    
    private var isListening = false
    private var userDefaults: UserDefaults
    
    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
        mpdNetServiceBrowser = NetServiceBrowser()
        volumioNetServiceBrowser = NetServiceBrowser()
        httpNetServiceBrowser = NetServiceBrowser()
    }
    
    /// Start listening for players on the local domain.
    public func startListening() {
        guard isListening == false else {
            return
        }
        
        isListening = true
        mpdNetServiceBrowser.searchForServices(ofType: "_mpd._tcp.", inDomain: "")
        volumioNetServiceBrowser.searchForServices(ofType: "_Volumio._tcp.", inDomain: "")
        httpNetServiceBrowser.searchForServices(ofType: "_http._tcp.", inDomain: "")
        
        let persistedPlayers = userDefaults.dictionary(forKey: "mpd.browser.manualplayers") ?? [String: [String: Any]]()
        for persistedPlayer in persistedPlayers.keys {
        }
    }
    
    /// Stop listening for players.
    public func stopListening() {
        guard isListening == true else {
            return
        }
        
        isListening = false
        mpdNetServiceBrowser.stop()
        volumioNetServiceBrowser.stop()
        httpNetServiceBrowser.stop()
        
#if os(iOS)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard UIApplication.shared.applicationState != .active else {
                return
            }
        }
#endif
    }
    
    /// Manually create a player based on the connection properties
    ///
    /// - Parameter connectionProperties: dictionary of connection properties
    /// - Returns: An observable on which a created Player can published.
    public func playerForConnectionProperties(_ connectionProperties: [String: Any]) async throws -> PlayerProtocol {
        guard connectionProperties[ConnectionProperties.controllerType.rawValue] as? String == MPDPlayer.controllerType,
              MPDHelper.hostToUse(connectionProperties) != "",
              let port = connectionProperties[ConnectionProperties.port.rawValue] as? Int else { throw MPDError.invalidData }

        let userDefaults = self.userDefaults
        let hostToUse = MPDHelper.hostToUse(connectionProperties)
        try await SwiftMPD.MPDConnector(.init(ipAddress: hostToUse, port: port, connectTimeout: 3, uuid: UUID(), playerName: connectionProperties[ConnectionProperties.name.rawValue] as? String ?? "Unknown")).connect()
        
        return await MPDPlayer(connectionProperties: connectionProperties, userDefaults: userDefaults)
    }
    
    public func persistPlayer(_ connectionProperties: [String: Any]) {
        guard connectionProperties[ConnectionProperties.controllerType.rawValue] as? String == MPDPlayer.controllerType else { return }
        
        var persistedPlayers = userDefaults.dictionary(forKey: "mpd.browser.manualplayers") ?? [String: [String: Any]]()
        
        if persistedPlayers[connectionProperties[ConnectionProperties.name.rawValue] as! String] != nil {
        }
        persistedPlayers[connectionProperties[ConnectionProperties.name.rawValue] as! String] = connectionProperties
        
        userDefaults.set(persistedPlayers, forKey: "mpd.browser.manualplayers")
    }
    
    public func removePlayer(_ player: any PlayerProtocol) {
        guard player.controllerType == MPDPlayer.controllerType else { return }
        
        var persistedPlayers = userDefaults.dictionary(forKey: "mpd.browser.manualplayers") ?? [String: [String: Any]]()
        
        if persistedPlayers[player.name] != nil {
            persistedPlayers.removeValue(forKey: player.name)
            userDefaults.set(persistedPlayers, forKey: "mpd.browser.manualplayers")
        }
    }
}
