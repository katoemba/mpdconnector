//
//  StatusManager.swift
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
import SwiftMPD
import SwiftUI
import Synchronization

enum ConnectionError: Error {
    case internalError
}

public enum MPDType: Int, Codable, CaseIterable, Sendable {
    case unknown = 0
    case classic = 1
    case volumio = 3
    case bryston = 4
    case runeaudio = 5
    case moodeaudio = 6
    case chord = 7
    
    var description: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .classic:
            return "Classic MPD"
        case .volumio:
            return "Volumio"
        case .bryston:
            return "Bryston"
        case .runeaudio:
            return "Rune Audio"
        case .moodeaudio:
            return "moOde"
        case .chord:
            return "Chord Poly/2go"
        }
    }
    
    static var selectableTypes: [MPDType] {
        [.classic, .volumio, .bryston, .runeaudio, .moodeaudio, .chord]
    }
}

/// A player is handed to tasks and other threads, while the settings views change it from the main thread. The
/// state that changes after `init` sits in `state`, behind a lock; everything else is set once in `init`.
public final class MPDPlayer: PlayerProtocol, ObservableObject {
    public struct PlayerAttributes: Codable, Sendable {
        public init(uuid: UUID, name: String, type: MPDType, version: String, ipAddress: String? = nil, host: String, port: Int, password: String?, useHttpCoverArt: Bool, manual: Bool, albumGrouping: String, coverFilename: String, outputHost: String, outputPort: Int, instanceID: String? = nil) {
            self.uuid = uuid
            self.name = name
            self.type = type
            self.version = version
            self.host = host
            self.port = port
            self.password = password
            self.useHttpCoverArt = useHttpCoverArt
            self.manual = manual
            self.albumGrouping = albumGrouping
            self.coverFilename = coverFilename
            self.outputHost = outputHost
            self.outputPort = outputPort
            self.instanceID = instanceID
        }
        
        private enum CodingKeys: String, CodingKey {
            case uuid, type, name, version, host, port, password, manual
            case useHttpCoverArt, albumGrouping, coverFilename, outputHost, outputPort, instanceID
        }

        // Tolerant decoding: persisted players written by older versions may lack newer fields, and a player
        // that fails to decode would silently disappear. Only host and port are essential.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let host = try container.decode(String.self, forKey: .host)
            self.host = host
            self.port = try container.decode(Int.self, forKey: .port)
            self.uuid = (try? container.decode(UUID.self, forKey: .uuid)) ?? UUID()
            self.type = (try? container.decode(MPDType.self, forKey: .type)) ?? .classic
            self.name = (try? container.decode(String.self, forKey: .name)) ?? host
            self.version = (try? container.decode(String.self, forKey: .version)) ?? "0.0.0"
            self.password = try? container.decodeIfPresent(String.self, forKey: .password)
            self.manual = (try? container.decode(Bool.self, forKey: .manual)) ?? false
            self.useHttpCoverArt = (try? container.decode(Bool.self, forKey: .useHttpCoverArt)) ?? false
            self.albumGrouping = (try? container.decode(String.self, forKey: .albumGrouping)) ?? "albumartist"
            self.coverFilename = (try? container.decode(String.self, forKey: .coverFilename)) ?? ""
            self.outputHost = (try? container.decode(String.self, forKey: .outputHost)) ?? host
            self.outputPort = (try? container.decode(Int.self, forKey: .outputPort)) ?? 0
            self.instanceID = try? container.decodeIfPresent(String.self, forKey: .instanceID)
        }

        // identification
        public let uuid: UUID
        public let type: MPDType

        // player network attributes
        public let name: String
        public let version: String
        public let host: String
        public let port: Int
        public let password: String?
        public let manual: Bool
        
        // player settings
        public let useHttpCoverArt: Bool
        public let albumGrouping: String
        public let coverFilename: String
        public let outputHost: String
        public let outputPort: Int

        /// Set for a manual player that shares host and port with another player, so both can exist side by side.
        /// Nil for all other players, which keeps their uniqueID (and everything stored under it) unchanged.
        public let instanceID: String?

        func withInstanceID(_ instanceID: String?) -> PlayerAttributes {
            PlayerAttributes(uuid: uuid, name: name, type: type, version: version, host: host, port: port,
                             password: password, useHttpCoverArt: useHttpCoverArt, manual: manual,
                             albumGrouping: albumGrouping, coverFilename: coverFilename,
                             outputHost: outputHost, outputPort: outputPort, instanceID: instanceID)
        }
    }
    
    private struct State {
        var name: String
        var attributes: PlayerAttributes
        var type: MPDType
        var version: String
        var commands: [String]
        var connectionWarning: String?
        var mpdConnector: SwiftMPD.MPDConnector
        var mpdIdleConnector: SwiftMPD.MPDConnector
    }
    private let state: Mutex<State>

    public let mediaServerModel: String = "MPD"
    
    public let mediaAvailable: Bool = true
    
    public let mediaServers: [BrowseProtocol] = []
    
    public func selectMediaServer(_ mediaServer: BrowseProtocol, source: ConnectorProtocol.SourceType) {
    }
    
    /// UserDefaults is documented as thread-safe, but this SDK doesn't mark it `Sendable`.
    nonisolated(unsafe) internal let userDefaults: UserDefaults
    public static let controllerType = "MPD"
    
    public var deviceName: String {
        return attributes.name
    }
    /// Changes are announced to SwiftUI by hand, as `@Published` storage is not safe to read from other threads.
    public var name: String {
        get { state.withLock { $0.name } }
        set {
            objectWillChange.send()
            state.withLock { $0.name = newValue }
        }
    }

    public var controllerType: String {
        return MPDPlayer.controllerType
    }
    public let discoverMode = DiscoverMode.automatic
    
    public internal(set) var attributes: PlayerAttributes {
        get { state.withLock { $0.attributes } }
        set {
            // Attributes are rebuilt in several places; make sure the player's identity survives that.
            var newAttributes = newValue
            if newAttributes.instanceID != instanceID {
                newAttributes = newAttributes.withInstanceID(instanceID)
            }
            state.withLock { $0.attributes = newAttributes }
            // The status builds the cover art URLs from these, so a changed setting applies right away.
            mpdStatus.updateAttributes(newAttributes)
            let customName = userDefaults.string(forKey: MPDDefaultKey.customPlayerName.stringValue(self))
            if let customName = customName, !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                name = customName
            }
            else {
                name = newAttributes.name
            }
        }
    }
    
    public internal(set) var type: MPDType {
        get { state.withLock { $0.type } }
        set { state.withLock { $0.type = newValue } }
    }
    private let instanceID: String?
    
    public private(set) var version: String {
        get { state.withLock { $0.version } }
        set {
            state.withLock { $0.version = newValue }
            attributes = MPDPlayer.PlayerAttributes(uuid: attributes.uuid,
                                                    name: attributes.name,
                                                    type: attributes.type,
                                                    version: newValue,
                                                    host: attributes.host,
                                                    port: attributes.port,
                                                    password: attributes.password,
                                                    useHttpCoverArt: attributes.useHttpCoverArt,
                                                    manual: attributes.manual,
                                                    albumGrouping: attributes.albumGrouping,
                                                    coverFilename: attributes.coverFilename,
                                                    outputHost: attributes.outputHost,
                                                    outputPort: attributes.outputPort)
        }
    }
    public func updateVersion(_ version: String) {
        if version != "0.0.0" {
            self.version = version
        }
    }

    public var hidden: Bool {
        return userDefaults.bool(forKey: MPDDefaultKey.hidden.stringValue(self))
    }

    public private(set) var connectionWarning: String? {
        get { state.withLock { $0.connectionWarning } }
        set { state.withLock { $0.connectionWarning = newValue } }
    }
    
    internal private(set) var mpdConnector: SwiftMPD.MPDConnector {
        get { state.withLock { $0.mpdConnector } }
        set { state.withLock { $0.mpdConnector = newValue } }
    }
    private var mpdIdleConnector: SwiftMPD.MPDConnector {
        get { state.withLock { $0.mpdIdleConnector } }
        set { state.withLock { $0.mpdIdleConnector = newValue } }
    }
    
    public var description: String {
        return type.description + " " + version
    }
    
    private var commands: [String] {
        get { state.withLock { $0.commands } }
        set { state.withLock { $0.commands = newValue } }
    }
    public var supportedFunctions: [Functions] {
        return [.playRecursiveFolder, .repeatSingle, .consume, .radio, .randomSongs, .randomAlbums, .composers, .performers, .conductors, .quality, .recentlyAddedAlbums, .stream, .playlists, .volumeAdjustment] + (commands.contains("albumart") ? [.binaryImageRetrieval] : [])  + (commands.contains("readpicture") ? [.embeddedImageRetrieval] : []) + (attributes.useHttpCoverArt ? [.httpImageRetrieval] : [])
    }
    
    /// Current status
    private let mpdStatus: MPDStatus
    public var status: StatusProtocol {
        return mpdStatus
    }
    
    public var uniqueID: String {
        get {
            return "\(MPDPlayer.uniqueIDForPlayer(self))"
        }
    }
    
    private static func uniqueIDForPlayer(_ player: MPDPlayer) -> String {
        return uniqueIDForPlayer(host: player.attributes.host, port: player.attributes.port, instanceID: player.instanceID)
    }

    /// Remove everything stored for the player with this id, such as its password and address settings.
    public static func forgetSettings(uniqueID: String, userDefaults: UserDefaults) {
        for key in MPDDefaultKey.allCases where key != .manualPlayers {
            userDefaults.removeObject(forKey: key.stringValue(uniqueID))
        }
    }

    public static func uniqueIDForPlayer(host: String, port: Int, instanceID: String?) -> String {
        let id = uniqueIDForPlayer(host: host, port: port)
        guard let instanceID else { return id }
        return "\(id)#\(instanceID)"
    }
    
    /// The connection password is read from UserDefaults, not from the attributes, so a player created with a
    /// password (manual add, legacy migration) must have it stored there. An empty password is left alone,
    /// so a password set earlier in the player settings is never wiped.
    public static func storePassword(_ password: String?, host: String, port: Int, instanceID: String? = nil, userDefaults: UserDefaults) {
        guard let password, !password.isEmpty else { return }
        userDefaults.set(password, forKey: MPDDefaultKey.password.stringValue(uniqueIDForPlayer(host: host, port: port, instanceID: instanceID)))
    }
    
    public static func uniqueIDForPlayer(host: String, port: Int) -> String {
        return "\(host):\(port)"
    }
    
    public var model: String {
        get {
            return type.description
        }
    }
    
    public func encodePlayer() throws -> Data {
        return try JSONEncoder().encode(attributes)
    }
    
    public static func decodePlayer(_ data: Data, userDefaults: UserDefaults) throws -> Self {
        let decodedPlayer = try JSONDecoder().decode(PlayerAttributes.self, from: data)
        return MPDPlayer(decodedPlayer, userDefaults: userDefaults) as! Self
    }
    
    public func playerDefinition() throws -> ConnectorProtocol.PlayerDefinition {
        try ConnectorProtocol.PlayerDefinition(id: uniqueID,
                                               name: name,
                                               type: controllerType,
                                               typeSpecificData: encodePlayer(),
                                               isManual: attributes.manual)
    }
    
    /// Create a unique object for every request for a control object
    public var control: ControlProtocol {
        get {
            // Use serialScheduler to synchronize commands across multiple MPDControl instances.
            return MPDControl.init(attributes: attributes, identification: uniqueID, mpdConnector: mpdConnector)
        }
    }
    /// Create a unique object for every request for a browse object
    public var browse: BrowseProtocol {
        get {
            return MPDBrowse.init(attributes: attributes, identification: uniqueID, mpdConnector: mpdConnector)
        }
    }
    
    public func browse(source: SourceType) -> (BrowseProtocol)? {
        browse
    }
    
    public var playerStreamURL: URL? {
        let hostString = attributes.outputHost
        let port = attributes.outputPort
        guard !hostString.isEmpty, port != 0 else { return nil }
        return URL(string: "http://\(hostString):\(port)")
    }
    
    public var diagnosticsInfo: [DiagnosticsItem] {
        [DiagnosticsItem(id: "id", description: uniqueID),
         DiagnosticsItem(id: "host", description: attributes.host),
         DiagnosticsItem(id: "connect to ip address", description: userDefaults.bool(forKey: MPDDefaultKey.connectToIpAddress.stringValue(self)) ? "Yes" : "No"),
         DiagnosticsItem(id: "ip address", description: userDefaults.string(forKey: MPDDefaultKey.ipAddress.stringValue(self)) ?? userDefaults.string(forKey: MPDDefaultKey.resolvedIpAddress.stringValue(self)) ?? "Unknown"),
         DiagnosticsItem(id: "port", description: "\(attributes.port)"),
         DiagnosticsItem(id: "model", description: model),
         DiagnosticsItem(id: "version", description: version),
         DiagnosticsItem(id: "manual", description: attributes.manual ? "Yes" : "No"),
         DiagnosticsItem(id: "hidden", description: hidden ? "Yes" : "No")
        ]
    }
    
    // MARK: - Initialization and connecting
    
    /// Initialize a new player object
    ///
    /// - Parameters:
    ///   - host: Host ip-address to connect to.
    ///   - port: Port to connect to.
    ///   - password: Password to use when connection, default is ""
    public init(_ attributes: PlayerAttributes,
                  userDefaults: UserDefaults) {
        self.instanceID = attributes.instanceID
        self.userDefaults = userDefaults
        
        // Per-player settings are keyed by uniqueID, so a manual copy never shares them with another player.
        let settingsID = MPDPlayer.uniqueIDForPlayer(host: attributes.host, port: attributes.port, instanceID: attributes.instanceID)
        let storedType = MPDType(rawValue: userDefaults.integer(forKey: MPDDefaultKey.MPDType.stringValue(settingsID)))
        let resolvedType = (storedType != nil && storedType != .unknown) ? storedType! : attributes.type

        // The type's defaults go in before the settings are read below, so a new player starts with them.
        MPDPlayer.storeDefaults(for: resolvedType, settingsID: settingsID, userDefaults: userDefaults)

        let connectToIpAddress = userDefaults.bool(forKey: MPDDefaultKey.connectToIpAddress.stringValue(settingsID))
        let ipAddress = connectToIpAddress ? userDefaults.string(forKey: MPDDefaultKey.ipAddress.stringValue(settingsID)) ?? attributes.host : (userDefaults.string(forKey: MPDDefaultKey.discoveredIpAddress.stringValue(settingsID)) ?? attributes.host)
        let password = userDefaults.string(forKey: MPDDefaultKey.password.stringValue(settingsID)) ?? ""

        let useHttpCoverArt = userDefaults.object(forKey: MPDDefaultKey.useHttpCoverArt.stringValue(settingsID)) as? Bool ?? attributes.useHttpCoverArt
        let albumGrouping = userDefaults.string(forKey: MPDDefaultKey.albumGrouping.stringValue(settingsID)) ?? attributes.albumGrouping
        let coverFilename = userDefaults.string(forKey: MPDDefaultKey.coverPostfix.stringValue(settingsID)) ?? attributes.coverFilename
        let outputHost = userDefaults.string(forKey: MPDDefaultKey.outputHost.stringValue(settingsID)) ?? attributes.outputHost
        let outputPort = (userDefaults.object(forKey: MPDDefaultKey.outputPort.stringValue(settingsID)) as? Int) ?? attributes.outputPort

        let resolvedAttributes = PlayerAttributes(uuid: attributes.uuid,
                                                  name: attributes.name,
                                                  type: resolvedType,
                                                  version: attributes.version,
                                                  host: attributes.host,
                                                  port: attributes.port,
                                                  password: attributes.password,
                                                  useHttpCoverArt: useHttpCoverArt,
                                                  manual: attributes.manual,
                                                  albumGrouping: albumGrouping,
                                                  coverFilename: coverFilename,
                                                  outputHost: outputHost,
                                                  outputPort: outputPort,
                                                  instanceID: attributes.instanceID)

        let mpdConnector = MPDConnector(MPDDeviceSettings(ipAddress: ipAddress, port: attributes.port, password: password, connectTimeout: 3, uuid: attributes.uuid, playerName: attributes.name))
        let mpdIdleConnector = MPDConnector(MPDDeviceSettings(ipAddress: ipAddress, port: attributes.port, password: password, connectTimeout: 3, uuid: attributes.uuid, playerName: attributes.name))
        // The status builds the cover art URLs, so it needs the settings, not just what was decoded.
        self.mpdStatus = MPDStatus.init(attributes: resolvedAttributes,
                                        mpdConnector: mpdConnector,
                                        mpdIdleConnector: mpdIdleConnector)

        var name = attributes.name
        if let customName = userDefaults.string(forKey: MPDDefaultKey.customPlayerName.stringValue(settingsID)),
           !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = customName
        }

        self.state = Mutex(State(name: name,
                                 attributes: resolvedAttributes,
                                 type: resolvedType,
                                 version: attributes.version,
                                 commands: [],
                                 connectionWarning: nil,
                                 mpdConnector: mpdConnector,
                                 mpdIdleConnector: mpdIdleConnector))

        Task { [weak self] in
            guard let self else { return }
            let commands = (try? await self.mpdConnector.status.commands()) ?? []
            self.commands = commands
        }
    }
    
    // MARK: - PlayerProtocol Implementations
    
    /// Upon activation, the status object starts monitoring the player status.
    public func activate() {
        mpdStatus.start()
    }
    
    /// Upon deactivation, the shared status object starts monitoring the player status, and open connections are closed.
    public func deactivate() {
        mpdStatus.stop()
    }

    /// Rebuild the underlying connectors using the latest connection settings (host, password)
    /// from UserDefaults. Existing connections are torn down so the next operation reconnects
    /// with the new credentials. Streams exposed via `status` are preserved.
    public func applyConnectionSettingsChange() {
        let connectToIpAddress = userDefaults.bool(forKey: MPDDefaultKey.connectToIpAddress.stringValue(self))
        let ipAddress = connectToIpAddress ? userDefaults.string(forKey: MPDDefaultKey.ipAddress.stringValue(self)) ?? attributes.host : (userDefaults.string(forKey: MPDDefaultKey.discoveredIpAddress.stringValue(self)) ?? attributes.host)
        let password = userDefaults.string(forKey: MPDDefaultKey.password.stringValue(self)) ?? ""

        let newMpdConnector = MPDConnector(MPDDeviceSettings(ipAddress: ipAddress, port: attributes.port, password: password, connectTimeout: 3, uuid: attributes.uuid, playerName: attributes.name))
        let newMpdIdleConnector = MPDConnector(MPDDeviceSettings(ipAddress: ipAddress, port: attributes.port, password: password, connectTimeout: 3, uuid: attributes.uuid, playerName: attributes.name))

        let oldMpdConnector = self.mpdConnector
        self.mpdConnector = newMpdConnector
        self.mpdIdleConnector = newMpdIdleConnector
        mpdStatus.replaceConnectors(mpdConnector: newMpdConnector, mpdIdleConnector: newMpdIdleConnector)

        Task {
            await oldMpdConnector.closeConnection()
        }
    }

    /// Settings some types need to work well. They only fill in what the user hasn't set.
    static func storeDefaults(for type: MPDType, settingsID: String, userDefaults: UserDefaults) {
        func setIfMissing(_ value: Any, _ key: MPDDefaultKey) {
            if userDefaults.object(forKey: key.stringValue(settingsID)) == nil {
                userDefaults.set(value, forKey: key.stringValue(settingsID))
            }
        }
        switch type {
        case .chord:
            setIfMissing(true, .connectToIpAddress)
        case .bryston:
            setIfMissing(true, .useHttpCoverArt)
            setIfMissing("albumartist", .albumGrouping)
            setIfMissing("bdp_front_250.jpg", .coverPostfix)
        default:
            break
        }
    }

    /// Switch to another type, as chosen in the player settings. The type ends up in the attributes, which the
    /// cover art URLs and the stored player definition are built from.
    func changeType(_ type: MPDType) {
        self.type = type
        userDefaults.set(type.rawValue, forKey: MPDDefaultKey.MPDType.stringValue(self))
        MPDPlayer.storeDefaults(for: type, settingsID: uniqueID, userDefaults: userDefaults)
        attributes = PlayerAttributes(uuid: attributes.uuid,
                                      name: attributes.name,
                                      type: type,
                                      version: attributes.version,
                                      host: attributes.host,
                                      port: attributes.port,
                                      password: attributes.password,
                                      useHttpCoverArt: userDefaults.object(forKey: MPDDefaultKey.useHttpCoverArt.stringValue(self)) as? Bool ?? attributes.useHttpCoverArt,
                                      manual: attributes.manual,
                                      albumGrouping: userDefaults.string(forKey: MPDDefaultKey.albumGrouping.stringValue(self)) ?? attributes.albumGrouping,
                                      coverFilename: userDefaults.string(forKey: MPDDefaultKey.coverPostfix.stringValue(self)) ?? attributes.coverFilename,
                                      outputHost: attributes.outputHost,
                                      outputPort: attributes.outputPort,
                                      instanceID: instanceID)
        objectWillChange.send()
    }

    /// Create a copy of a player
    ///
    /// - Returns: copy of the this player
    public func copy() -> any PlayerProtocol {
        return MPDPlayer.init(attributes, userDefaults: userDefaults)
    }
    
    public func finishDiscovery() async throws {
        let tagTypes = try await mpdConnector.status.tagtypes()
        let commands = try await mpdConnector.status.commands()

        let version = mpdConnector.version
        var connectionWarning: String? = nil
        if version < SwiftMPD.MPDConnection.Version("0.19.0") {
            connectionWarning = "MPD version \(version) too low, 0.19.0 required"
        }

        if connectionWarning == nil {
            var missingTagTypes = [String]()
            if tagTypes.contains("AlbumArtist") == false && tagTypes.contains("albumartist") == false {
                missingTagTypes.append("albumartist")
            }
            if tagTypes.contains("ArtistSort") == false && tagTypes.contains("artistsort") == false {
                missingTagTypes.append("artistsort")
            }
            if tagTypes.contains("AlbumArtistSort") == false && tagTypes.contains("albumartistsort") == false {
                missingTagTypes.append("albumartistsort")
            }
            if missingTagTypes.count == 1 {
                connectionWarning = "id3-tag \(missingTagTypes[0]) is not configured"
            }
            else if missingTagTypes.count > 1 {
                connectionWarning = "id3-tags "
                for tag in missingTagTypes {
                    if connectionWarning! != "id3-tags " {
                        connectionWarning! += ", "
                    }
                    connectionWarning! += tag
                }
                connectionWarning! += " are not configured"
            }
        }

        await MainActor.run {
            self.commands = commands
            self.version = version.description
            self.connectionWarning = connectionWarning
        }
    }
    
    public func favourites() async throws -> [FoundItem] {
        []
    }
    
    public func ping() async -> Bool {
        await mpdConnector.ping(close: true)
    }
    
    @MainActor @ViewBuilder
    public func settingsView(deleteAction: ((any PlayerProtocol) -> ())?,
                             hideAction: ((any PlayerProtocol) -> ())?) -> some View {
        MPDSettingsView(player: self, deleteAction: deleteAction, hideAction: hideAction)
    }
}

extension MPDPlayer : Equatable {
    public static func ==(lhs: MPDPlayer, rhs: MPDPlayer) -> Bool {
        return lhs.uniqueID == rhs.uniqueID
    }
}
