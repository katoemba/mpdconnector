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

enum ConnectionError: Error {
    case internalError
}

public enum MPDType: Int, Codable, CaseIterable {
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

public class MPDPlayer: PlayerProtocol, ObservableObject {
    public struct PlayerAttributes: Codable {
        public init(uuid: UUID, name: String, type: MPDType, version: String, ipAddress: String? = nil, host: String, port: Int, password: String?, useHttpCoverArt: Bool, manual: Bool, albumGrouping: String, coverFilename: String, outputHost: String, outputPort: Int) {
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
    }
    
    public var mediaServerModel: String = "MPD"
    
    public var mediaAvailable: Bool = true
    
    public var mediaServers: [BrowseProtocol] = []
    
    public func selectMediaServer(_ mediaServer: BrowseProtocol, source: ConnectorProtocol.SourceType) {
    }
    
    internal let userDefaults: UserDefaults
    public static let controllerType = "MPD"
    
    public var deviceName: String {
        return attributes.name
    }
    @Published public var name: String

    public var controllerType: String {
        return MPDPlayer.controllerType
    }
    public private(set) var discoverMode = DiscoverMode.automatic
    
    public internal(set) var attributes: PlayerAttributes {
        didSet {
            let customName = userDefaults.string(forKey: MPDDefaultKey.customPlayerName.stringValue(self))
            if let customName = customName, !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                name = customName
            }
            else {
                name = attributes.name
            }
        }
    }
    
    public internal(set) var type: MPDType
    private var uuid = UUID()
    
    public private(set) var version: String
    public var hidden: Bool {
        return userDefaults.bool(forKey: MPDDefaultKey.hidden.stringValue(self))
    }

    public private(set) var connectionWarning: String?
    
    internal private(set) var mpdConnector: SwiftMPD.MPDConnector
    private var mpdIdleConnector: SwiftMPD.MPDConnector
    
    public var description: String {
        return type.description + " " + version
    }
    
    private var commands: [String]
    public var supportedFunctions: [Functions] {
        return [.playRecursiveFolder, .repeatSingle, .consume, .radio, .randomSongs, .randomAlbums, .composers, .performers, .conductors, .quality, .recentlyAddedAlbums, .stream, .playlists, .volumeAdjustment] + (commands.contains("albumart") ? [.binaryImageRetrieval] : [])  + (commands.contains("readpicture") ? [.embeddedImageRetrieval] : [])
    }
    
    /// Current status
    private var mpdStatus: MPDStatus
    public var status: StatusProtocol {
        return mpdStatus
    }
    
    public var uniqueID: String {
        get {
            return "\(MPDPlayer.uniqueIDForPlayer(self))"
        }
    }
    
    private static func uniqueIDForPlayer(_ player: MPDPlayer) -> String {
        return uniqueIDForPlayer(host: player.attributes.host, port: player.attributes.port)
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
    
    public static func decodePlayer(_ data: Data, userDefaults: UserDefaults) async throws -> Self {
        let decodedPlayer = try JSONDecoder().decode(PlayerAttributes.self, from: data)
        return MPDPlayer(decodedPlayer, userDefaults: userDefaults) as! Self
    }
    
    public func playerDefinition() throws -> ConnectorProtocol.PlayerDefinition {
        try ConnectorProtocol.PlayerDefinition(id: uniqueID,
                                               name: name,
                                               type: controllerType,
                                               typeSpecificData: encodePlayer())
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
         DiagnosticsItem(id: "connect to ip address", description: userDefaults.bool(forKey: MPDDefaultKey.connectToIpAddress.stringValue(host: attributes.host, port: attributes.port)) ? "Yes" : "No"),
         DiagnosticsItem(id: "ip address", description: userDefaults.string(forKey: MPDDefaultKey.ipAddress.stringValue(host: attributes.host, port: attributes.port)) ?? "Unknown"),
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
        self.attributes = attributes
        self.userDefaults = userDefaults
        self.name = attributes.name
        self.version = attributes.version
        self.type = attributes.type

        self.commands = []
        
        let connectToIpAddress = userDefaults.bool(forKey: MPDDefaultKey.connectToIpAddress.stringValue(host: attributes.host, port: attributes.port))
        let ipAddress = connectToIpAddress ? userDefaults.string(forKey: MPDDefaultKey.ipAddress.stringValue(host: attributes.host, port: attributes.port)) ?? attributes.host : attributes.host
        let password = userDefaults.string(forKey: MPDDefaultKey.password.stringValue(host: attributes.host, port: attributes.port)) ?? ""
        
        self.mpdConnector = MPDConnector(MPDDeviceSettings(ipAddress: ipAddress, port: attributes.port, password: password, connectTimeout: 3, uuid: attributes.uuid, playerName: attributes.name))
        self.mpdIdleConnector = MPDConnector(MPDDeviceSettings(ipAddress: ipAddress, port: attributes.port, password: password, connectTimeout: 3, uuid: attributes.uuid, playerName: attributes.name))
        self.mpdStatus = MPDStatus.init(attributes: attributes,
                                        mpdConnector: mpdConnector,
                                        mpdIdleConnector: mpdIdleConnector)
        Task { [weak self] in
            guard let self else { return }
            let commands = (try? await self.mpdConnector.status.commands()) ?? []
            await MainActor.run { self.commands = commands }
        }

        let storedType = MPDType(rawValue: userDefaults.integer(forKey: MPDDefaultKey.MPDType.stringValue(self)))
        let resolvedType = (storedType != nil && storedType != .unknown) ? storedType! : attributes.type
        self.type = resolvedType

        let useHttpCoverArt = userDefaults.object(forKey: MPDDefaultKey.useHttpCoverArt.stringValue(self)) as? Bool ?? attributes.useHttpCoverArt
        let albumGrouping = userDefaults.string(forKey: MPDDefaultKey.albumGrouping.stringValue(self)) ?? attributes.albumGrouping
        let coverFilename = userDefaults.string(forKey: MPDDefaultKey.coverPostfix.stringValue(self)) ?? attributes.coverFilename
        let outputHost = userDefaults.string(forKey: MPDDefaultKey.outputHost.stringValue(self)) ?? attributes.outputHost
        let outputPort = (userDefaults.object(forKey: MPDDefaultKey.outputPort.stringValue(self)) as? Int) ?? attributes.outputPort

        self.attributes = PlayerAttributes(uuid: attributes.uuid,
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
                                           outputPort: outputPort)

        if attributes.type == .chord {
            if userDefaults.value(forKey: MPDDefaultKey.connectToIpAddress.stringValue(self)) == nil {
                userDefaults.set(true, forKey: MPDDefaultKey.connectToIpAddress.stringValue(self))
            }
        }

        if attributes.type == .bryston {
            if userDefaults.value(forKey: MPDDefaultKey.useHttpCoverArt.stringValue(self)) == nil {
                userDefaults.set(true, forKey: MPDDefaultKey.useHttpCoverArt.stringValue(self))
            }
            if userDefaults.value(forKey: MPDDefaultKey.albumGrouping.stringValue(self)) == nil {
                userDefaults.set("albumartist", forKey: MPDDefaultKey.albumGrouping.stringValue(self))
            }
            if userDefaults.value(forKey: MPDDefaultKey.coverPostfix.stringValue(self)) == nil {
                userDefaults.set("bdp_front_250.jpg", forKey: MPDDefaultKey.coverPostfix.stringValue(self))
            }
        }

        let customName = userDefaults.string(forKey: MPDDefaultKey.customPlayerName.stringValue(self))
        if let customName = customName, !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.name = customName
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
        let connectToIpAddress = userDefaults.bool(forKey: MPDDefaultKey.connectToIpAddress.stringValue(host: attributes.host, port: attributes.port))
        let ipAddress = connectToIpAddress ? userDefaults.string(forKey: MPDDefaultKey.ipAddress.stringValue(host: attributes.host, port: attributes.port)) ?? attributes.host : attributes.host
        let password = userDefaults.string(forKey: MPDDefaultKey.password.stringValue(host: attributes.host, port: attributes.port)) ?? ""

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
    
    @ViewBuilder
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
