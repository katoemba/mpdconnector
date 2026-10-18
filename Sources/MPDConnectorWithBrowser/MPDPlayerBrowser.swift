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
    
    // The synchronous requirements of PlayerBrowserProtocol are not main actor isolated, so the members that
    // satisfy them are `nonisolated`: they only touch immutable values, or hop to the main actor themselves.
    public nonisolated var controllerType: String {
        MPDPlayer.controllerType
    }
    
    public nonisolated let playerEventStream: AsyncStream<ConnectorProtocol.PlayerBrowserEvent>
    private let playerEventContinuation: AsyncStream<ConnectorProtocol.PlayerBrowserEvent>.Continuation

    private var isListening = false
    private var discoveryTasks: [String: Task<Void, Never>] = [:]
    /// The player each discovered service turned into, so its removal can be reported under the player's id.
    private var discoveredPlayerIDs: [String: String] = [:]
    /// Announcements of cached players still in progress, by player id. A token tells a task apart from a later one.
    private var announceTasks: [String: (token: UUID, task: Task<Void, Never>)] = [:]
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
        (self.playerEventStream, self.playerEventContinuation) = AsyncStream.makeStream(of: ConnectorProtocol.PlayerBrowserEvent.self)
    }
    
    /// Start listening for players on the local domain.
    public func startListening(predefinedPlayers: [PlayerDefinition]) async {
        guard isListening == false else {
            return
        }
        
        isListening = true
        
        let predefinedPlayerIDs = Set(predefinedPlayers.compactMap { definition -> String? in
            guard definition.type == controllerType,
                  let player = try? JSONDecoder().decode(MPDPlayer.PlayerAttributes.self, from: definition.typeSpecificData) else { return nil }
            return MPDPlayer.uniqueIDForPlayer(host: player.host, port: player.port)
        })

        for definition in predefinedPlayers {
            guard definition.type == controllerType else { continue }
            let token = UUID()
            let task = Task { [weak self] in
                await self?.announce(definition)
                if self?.announceTasks[definition.id]?.token == token {
                    self?.announceTasks.removeValue(forKey: definition.id)
                }
            }
            announceTasks[definition.id] = (token, task)
        }

        migrateLegacyManualPlayersIfNeeded(predefinedPlayerIDs: predefinedPlayerIDs)

        let mpdBrowser = AsyncServiceBrowser()
        self.mpdBrowser = mpdBrowser
        Task {
            for await event in mpdBrowser.discover(type: "_mpd._tcp.") {
                switch event {
                case .found(let service):
                    handleFound(taskKey: "mpd:\(service.name)") { [self] in
                        let connectionData = MPDConnectionData(name: service.name,
                                                               host: service.hostName ?? "",
                                                               ip: service.ipv4Address,
                                                               port: service.port,
                                                               type: .classic)
                        return (try await createPlayerFromService(connectionData), connectionData.ip)
                    }
                case .removed(let service):
                    serviceRemoved(taskKey: "mpd:\(service.name)")
                }
            }
        }
        
        let httpBrowser = AsyncServiceBrowser()
        self.httpBrowser = httpBrowser
        Task {
            for await event in httpBrowser.discover(type: "_http._tcp.") {
                switch event {
                case .found(let service):
                    handleFound(taskKey: "http:\(service.name)") { [self] in
                        let connectionData: MPDConnectionData?
                        if let moode = await fetchMoodeConnectionData(from: service) {
                            connectionData = moode
                        }
                        else {
                            connectionData = await fetchVolumioConnectionData(from: service)
                        }
                        guard let connectionData else { return nil }
                        return (try await createPlayerFromService(connectionData), connectionData.ip)
                    }
                case .removed(let service):
                    serviceRemoved(taskKey: "http:\(service.name)")
                }
            }
        }
        
        let volumioBrowser = AsyncServiceBrowser()
        self.volumioBrowser = volumioBrowser
        Task {
            for await event in volumioBrowser.discover(type: "_Volumio._tcp.") {
                switch event {
                case .found(let service):
                    handleFound(taskKey: "volumio:\(service.name)") { [self] in
                        let connectionData = MPDConnectionData(name: service.name,
                                                               host: service.hostName ?? "",
                                                               ip: service.ipv4Address,
                                                               port: 6600,
                                                               type: .volumio)
                        return (try await createPlayerFromService(connectionData), connectionData.ip)
                    }
                case .removed(let service):
                    serviceRemoved(taskKey: "volumio:\(service.name)")
                }
            }
        }
    }
    
    /// Handle a discovered service without blocking the discovery loop. The player is announced as soon as it
    /// is created, so it shows up immediately. The slow, network-bound part (connect and finishDiscovery) runs
    /// in a per-service task, after which the player is announced again so the manager picks up its details.
    func handleFound(taskKey: String,
                             createPlayer: @escaping @MainActor () async throws -> (MPDPlayer, String?)?) {
        // A discovery for this service is already in flight.
        guard discoveryTasks[taskKey] == nil else { return }

        discoveryTasks[taskKey] = Task { [weak self] in
            defer { self?.discoveryTasks.removeValue(forKey: taskKey) }
            do {
                guard let (player, ipAddress) = try await createPlayer(), !Task.isCancelled, let self else { return }
                self.discoveredPlayerIDs[taskKey] = player.uniqueID
                self.pushPlayerEvent(.added(player))
                await self.connect(player, ipAddress: ipAddress)
                guard !Task.isCancelled else { return }
                self.pushPlayerEvent(.added(player))
            } catch {
                print("Failed to create player: \(error)")
            }
        }
    }

    /// A service went away. Players are keyed by host and port, which for moOde and Volumio is not in the service
    /// itself, so report the removal under the id of the player the service was turned into.
    func serviceRemoved(taskKey: String) {
        cancelDiscovery(taskKey: taskKey)
        if let uniqueID = discoveredPlayerIDs.removeValue(forKey: taskKey) {
            pushPlayerEvent(.removed(uniqueID))
        }
    }

    private func cancelDiscovery(taskKey: String) {
        discoveryTasks.removeValue(forKey: taskKey)?.cancel()
    }

    /// Finish discovery for a newly discovered player. Players connect via their hostname; if that fails but
    /// discovery resolved an IPv4 address, fall back to that address. The fallback is stored per player and is
    /// cleared again as soon as the hostname works.
    private func connect(_ player: MPDPlayer, ipAddress: String?) async {
        if await player.ping() == false, let ip = ipAddress, !ip.isEmpty, ip != player.attributes.host {
            let key = MPDDefaultKey.discoveredIpAddress.stringValue(host: player.attributes.host, port: player.attributes.port)
            userDefaults.set(ip, forKey: key)
            player.applyConnectionSettingsChange()
            if await player.ping() == false {
                userDefaults.removeObject(forKey: key)
                player.applyConnectionSettingsChange()
            }
        }
        try? await player.finishDiscovery()
    }

    /// Create a player from a discovered service
    private func createPlayerFromService(_ connectionData: MPDConnectionData) async throws -> MPDPlayer {
        // Forget any fallback address from an earlier discovery, the hostname is tried first.
        userDefaults.removeObject(forKey: MPDDefaultKey.discoveredIpAddress.stringValue(host: connectionData.host, port: connectionData.port))
        // Remember the address discovery resolved, for display in diagnostics.
        let resolvedKey = MPDDefaultKey.resolvedIpAddress.stringValue(host: connectionData.host, port: connectionData.port)
        if let ip = connectionData.ip, !ip.isEmpty {
            userDefaults.set(ip, forKey: resolvedKey)
        }
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
                                                    password: nil,
                                                    useHttpCoverArt: false,
                                                    manual: false,
                                                    albumGrouping: "albumartist",
                                                    coverFilename: "",
                                                    outputHost: connectionData.host,
                                                    outputPort: 0)

        return MPDPlayer(attributes, userDefaults: userDefaults)
    }
    
    // MARK: - Legacy migration

    private static let legacyMigrationDoneKey = "MPD.ManualPlayersMigrated"

    /// Reads manual players stored by the old app version and injects them into the new PlayerManager
    /// via the event stream. Runs at most once, gated by a UserDefaults flag.
    private func migrateLegacyManualPlayersIfNeeded(predefinedPlayerIDs: Set<String>) {
        guard !userDefaults.bool(forKey: Self.legacyMigrationDoneKey) else { return }
        // Only flag the migration as done once it has completed, so an interrupted run is retried.
        defer { userDefaults.set(true, forKey: Self.legacyMigrationDoneKey) }

        // Old format: [playerName: [String: Any]] stored under one of these keys.
        let legacyKeys = ["MPD.ManualPlayers", "mpd.browser.manualplayers"]
        for key in legacyKeys {
            guard let stored = userDefaults.dictionary(forKey: key), !stored.isEmpty else { continue }
            for (_, value) in stored {
                guard let props = value as? [String: Any],
                      // The old app used capitalised keys, savePlayer() in this package uses lowercase ones.
                      let host = (props["Host"] ?? props["host"]) as? String, !host.isEmpty,
                      let port = (props["Port"] ?? props["port"]) as? Int, port > 0 else { continue }

                // Skip players already present in the new persistence.
                let playerID = MPDPlayer.uniqueIDForPlayer(host: host, port: port)
                guard !predefinedPlayerIDs.contains(playerID) else { continue }

                let name = ((props["Name"] ?? props["name"]) as? String) ?? host
                let typeInt = (props["type"] as? Int) ?? MPDType.classic.rawValue
                let mpdType = MPDType(rawValue: typeInt) ?? .classic
                let rawPassword = ((props["Password"] ?? props["password"]) as? String) ?? ""
                let password: String? = rawPassword.isEmpty ? nil : rawPassword
                // Old format may use "ipAddress" (lowercase) or "MPD.IpAddress"
                let ipAddress = (props["ipAddress"] as? String) ?? (props["MPD.IpAddress"] as? String)

                let attributes = MPDPlayer.PlayerAttributes(
                    uuid: UUID(),
                    name: name,
                    type: mpdType,
                    version: "0.0.0",
                    ipAddress: ipAddress,
                    host: host,
                    port: port,
                    password: password,
                    useHttpCoverArt: false,
                    manual: true,
                    albumGrouping: "albumartist",
                    coverFilename: "",
                    outputHost: host,
                    outputPort: 0
                )
                MPDPlayer.storePassword(password, host: host, port: port, userDefaults: userDefaults)
                let player = MPDPlayer(attributes, userDefaults: userDefaults)
                self.pushPlayerEvent(.added(player))
                Task {
                    try? await player.finishDiscovery()
                }
            }
        }
    }

    /// Announce a player that is known from an earlier session.
    ///
    /// Announcing a player counts as having seen it, which is what keeps a cached player from expiring. So a
    /// cached player is only announced when it answers: otherwise players that are gone (another network, a
    /// changed hostname) would stay in the list forever, and only manual players can be deleted. Manual players
    /// are always announced, as they can't be rediscovered.
    func announce(_ definition: PlayerDefinition) async {
        guard let player = try? MPDPlayer.decodePlayer(definition.typeSpecificData, userDefaults: userDefaults) else { return }
        let isReachable = await player.ping()
        try? await player.finishDiscovery()
        // Cancelled when the player was deleted in the meantime: announcing it would bring it back.
        guard !Task.isCancelled else { return }
        if isReachable || definition.isManual || player.attributes.manual {
            pushPlayerEvent(.added(player))
        }
    }

    /// Stop listening for players.
    public func stopListening() async {
        guard isListening == true else {
            return
        }
        
        discoveryTasks.values.forEach { $0.cancel() }
        discoveryTasks.removeAll()
        discoveredPlayerIDs.removeAll()
        announceTasks.values.forEach { $0.task.cancel() }
        announceTasks.removeAll()

        mpdBrowser?.stopListening()
        mpdBrowser = nil
        
        httpBrowser?.stopListening()
        httpBrowser = nil
        
        volumioBrowser?.stopListening()
        volumioBrowser = nil

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
    
    private func pushPlayerEvent(_ event: ConnectorProtocol.PlayerBrowserEvent) {
        playerEventContinuation.yield(event)
    }

    // MARK: - moOde discovery helpers

    /// Fetch and parse /browserconfig.xml to determine whether this HTTP service is a moOde instance.
    /// Returns nil if the endpoint is missing/invalid.
    private func fetchMoodeConnectionData(from service: DiscoveredService) async -> MPDConnectionData? {
        let host = service.hostName ?? service.ipAddresses?.first ?? ""
        guard !host.isEmpty else { return nil }

        // Prefer the resolved numeric IP for the HTTP call.
        let httpHost = service.ipAddresses?.first ?? host
        let port = service.port

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

            return MPDConnectionData(name: host, host: host, ip: service.ipv4Address, port: 6600, type: .moodeaudio)
        } catch {
            return nil
        }
    }

    // MARK: - Volumio discovery helpers

    /// Fetch and parse /browserconfig.xml to determine whether this HTTP service is a moOde instance.
    /// Returns nil if the endpoint is missing/invalid.
    private func fetchVolumioConnectionData(from service: DiscoveredService) async -> MPDConnectionData? {
        let host = service.hostName ?? service.ipAddresses?.first ?? ""
        guard !host.isEmpty else { return nil }

        // Prefer the resolved numeric IP for the HTTP call.
        let httpHost = service.ipAddresses?.first ?? host
        let port = service.port
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
                return MPDConnectionData(name: host, host: host, ip: service.ipv4Address, port: 6600, type: .volumio)
            }
            return nil
        } catch {
            return nil
        }
    }
    
    public func decodePlayer(_ playerDefinition: ConnectorProtocol.PlayerDefinition) async throws -> any ConnectorProtocol.PlayerProtocol {
        try MPDPlayer.decodePlayer(playerDefinition.typeSpecificData, userDefaults: userDefaults)
    }

    /// The user deleted a manual player: forget its settings (password, address, name, ...), so that adding the
    /// same player again starts afresh instead of silently reusing them.
    public nonisolated func playerRemoved(_ playerDefinition: ConnectorProtocol.PlayerDefinition) {
        // Called by the player manager, which runs on the main actor.
        MainActor.assumeIsolated {
            guard playerDefinition.type == controllerType else { return }
            // An announcement still in progress would bring the player back.
            announceTasks.removeValue(forKey: playerDefinition.id)?.task.cancel()

            guard playerDefinition.isManual || isManualPlayer(playerDefinition) else { return }
            MPDPlayer.forgetSettings(uniqueID: playerDefinition.id, userDefaults: userDefaults)
        }
    }

    /// Whether a persisted player was added manually. Only reads the attributes, so it is cheap.
    public nonisolated func isManualPlayer(_ playerDefinition: ConnectorProtocol.PlayerDefinition) -> Bool {
        guard playerDefinition.type == controllerType,
              let attributes = try? JSONDecoder().decode(MPDPlayer.PlayerAttributes.self, from: playerDefinition.typeSpecificData) else {
            return false
        }
        return attributes.manual
    }

    @ViewBuilder
    public func manualAddPlayerView() -> some View {
        ManualAddMPDPlayerView(userDefaults: userDefaults) { [weak self] player in
            guard let self else { return }
            // Push immediately — user already verified connectivity via the connection test.
            // Calling ping() again here hangs on hotspot/direct-AP networks after the first connection closes.
            self.pushPlayerEvent(.updated(player))
            Task {
                try? await player.finishDiscovery()
            }
        }
    }
}

private struct ManualAddMPDPlayerView: View {
    @State private var name: String = ""
    @State private var host: String = ""
    @State private var portText: String = "6600"
    @State private var type: MPDType = .classic
    @State private var password: String = ""
    @State private var isTesting = false
    @State private var canTest = false
    @State private var testResult = ""
    @State private var testColor: Color = .secondary
    @State private var testSucceeded: Bool = false
    @Environment(\.dismiss) private var dismiss

    let userDefaults: UserDefaults
    let onSave: (MPDPlayer) -> Void

    /// The entered port, or nil when it isn't a valid one.
    private var port: Int? {
        guard let port = Int(portText.trimmingCharacters(in: .whitespaces)), (1...65535).contains(port) else {
            return nil
        }
        return port
    }

    var body: some View {
        VStack(alignment: .leading) {
            Form {
                Section(header: Text(String(localized: "Connection", bundle: .module))) {
                    TextField(String(localized: "Name", bundle: .module), text: $name)
                        .textContentType(.name)
                    TextField(String(localized: "IP address or host", bundle: .module), text: $host)
                        .autocorrectionDisabled(true)
                    // Bound to text rather than through a formatter: a formatter only hands over the value on
                    // Return or when the field loses focus, so tapping Test or Save straight after typing would
                    // use the previous port.
                    TextField(String(localized: "Port", bundle: .module), text: $portText)
                    #if os(iOS)
                        .keyboardType(.numberPad)
                    #endif
                    Picker(String(localized: "Type", bundle: .module), selection: $type) {
                        Text("Classic").tag(MPDType.classic)
                        Text("Chord").tag(MPDType.chord)
                        Text("moOde").tag(MPDType.moodeaudio)
                        Text("Volumio").tag(MPDType.volumio)
                        Text("Bryston").tag(MPDType.bryston)
                    }
                    SecureField(String(localized: "Password (optional)", bundle: .module), text: $password)
                }
                .onChange(of: host) { _, _ in
                    resetTest()
                }
                .onChange(of: portText) { _, _ in
                    resetTest()
                }
                .onChange(of: type) { _, _ in
                    resetTest()
                }
                .onChange(of: password) { _, _ in
                    resetTest()
                }

                Section {
                    Text(testResult)
                        .foregroundStyle(testColor)
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 420, idealWidth: 520, maxWidth: 640, alignment: .center)
            .toolbar {
                ToolbarItem() {
                    Button(String(localized: "Test Connection", bundle: .module)) {
                        Task {
                            await testConnection()
                        }
                    }
                    .disabled(!canTest)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: .module)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save", bundle: .module)) {
                        // Every manually added player gets its own id: adding the same server again, even under a
                        // name used before, adds a player instead of silently replacing one and inheriting its settings.
                        guard let port else { return }
                        let player = buildPlayer(instanceID: UUID().uuidString, port: port)
                        onSave(player)
                        dismiss()
                    }
                    .disabled(!testSucceeded || name.isEmpty || port == nil)
                }
            }
        }
        .onAppear() {
            resetTest()
        }
    }

    private func buildPlayer(instanceID: String, port: Int) -> MPDPlayer {
        let attributes = MPDPlayer.PlayerAttributes(
            uuid: UUID(),
            name: name.isEmpty ? host : name,
            type: type,
            version: "0.0.0",
            ipAddress: host,
            host: host,
            port: port,
            password: password.isEmpty ? nil : password,
            useHttpCoverArt: false,
            manual: true,
            albumGrouping: "albumartist",
            coverFilename: "",
            outputHost: host,
            outputPort: 0,
            instanceID: instanceID
        )
        // The connection reads the password from UserDefaults, so it must be there before connecting.
        MPDPlayer.storePassword(attributes.password, host: host, port: port, instanceID: instanceID, userDefaults: userDefaults)
        return MPDPlayer(attributes, userDefaults: userDefaults)
    }

    @MainActor
    private func testConnection() async {
        isTesting = true
        defer { isTesting = false }
        testResult = String(localized: "Testing...", bundle: .module)
        testColor = .primary

        // Test with a throwaway id, and forget what it stored (the password, and the defaults a player of the
        // chosen type writes), so nothing of the test sticks to the player that gets saved, or to another one.
        guard let port else { return }
        let testID = "test-\(UUID().uuidString)"
        let player = buildPlayer(instanceID: testID, port: port)
        let ok = await player.ping()
        MPDPlayer.forgetSettings(uniqueID: player.uniqueID, userDefaults: userDefaults)
        if ok {
            testResult = String(localized: "Connection successful", bundle: .module)
            testColor = .green
            testSucceeded = true
        } else {
            testResult = String(localized: "Failed to connect", bundle: .module)
            testColor = .red
            testSucceeded = false
        }
    }
    
    private func resetTest() {
        canTest = !host.isEmpty && port != nil
        testResult = String(localized: "Not Connected", bundle: .module)
        testColor = .secondary
        testSucceeded = false
    }
}

