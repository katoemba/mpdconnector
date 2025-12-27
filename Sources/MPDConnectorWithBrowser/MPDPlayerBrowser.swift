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
import SwiftUI

enum MPDError: Error {
    case invalidData
}

/// Class to monitor mpdPlayers appearing and disappearing from the network.
@MainActor
public class MPDPlayerBrowser: @preconcurrency PlayerBrowserProtocol {
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
    
    @Published public var players: [any PlayerProtocol] = []
    
    private var isListening = false
    private var userDefaults: UserDefaults
    
    private var mpdBrowser: AsyncServiceBrowser?
    private var httpBrowser: AsyncServiceBrowser?
    private var volumioBrowser: AsyncServiceBrowser?

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }
    
    /// Start listening for players on the local domain.
    public func startListening() {
        guard isListening == false else {
            return
        }
        
        isListening = true
        
        let mpdBrowser = AsyncServiceBrowser()
        self.mpdBrowser = mpdBrowser
        Task {
            for await event in mpdBrowser.discover(type: "_mpd._tcp.") {
                switch event {
                case .found(let service):
                    do {
                        if let player = try await createPlayerFromService(service) {
                            // Only add if not already in the list
                            if !players.contains(where: { $0.name == player.name }) {
                                players.append(player)
                            }
                        }
                    } catch {
                        print("Failed to create player: \(error)")
                    }
                case .removed(let service):
                    // Find and remove player with matching name
                    removePlayerByName(service.name)
                }
            }
        }
        
        let httpBrowser = AsyncServiceBrowser()
        self.httpBrowser = httpBrowser
        Task {
            for await event in httpBrowser.discover(type: "_http._tcp.") {
                switch event {
                case .found(let service):
                    do {
                        if let connectionData = await fetchMoodeConnectionData(from: service) {
                            let connectionProperties = moodeConnectionProperties(from: connectionData)
                            let player = try await playerForConnectionProperties(connectionProperties)
                            if !players.contains(where: { $0.uniqueID == player.uniqueID && $0.controllerType == player.controllerType }) {
                                players.append(player)
                            }
                        }
                        else if let connectionData = await fetchVolumioConnectionData(from: service) {
                            let connectionProperties = volumioConnectionProperties(from: connectionData)
                            let player = try await playerForConnectionProperties(connectionProperties)
                            if !players.contains(where: { $0.uniqueID == player.uniqueID && $0.controllerType == player.controllerType }) {
                                players.append(player)
                            }
                        }
                    } catch {
                        print("Failed to create moOde player: \(error)")
                    }
                case .removed(let service):
                    removePlayerByName(service.name)
                }
            }
        }
        
        let volumioBrowser = AsyncServiceBrowser()
        self.volumioBrowser = volumioBrowser
        Task {
            for await event in volumioBrowser.discover(type: "_Volumio._tcp.") {
                switch event {
                case .found(let service):
                    do {
                        if let player = try await createPlayerFromService(service, portOverwrite: 6600) {
                            // Only add if not already in the list
                            if !players.contains(where: { $0.uniqueID == player.uniqueID && $0.controllerType == player.controllerType }) {
                                players.append(player)
                            }
                        }
                    } catch {
                        print("Failed to create volumio player: \(error)")
                    }
                case .removed(let service):
                    removePlayerByName(service.name)
                }
            }
        }
        
        // Handle manually configured players
        let persistedPlayers = userDefaults.dictionary(forKey: "mpd.browser.manualplayers") ?? [String: [String: Any]]()
        for persistedPlayer in persistedPlayers.keys {
            if let playerProperties = persistedPlayers[persistedPlayer] as? [String: Any] {
                Task {
                    do {
                        let player = try await playerForConnectionProperties(playerProperties)
                        // Only add if not already in the list
                        if !players.contains(where: { $0.name == player.name }) {
                            players.append(player)
                        }
                    } catch {
                        print("Failed to create persisted player \(persistedPlayer): \(error)")
                    }
                }
            }
        }
    }
    
    /// Create a player from a discovered service
    private func createPlayerFromService(_ service: DiscoveredService, portOverwrite: Int? = nil) async throws -> (any PlayerProtocol)? {
        // Create connection properties
        var connectionProperties: [String: Any] = [
            ConnectionProperties.name.rawValue: service.name,
            ConnectionProperties.host.rawValue: service.service.hostName ?? "",
            ConnectionProperties.port.rawValue: portOverwrite ?? service.service.port,
            ConnectionProperties.controllerType.rawValue: MPDPlayer.controllerType,
            MPDConnectionProperties.MPDType.rawValue: MPDType.classic.rawValue
        ]
        if let ipAddress = service.ipAddresses?.first {
            connectionProperties[MPDConnectionProperties.ipAddress.rawValue] = ipAddress
        }
        
        if service.name.lowercased().contains("poly") ||
            service.service.hostName?.lowercased().contains("poly") ?? false ||
            service.name.lowercased().contains("chord") ||
            service.service.hostName?.lowercased().contains("chord") ?? false ||
            service.name.lowercased().contains("2go") ||
            service.service.hostName?.lowercased().contains("2go") ?? false ||
            service.name.lowercased().contains("2 go") ||
            service.service.hostName?.lowercased().contains("2 go") ?? false ||
            service.name.lowercased().contains("hugo") ||
            service.service.hostName?.lowercased().contains("hugo") ?? false {
            connectionProperties[MPDConnectionProperties.MPDType.rawValue] = MPDType.chord.rawValue
        }

        return try await playerForConnectionProperties(connectionProperties)
    }
    
    /// Stop listening for players.
    public func stopListening() {
        guard isListening == true else {
            return
        }
        
        mpdBrowser?.stopListening()
        mpdBrowser = nil
        
        httpBrowser?.stopListening()
        httpBrowser = nil
        
        volumioBrowser?.stopListening()
        volumioBrowser = nil

        isListening = false
    }
    
    /// Manually create a player based on the connection properties
    ///
    /// - Parameter connectionProperties: dictionary of connection properties
    /// - Returns: An observable on which a created Player can published.
    public func playerForConnectionProperties(_ connectionProperties: [String: Any]) async throws -> any PlayerProtocol {
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
    
    private func removePlayerByName(_ name: String) {
        players.removeAll { $0.name == name }
    }

    // MARK: - moOde discovery helpers

    /// Fetch and parse /browserconfig.xml to determine whether this HTTP service is a moOde instance.
    /// Returns nil if the endpoint is missing/invalid.
    private func fetchMoodeConnectionData(from service: DiscoveredService) async -> MPDConnectionData? {
        let host = service.service.hostName ?? service.ipAddresses?.first ?? ""
        guard !host.isEmpty else { return nil }

        // Prefer the resolved numeric IP for the HTTP call.
        let httpHost = service.ipAddresses?.first ?? host
        let port = service.service.port

        // Try /browserconfig.xml over HTTP.
        guard let url = URL(string: "http://\(httpHost):\(port)/browserconfig.xml") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2.5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            let xml = XMLHash.parse(data)
            guard let _ = xml["browserconfig"].element else {
                return nil
            }

            return MPDConnectionData(name: host, host: host, ip: service.ipAddresses?.first, port: 6600, type: .moodeaudio)
        } catch {
            return nil
        }
    }

    private func moodeConnectionProperties(from data: MPDConnectionData) -> [String: Any] {
        var connectionProperties: [String: Any] = [
            ConnectionProperties.name.rawValue: data.name,
            ConnectionProperties.host.rawValue: data.host,
            ConnectionProperties.port.rawValue: data.port,
            ConnectionProperties.controllerType.rawValue: MPDPlayer.controllerType,
            MPDConnectionProperties.MPDType.rawValue: MPDType.moodeaudio.rawValue
        ]
        if let ip = data.ip {
            connectionProperties[MPDConnectionProperties.ipAddress.rawValue] = ip
        }
        return connectionProperties
    }

    // MARK: - Volumio discovery helpers

    /// Fetch and parse /browserconfig.xml to determine whether this HTTP service is a moOde instance.
    /// Returns nil if the endpoint is missing/invalid.
    private func fetchVolumioConnectionData(from service: DiscoveredService) async -> MPDConnectionData? {
        let host = service.service.hostName ?? service.ipAddresses?.first ?? ""
        guard !host.isEmpty else { return nil }

        // Prefer the resolved numeric IP for the HTTP call.
        let httpHost = service.ipAddresses?.first ?? host
        let port = service.service.port
        print("host \(httpHost) \(port)")
        
        // Try /browserconfig.xml over HTTP.
        guard let url = URL(string: "http://\(httpHost):\(port)/api/v1/getstate") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2.5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] ,json["album"] != nil, json["artist"] != nil {
                return MPDConnectionData(name: host, host: host, ip: service.ipAddresses?.first, port: 6600, type: .volumio)
            }
            return nil
        } catch {
            return nil
        }
    }

    private func volumioConnectionProperties(from data: MPDConnectionData) -> [String: Any] {
        var connectionProperties: [String: Any] = [
            ConnectionProperties.name.rawValue: data.name,
            ConnectionProperties.host.rawValue: data.host,
            ConnectionProperties.port.rawValue: data.port,
            ConnectionProperties.controllerType.rawValue: MPDPlayer.controllerType,
            MPDConnectionProperties.MPDType.rawValue: MPDType.volumio.rawValue
        ]
        if let ip = data.ip {
            connectionProperties[MPDConnectionProperties.ipAddress.rawValue] = ip
        }
        return connectionProperties
    }

    public func decodePlayer(_ data: Data) async throws -> any PlayerProtocol {
        let player = try await MPDPlayer.decodePlayer(data)
        if !players.contains(where: { $0.uniqueID == player.uniqueID }) {
            players.append(player)
        }
        return player
    }
        
    @ViewBuilder
    public func manualAddPlayerView() -> some View {
        Text("Here we can add a player manually.")
    }
}
