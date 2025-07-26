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

enum ConnectionError: Error {
    case internalError
}

public enum MPDType: Int {
    case unknown = 0
    case classic = 1
    case mopidy = 2
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
        case .mopidy:
            return "Mopidy"
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
}

public enum MPDConnectionProperties: String {
    case MPDType = "type"
    case coverHttpPort = "MPD.Uri.Port"
    case coverPrefix = "MPD.Uri.Prefix"
    case coverPostfix = "MPD.Uri.Postfix"
    case alternativeCoverPostfix = "MPD.Uri.AlternativePostfix"
    case alternativeCoverHost = "MPD.Uri.AlternativeCoverHost"
    case version = "MPD.Version"
    case outputHost = "MPD.Output.Host"
    case outputPort = "MPD.Output.Port"
    case ipAddress = "MPD.IpAddress"
    case connectToIpAddress = "MPD.ConnectToIpAddress"
}

public class MPDPlayer: PlayerProtocol {
    public var mediaServerModel: String = "MPD"

    public var mediaAvailable: Bool = true

    public var mediaServers: [BrowseProtocol] = []

    public func selectMediaServer(_ mediaServer: BrowseProtocol, source: ConnectorProtocol.SourceType) {
    }

    private let userDefaults: UserDefaults
    public static let controllerType = "MPD"
    
    public private(set) var name: String
    public var controllerType: String {
        return MPDPlayer.controllerType
    }
    public private(set) var discoverMode = DiscoverMode.automatic
    
    private var host: String
    private var ipAddress: String?
    private var port: Int
    //private var password: String
    public private(set) var type: MPDType
    private var uuid = UUID()
    
    public private(set) var version: String
    
    public private(set) var connectionWarning: String?
    
    private let mpdConnector: SwiftMPD.MPDConnector
    private let mpdIdleConnector: SwiftMPD.MPDConnector
    
    public var description: String {
        return type.description + " " + version
    }
    
    private var commands: [String]
    public var supportedFunctions: [Functions] {
        return [.radio, .randomSongs, .randomAlbums, .composers, .performers, .conductors, .quality, .recentlyAddedAlbums, .stream, .playlists, .volumeAdjustment] + (commands.contains("albumart") ? [.binaryImageRetrieval] : [])  + (commands.contains("readpicture") ? [.embeddedImageRetrieval] : [])
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
        return uniqueIDForPlayer(host: player.host, port: player.port)
    }
    
    public static func uniqueIDForPlayer(host: String, port: Int) -> String {
        return "\(host):\(port)"
    }
    
    public var model: String {
        get {
            return type.description
        }
    }
    
    public var connectionProperties: [String: Any] {
        get {
            return [ConnectionProperties.controllerType.rawValue: MPDPlayer.controllerType,
                    ConnectionProperties.name.rawValue: name,
                    ConnectionProperties.host.rawValue: host,
                    ConnectionProperties.port.rawValue: port,
                    MPDConnectionProperties.ipAddress.rawValue: ipAddress ?? "",
                    MPDConnectionProperties.MPDType.rawValue: type.rawValue,
                    MPDConnectionProperties.version.rawValue: version]
        }
    }
    
  
    /// Create a unique object for every request for a control object
    public var control: ControlProtocol {
        get {
            // Use serialScheduler to synchronize commands across multiple MPDControl instances.
            return MPDControl.init(connectionProperties: connectionProperties, identification: uniqueID, userDefaults: userDefaults, mpdConnector: mpdConnector)
        }
    }
    /// Create a unique object for every request for a browse object
    public var browse: BrowseProtocol {
        get {
            return MPDBrowse.init(connectionProperties: connectionProperties, identification: uniqueID, mpdConnector: mpdConnector)
        }
    }
    
    public func browse(source: SourceType) -> (BrowseProtocol)? {
        browse
    }

    public var playerStreamURL: URL? {
        guard let hostString = connectionProperties[MPDConnectionProperties.outputHost.rawValue] as? String, hostString != "",
              let portString = connectionProperties[MPDConnectionProperties.outputPort.rawValue] as? String, let port = Int(portString), port != 0
        else { return nil }
        
        return URL(string: "http://\(hostString):\(port)")
    }
    
    // MARK: - Initialization and connecting
    
    /// Initialize a new player object
    ///
    /// - Parameters:
    ///   - host: Host ip-address to connect to.
    ///   - port: Port to connect to.
    ///   - password: Password to use when connection, default is ""
    public init(name: String,
                host: String,
                ipAddress: String?,
                port: Int,
                password: String? = nil,
                type: MPDType = .classic,
                version: String = "",
                discoverMode: DiscoverMode = .automatic,
                connectionWarning: String? = nil,
                userDefaults: UserDefaults,
                commands: [String] = []) {
        self.userDefaults = userDefaults
        self.name = name
        self.host = host
        self.ipAddress = ipAddress
        self.port = port
        self.connectionWarning = connectionWarning
        self.commands = commands
        self.version = version
        self.discoverMode = discoverMode
        self.type = type
        
        let connectionProperties = [ConnectionProperties.name.rawValue: name,
                                    ConnectionProperties.host.rawValue: host,
                                    ConnectionProperties.port.rawValue: port,
                                    MPDConnectionProperties.ipAddress.rawValue: ipAddress ?? "",
                                    MPDConnectionProperties.MPDType.rawValue: type,
                                    MPDConnectionProperties.version.rawValue: version] as [String : Any]
        
        let hostToUse = MPDHelper.hostToUse(connectionProperties)
        self.mpdConnector = MPDConnector(MPDDeviceSettings(ipAddress: hostToUse, port: port, password: password, connectTimeout: 3, uuid: uuid, playerName: name))
        self.mpdIdleConnector = MPDConnector(MPDDeviceSettings(ipAddress: hostToUse, port: port, password: password, connectTimeout: 3, uuid: uuid, playerName: name))
        self.mpdStatus = MPDStatus.init(connectionProperties: connectionProperties,
                                        userDefaults: userDefaults,
                                        mpdConnector: mpdConnector,
                                        mpdIdleConnector: mpdIdleConnector)
    }
    
    /// Init an instance of a MPDPlayer based on a connectionProperties dictionary
    ///
    /// - Parameters:
    ///   - connectionProperties: dictionary of properties
    public convenience init(connectionProperties: [String: Any],
                            type: MPDType = .classic,
                            version: String = "",
                            discoverMode: DiscoverMode = .automatic,
                            connectionWarning: String? = nil,
                            userDefaults: UserDefaults,
                            commands: [String] = []) async {
        guard let name = connectionProperties[ConnectionProperties.name.rawValue] as? String,
              let host = connectionProperties[ConnectionProperties.host.rawValue] as? String,
              let port = connectionProperties[ConnectionProperties.port.rawValue] as? Int else {
            self.init(name: "",
                      host: "",
                      ipAddress: connectionProperties[MPDConnectionProperties.ipAddress.rawValue] as? String,
                      port: 6600,
                      type: type,
                      version: version,
                      discoverMode: discoverMode,
                      connectionWarning: connectionWarning,
                      userDefaults: userDefaults,
                      commands: commands)
            return
        }
        
        
        self.init(name: name,
                  host: host,
                  ipAddress: connectionProperties[MPDConnectionProperties.ipAddress.rawValue] as? String,
                  port: port,
                  password: connectionProperties[ConnectionProperties.password.rawValue] as? String,
                  type: type,
                  version: version != "" ? version : (connectionProperties[MPDConnectionProperties.version.rawValue] as? String ?? ""),
                  discoverMode: discoverMode,
                  connectionWarning: connectionWarning,
                  userDefaults: userDefaults,
                  commands: commands)
        
        if commands.count == 0 {
            self.commands = (try? await (browse as! MPDBrowse).availableCommands()) ?? []
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
    public func copy() async -> PlayerProtocol {
        return await MPDPlayer.init(connectionProperties: connectionProperties, type: type, version: version, userDefaults: userDefaults, commands: commands)
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
            
            if userDefaults.value(forKey: ConnectionProperties.binaryCoverArt.rawValue + "." + uniqueID) == nil {
                userDefaults.set(self.supportedFunctions.contains(.binaryImageRetrieval), forKey: ConnectionProperties.binaryCoverArt.rawValue + "." + uniqueID)
                userDefaults.set(self.supportedFunctions.contains(.embeddedImageRetrieval), forKey: ConnectionProperties.embeddedCoverArt.rawValue + "." + uniqueID)
                if !self.supportedFunctions.contains(.binaryImageRetrieval) && !self.supportedFunctions.contains(.embeddedImageRetrieval) {
                    userDefaults.set(true, forKey: ConnectionProperties.urlCoverArt.rawValue + "." + uniqueID)
                }
                else {
                    userDefaults.set(false, forKey: ConnectionProperties.urlCoverArt.rawValue + "." + uniqueID)
                }
                userDefaults.set(false, forKey: ConnectionProperties.discogsCoverArt.rawValue + "." + uniqueID)
                userDefaults.set(false, forKey: ConnectionProperties.musicbrainzCoverArt.rawValue + "." + uniqueID)
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
}

extension MPDPlayer : Equatable {
    public static func ==(lhs: MPDPlayer, rhs: MPDPlayer) -> Bool {
        return lhs.uniqueID == rhs.uniqueID
    }
}
