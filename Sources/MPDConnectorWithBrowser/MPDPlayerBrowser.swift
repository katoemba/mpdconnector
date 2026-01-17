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
    
    private func nowTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }
    
    /// Start listening for players on the local domain.
    public func startListening(predefinedPlayers: [PlayerDefinition]) async {
        guard isListening == false else {
            return
        }
        
        isListening = true
        
        for definition in predefinedPlayers {
            guard definition.type == controllerType else { continue }
            Task {
                guard let player = try? await MPDPlayer.decodePlayer(definition.typeSpecificData, userDefaults: userDefaults),
                      await player.ping() else {
                    return
                }
                
                if !players.contains(where: { $0 as? MPDPlayer == player }) {
                    players.append(player)
                }
            }
        }
        
        let mpdBrowser = AsyncServiceBrowser()
        self.mpdBrowser = mpdBrowser
        Task {
            for await event in mpdBrowser.discover(type: "_mpd._tcp.") {
                switch event {
                case .found(let service):
                    do {
                        let connectionData = MPDConnectionData(name: service.name,
                                                               host: service.service.hostName ?? "",
                                                               ip: service.ipAddresses?.first,
                                                               port: service.service.port,
                                                               type: .classic)
                        let player = try await createPlayerFromService(connectionData)
                        // Only add if not already in the list
                        if !players.contains(where: { $0 as? MPDPlayer == player }) {
                            players.append(player)
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
                            let player = try await createPlayerFromService(connectionData)
                            if !players.contains(where: { $0 as? MPDPlayer == player }) {
                                players.append(player)
                            }
                        }
                        else if let connectionData = await fetchVolumioConnectionData(from: service) {
                            let player = try await createPlayerFromService(connectionData)
                            if !players.contains(where: { $0 as? MPDPlayer == player }) {
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
                        let connectionData = MPDConnectionData(name: service.name,
                                                               host: service.service.hostName ?? "",
                                                               ip: service.ipAddresses?.first,
                                                               port: 6600,
                                                               type: .volumio)

                        let player = try await createPlayerFromService(connectionData)
                        // Only add if not already in the list
                        if !players.contains(where: { $0 as? MPDPlayer == player }) {
                            players.append(player)
                        }
                    } catch {
                        print("Failed to create volumio player: \(error)")
                    }
                case .removed(let service):
                    removePlayerByName(service.name)
                }
            }
        }
    }
    
    /// Create a player from a discovered service
    private func createPlayerFromService(_ connectionData: MPDConnectionData) async throws -> MPDPlayer {
        // Create connection properties
        var type: MPDType = connectionData.type
        if type == .classic {
            if connectionData.name.lowercased().contains("poly") ||
                connectionData.host.lowercased().contains("poly") ||
                connectionData.name.lowercased().contains("chord") ||
                connectionData.host.lowercased().contains("chord") ||
                connectionData.name.lowercased().contains("2go") ||
                connectionData.host.lowercased().contains("2go") ||
                connectionData.name.lowercased().contains("2 go") ||
                connectionData.host.lowercased().contains("2 go") ||
                connectionData.name.lowercased().contains("hugo") ||
                connectionData.host.lowercased().contains("hugo") {
                type = .chord
            }
        }
        
        let attributes = MPDPlayer.PlayerAttributes(uuid: UUID(),
                                                    name: connectionData.name,
                                                    type: type,
                                                    version: "0.0.0",
                                                    ipAddress: connectionData.ip,
                                                    host: connectionData.host,
                                                    port: connectionData.port,
                                                    password: nil)

        return MPDPlayer(attributes, userDefaults: userDefaults)
    }
    
    /// Stop listening for players.
    public func stopListening() async {
        guard isListening == true else {
            return
        }
        
        mpdBrowser?.stopListening()
        mpdBrowser = nil
        
        httpBrowser?.stopListening()
        httpBrowser = nil
        
        volumioBrowser?.stopListening()
        volumioBrowser = nil

        players.removeAll()
        
        isListening = false
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
    
    public func decodePlayer(_ playerDefinition: ConnectorProtocol.PlayerDefinition) async throws -> any ConnectorProtocol.PlayerProtocol {
        let player = try await MPDPlayer.decodePlayer(playerDefinition.typeSpecificData, userDefaults: userDefaults)
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

