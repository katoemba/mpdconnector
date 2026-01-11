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
        public init(uuid: UUID, name: String, version: String, ipAddress: String? = nil, host: String, port: Int, password: String? = nil, type: MPDType, coverHttpPort: String? = nil, coverPrefix: String? = nil, coverPostfix: String? = nil, alternativeCoverPostfix: String? = nil, alternativeCoverHost: String? = nil, outputHost: String? = nil, outputPort: String? = nil, connectToIpAddress: Bool? = nil, customPlayerName: String? = nil, hidden: Bool? = nil) {
            self.uuid = uuid
            self.name = name
            self.version = version
            self.ipAddress = ipAddress
            self.host = host
            self.port = port
            self.password = password
            self.type = type
            self.coverHttpPort = coverHttpPort
            self.coverPrefix = coverPrefix
            self.coverPostfix = coverPostfix
            self.alternativeCoverPostfix = alternativeCoverPostfix
            self.alternativeCoverHost = alternativeCoverHost
            self.outputHost = outputHost
            self.outputPort = outputPort
            self.connectToIpAddress = connectToIpAddress
            self.customPlayerName = customPlayerName
            self.hidden = hidden
        }
        
        // identification
        let uuid: UUID
        let type: MPDType

        // player network attributes
        let name: String
        let version: String
        let host: String
        let port: Int
        
        // player settings
        let ipAddress: String?
        let password: String?
        let coverHttpPort: String?
        let coverPrefix: String?
        let coverPostfix: String?
        let alternativeCoverPostfix: String?
        let alternativeCoverHost: String?
        let outputHost: String?
        let outputPort: String?
        let connectToIpAddress: Bool?
        let customPlayerName: String?
        let hidden: Bool?
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
    
    internal var attributes: PlayerAttributes {
        didSet {
            name = attributes.name
        }
    }
    
    public internal(set) var type: MPDType
    private var uuid = UUID()
    
    public private(set) var version: String
    public var hidden: Bool {
        return userDefaults.bool(forKey: defaultsKey(MPDDefaultKey.hidden.rawValue))
    }

    public private(set) var connectionWarning: String?
    
    internal let mpdConnector: SwiftMPD.MPDConnector
    private let mpdIdleConnector: SwiftMPD.MPDConnector
    
    public var description: String {
        return type.description + " " + version
    }
    
    private var commands: [String]
    public var supportedFunctions: [Functions] {
        return [.repeatSingle, .consume, .radio, .randomSongs, .randomAlbums, .composers, .performers, .conductors, .quality, .recentlyAddedAlbums, .stream, .playlists, .volumeAdjustment] + (commands.contains("albumart") ? [.binaryImageRetrieval] : [])  + (commands.contains("readpicture") ? [.embeddedImageRetrieval] : [])
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
//        let hostString = outputHostProp ?? ""
//        let portString = outputPortProp ?? ""
//        guard !hostString.isEmpty, let port = Int(portString), port != 0 else { return nil }
//        return URL(string: "http://\(hostString):\(port)")
        return nil
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
        self.type = attributes.type
        self.version = attributes.version
        self.commands = []
        
        self.mpdConnector = MPDConnector(MPDDeviceSettings(ipAddress: attributes.host, port: attributes.port, password: attributes.password, connectTimeout: 3, uuid: attributes.uuid, playerName: attributes.name))
        self.mpdIdleConnector = MPDConnector(MPDDeviceSettings(ipAddress: attributes.host, port: attributes.port, password: attributes.password, connectTimeout: 3, uuid: attributes.uuid, playerName: attributes.name))
        self.mpdStatus = MPDStatus.init(attributes: attributes,
                                        mpdConnector: mpdConnector,
                                        mpdIdleConnector: mpdIdleConnector)
        Task {
            self.commands = (try? await self.mpdConnector.status.commands()) ?? []
        }

        if attributes.type == .chord {
            let key = MPDDefaultKey.connectToIpAddress.stringValue(self)
            if userDefaults.value(forKey: key) == nil {
                userDefaults.set(true, forKey: key)
            }
        }

        let key = MPDDefaultKey.MPDType.stringValue(self)
        if userDefaults.object(forKey: key) != nil, let storedType = MPDType(rawValue: userDefaults.integer(forKey: key)) {
            self.type = storedType
        }
        else {
            self.type = attributes.type
        }

        let customName = userDefaults.string(forKey: defaultsKey(MPDDefaultKey.customPlayerName.rawValue))
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
    
    /// Create a copy of a player
    ///
    /// - Returns: copy of the this player
    public func copy() -> any PlayerProtocol {
        return MPDPlayer.init(attributes, userDefaults: userDefaults)
    }
    
    public func finishDiscovery() {
        Task {
            let tagTypes = try await mpdConnector.status.tagtypes()
            self.commands = try await mpdConnector.status.commands()
            
            let version = mpdConnector.version
            self.version = version.description
            if version < SwiftMPD.MPDConnection.Version("0.19.0") {
                connectionWarning = "MPD version \(version) too low, 0.19.0 required"
            }
            
            if userDefaults.value(forKey: MPDDefaultKey.binaryCoverArt.stringValue(self)) == nil {
                userDefaults.set(self.supportedFunctions.contains(.binaryImageRetrieval), forKey: MPDDefaultKey.binaryCoverArt.stringValue(self))
                userDefaults.set(self.supportedFunctions.contains(.embeddedImageRetrieval), forKey: MPDDefaultKey.embeddedCoverArt.stringValue(self))
                if !self.supportedFunctions.contains(.binaryImageRetrieval) && !self.supportedFunctions.contains(.embeddedImageRetrieval) {
                    userDefaults.set(true, forKey: MPDDefaultKey.urlCoverArt.stringValue(self))
                }
                else {
                    userDefaults.set(false, forKey: MPDDefaultKey.urlCoverArt.stringValue(self))
                }
                userDefaults.set(false, forKey: MPDDefaultKey.discogsCoverArt.stringValue(self))
                userDefaults.set(false, forKey: MPDDefaultKey.musicbrainzCoverArt.stringValue(self))
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
        }
    }
    
    public func favourites() async throws -> [FoundItem] {
        []
    }
    
    public func ping() async -> Bool {
        await mpdConnector.ping()
    }
    
    @ViewBuilder
    public func settingsView() -> some View {
        MPDSettingsView(player: self)
    }
}

extension MPDPlayer : Equatable {
    public static func ==(lhs: MPDPlayer, rhs: MPDPlayer) -> Bool {
        return lhs.uniqueID == rhs.uniqueID
    }
}
