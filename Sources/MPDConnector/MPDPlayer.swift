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
import libmpdclient
import RxSwift

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
}

public class MPDPlayer: PlayerProtocol {
    private let userDefaults: UserDefaults
    private let mpd: MPDProtocol

    private var _name: String
    public var name: String {
        return _name
    }
    
    public var controllerType: String {
        return "MPD"
    }
    private var _discoverMode = DiscoverMode.automatic
    public var discoverMode: DiscoverMode {
        return _discoverMode
    }
    
    private var host: String
    private var port: Int
    //private var password: String
    private var _type: MPDType
    public var type: MPDType {
        return _type
    }
    
    private var _version: String
    public var version: String {
        return _version
    }
    
    private var _connectionWarning = nil as String?
    public var connectionWarning: String? {
        return _connectionWarning
    }
    
    public var description: String {
        return _type.description + " " + _version
    }
    
    public var supportedFunctions: [Functions] {
        return [.randomSongs, .randomAlbums, .composers, .performers, .quality, .recentlyAddedAlbums]
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

    static func uniqueIDForPlayer(host: String, port: Int) -> String {
        return "\(host):\(port)"
    }

    public var model: String {
        get {
            return type.description
        }
    }
    
    public var connectionProperties: [String: Any] {
        get {
            let alternativCoverHost = (self.loadSetting(id: MPDConnectionProperties.alternativeCoverHost.rawValue) as? StringSetting)?.value ?? ""
            let coverHttpPort = (self.loadSetting(id: MPDConnectionProperties.coverHttpPort.rawValue) as? StringSetting)?.value ?? ""
            let prefix = (self.loadSetting(id: MPDConnectionProperties.coverPrefix.rawValue) as? StringSetting)?.value ?? ""
            let postfix = (self.loadSetting(id: MPDConnectionProperties.coverPostfix.rawValue) as? StringSetting)?.value ?? ""
            let alternativePostfix = (self.loadSetting(id: MPDConnectionProperties.alternativeCoverPostfix.rawValue) as? StringSetting)?.value ?? ""
            let password = (self.loadSetting(id: ConnectionProperties.Password.rawValue) as? StringSetting)?.value ?? ""
            return [ConnectionProperties.Name.rawValue: name,
                    ConnectionProperties.Host.rawValue: host,
                    ConnectionProperties.Port.rawValue: port,
                    ConnectionProperties.Password.rawValue: password,
                    MPDConnectionProperties.alternativeCoverHost.rawValue: alternativCoverHost,
                    MPDConnectionProperties.coverHttpPort.rawValue: coverHttpPort,
                    MPDConnectionProperties.coverPrefix.rawValue: prefix,
                    MPDConnectionProperties.coverPostfix.rawValue: postfix,
                    MPDConnectionProperties.alternativeCoverPostfix.rawValue: alternativePostfix,
                    MPDConnectionProperties.MPDType.rawValue: type.rawValue,
                    MPDConnectionProperties.version.rawValue: version]
        }
    }
    
    public var settings: [PlayerSettingGroup] {
        get {
            let mpdDBStatusObservable = (self.browse as! MPDBrowse).databaseStatus()
            let reloadingObservable = Observable<Int>
                .interval(RxTimeInterval.seconds(2), scheduler: MainScheduler.instance)
                .flatMap( { _ in
                    mpdDBStatusObservable
                })
            
            var coverArtDescription = ""
            if type == .runeaudio {
                coverArtDescription = "To enable cover art retrieval from a Rune Audio player, you need to configure the internal webserver:\n\n" +
                "1 - Login to the player: ssh root@\(host) (the default password is 'rune')\n" +
                "2 - Enter the following command: ln -s /mnt/MPD   /var/www/music\n" +
                "3 - Make sure the specified Cover Filename matches the artwork filename you use in each folder"
            }
            else if type == .bryston {
                coverArtDescription = "For a Bryston player, make sure the specified Cover Filename matches the artwork filename you use in each folder."
            }
            else if type == .volumio {
                coverArtDescription = "For a Volumio based player, the default cover art settings should not be changed."
            }
            else if type == .moodeaudio {
                coverArtDescription = "For a moOde based player, the default cover art settings should not be changed."
            }
            else if type == .classic {
                coverArtDescription = "To enable cover art retrieval, a webserver needs to be running on the player, normally on port 80. This webserver must be configured to support browsing the music directories.\n\n" +
                "Make sure the specified Cover Filename matches the artwork filename you use in each folder."
            }
            return [PlayerSettingGroup(title: "Player Type", description: "", settings:[loadSetting(id: MPDConnectionProperties.MPDType.rawValue)!,
                                                                                        loadSetting(id: ConnectionProperties.Password.rawValue)!]),
                    PlayerSettingGroup(title: "Cover Art", description: coverArtDescription, settings:[loadSetting(id: MPDConnectionProperties.coverPrefix.rawValue)!,
                                                                                                       loadSetting(id: MPDConnectionProperties.coverHttpPort.rawValue)!,
                                                                                                       loadSetting(id: MPDConnectionProperties.coverPostfix.rawValue)!,
                                                                                                       loadSetting(id: MPDConnectionProperties.alternativeCoverPostfix.rawValue)!,
                                                                                                       loadSetting(id: MPDConnectionProperties.alternativeCoverHost.rawValue)!]),
                    PlayerSettingGroup(title: "MPD Database", description: "", settings:[DynamicSetting.init(id: "MPDDBStatus", description: "Database Status", titleObservable: Observable.merge(mpdDBStatusObservable, reloadingObservable)),
                                                                                         ActionSetting.init(id: "MPDReload", description: "Update DB", action: { () -> Observable<String> in
                                                                                            (self.browse as! MPDBrowse).updateDB()
                                                                                            return Observable.just("Update initiated")
                    })])]
        }
    }
    
    /// Create a unique object for every request for a control object
    public var control: ControlProtocol {
        get {
            // Use serialScheduler to synchronize commands across multiple MPDControl instances.
            return MPDControl.init(mpd: mpd, connectionProperties: connectionProperties, identification: uniqueID, scheduler: serialScheduler)
        }
    }
    /// Create a unique object for every request for a browse object
    public var browse: BrowseProtocol {
        get {
            return MPDBrowse.init(mpd: mpd, connectionProperties: connectionProperties, identification: uniqueID, scheduler: scheduler)
        }
    }

    // Test scheduler that can be passed down to mpdstatus, mpdcontrol, and mpdbrowse
    private var scheduler: SchedulerType?
    // Serial scheduler that is used to synchronize commands sent via mpdcontrol
    private var serialScheduler: SchedulerType?
    private let bag = DisposeBag()

    // MARK: - Initialization and connecting
    
    /// Initialize a new player object
    ///
    /// - Parameters:
    ///   - host: Host ip-address to connect to.
    ///   - port: Port to connect to.
    ///   - password: Password to use when connection, default is ""
    public init(mpd: MPDProtocol? = nil,
                name: String,
                host: String,
                port: Int,
                password: String? = nil,
                scheduler: SchedulerType? = nil,
                type: MPDType = .classic,
                version: String = "",
                discoverMode: DiscoverMode = .automatic,
                connectionWarning: String? = nil,
                userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
        self.mpd = mpd ?? MPDWrapper()
        self._name = name
        self.host = host
        self.port = port
        self.scheduler = scheduler
        self.serialScheduler = scheduler ?? SerialDispatchQueueScheduler.init(qos: .background, internalSerialQueueName: "com.katoemba.mpdplayer")
        self._connectionWarning = connectionWarning
        _version = version
        _discoverMode = discoverMode
        let initialUniqueID = MPDPlayer.uniqueIDForPlayer(host: host, port: port)
        
        if password != nil {
            userDefaults.set(password, forKey: ConnectionProperties.Password.rawValue + "." + initialUniqueID)
        }
        let password = userDefaults.string(forKey: "\(ConnectionProperties.Password.rawValue).\(initialUniqueID)") ?? ""
        let defaultTypeInt = userDefaults.integer(forKey: "\(MPDConnectionProperties.MPDType.rawValue).\(initialUniqueID)")
        if defaultTypeInt > 0 {
            _type = MPDType(rawValue: defaultTypeInt)!
        }
        else {
            // Note: using _name here instead of _uniqueId because that is not yet available.
            if type == MPDType.volumio {
                userDefaults.set("albumart?path=", forKey: MPDConnectionProperties.coverPrefix.rawValue + "." + initialUniqueID)
                userDefaults.set("", forKey: MPDConnectionProperties.coverPostfix.rawValue + "." + initialUniqueID)
                userDefaults.set("", forKey: MPDConnectionProperties.alternativeCoverPostfix.rawValue + "." + initialUniqueID)
                userDefaults.set("", forKey: MPDConnectionProperties.alternativeCoverHost.rawValue + "." + initialUniqueID)
            }
            else if type == MPDType.bryston {
                userDefaults.set("music/", forKey: MPDConnectionProperties.coverPrefix.rawValue + "." + initialUniqueID)
                userDefaults.set("Folder.jpg", forKey: MPDConnectionProperties.coverPostfix.rawValue + "." + initialUniqueID)
                userDefaults.set("bdp_front_250.jpg", forKey: MPDConnectionProperties.alternativeCoverPostfix.rawValue + "." + initialUniqueID)
                userDefaults.set("", forKey: MPDConnectionProperties.alternativeCoverHost.rawValue + "." + initialUniqueID)
            }
            else if type == MPDType.runeaudio {
                userDefaults.set("music/", forKey: MPDConnectionProperties.coverPrefix.rawValue + "." + initialUniqueID)
                userDefaults.set("Folder.jpg", forKey: MPDConnectionProperties.coverPostfix.rawValue + "." + initialUniqueID)
                userDefaults.set("", forKey: MPDConnectionProperties.alternativeCoverPostfix.rawValue + "." + initialUniqueID)
                userDefaults.set("", forKey: MPDConnectionProperties.alternativeCoverHost.rawValue + "." + initialUniqueID)
            }
            else if type == MPDType.moodeaudio {
                userDefaults.set("coverart.php/", forKey: MPDConnectionProperties.coverPrefix.rawValue + "." + initialUniqueID)
                userDefaults.set("<track>", forKey: MPDConnectionProperties.coverPostfix.rawValue + "." + initialUniqueID)
                userDefaults.set("", forKey: MPDConnectionProperties.alternativeCoverPostfix.rawValue + "." + initialUniqueID)
                userDefaults.set("", forKey: MPDConnectionProperties.alternativeCoverHost.rawValue + "." + initialUniqueID)
            }
            else {
                userDefaults.set("", forKey: MPDConnectionProperties.coverPrefix.rawValue + "." + initialUniqueID)
                userDefaults.set("Folder.jpg", forKey: MPDConnectionProperties.coverPostfix.rawValue + "." + initialUniqueID)
                userDefaults.set("", forKey: MPDConnectionProperties.alternativeCoverPostfix.rawValue + "." + initialUniqueID)
                userDefaults.set("", forKey: MPDConnectionProperties.alternativeCoverHost.rawValue + "." + initialUniqueID)
            }
            userDefaults.set(type.rawValue, forKey: MPDConnectionProperties.MPDType.rawValue + "." + initialUniqueID)
            _type = type
        }
        _type = defaultTypeInt > 0 ? MPDType(rawValue: defaultTypeInt)! : type

        // Note: using _name here instead of _uniqueId because that is not yet available.
        let coverHttpPort = userDefaults.string(forKey: "\(MPDConnectionProperties.coverHttpPort.rawValue).\(initialUniqueID)") ?? ""
        let prefix = userDefaults.string(forKey: "\(MPDConnectionProperties.coverPrefix.rawValue).\(initialUniqueID)") ?? ""
        let postfix = userDefaults.string(forKey: "\(MPDConnectionProperties.coverPostfix.rawValue).\(initialUniqueID)") ?? ""
        let alternativePostfix = userDefaults.string(forKey: "\(MPDConnectionProperties.alternativeCoverPostfix.rawValue).\(initialUniqueID)") ?? ""
        let alternativeCoverHost = userDefaults.string(forKey: "\(MPDConnectionProperties.alternativeCoverHost.rawValue).\(initialUniqueID)") ?? ""
        let connectionProperties = [ConnectionProperties.Name.rawValue: name,
                ConnectionProperties.Host.rawValue: host,
                ConnectionProperties.Port.rawValue: port,
                ConnectionProperties.Password.rawValue: password,
                MPDConnectionProperties.alternativeCoverHost.rawValue: alternativeCoverHost,
                MPDConnectionProperties.coverHttpPort.rawValue: coverHttpPort,
                MPDConnectionProperties.coverPrefix.rawValue: prefix,
                MPDConnectionProperties.coverPostfix.rawValue: postfix,
                MPDConnectionProperties.alternativeCoverPostfix.rawValue: alternativePostfix,
                MPDConnectionProperties.MPDType.rawValue: _type,
                MPDConnectionProperties.version.rawValue: version] as [String : Any]

        self.mpdStatus = MPDStatus.init(mpd: mpd,
                                        connectionProperties: connectionProperties,
                                        scheduler: scheduler)
        
        HelpMePlease.allocUp(name: "MPDPlayer")
    }
    
    /// Init an instance of a MPDPlayer based on a connectionProperties dictionary
    ///
    /// - Parameters:
    ///   - connectionProperties: dictionary of properties
    public convenience init(mpd: MPDProtocol? = nil,
                            connectionProperties: [String: Any],
                            scheduler: SchedulerType? = nil,
                            type: MPDType = .classic,
                            version: String = "",
                            discoverMode: DiscoverMode = .automatic,
                            connectionWarning: String? = nil,
                            userDefaults: UserDefaults) {
        guard let name = connectionProperties[ConnectionProperties.Name.rawValue] as? String,
            let host = connectionProperties[ConnectionProperties.Host.rawValue] as? String,
            let port = connectionProperties[ConnectionProperties.Port.rawValue] as? Int else {
                self.init(mpd: mpd,
                          name: "",
                          host: "",
                          port: 6600,
                          scheduler: scheduler,
                          type: type,
                          version: version,
                          discoverMode: discoverMode,
                          connectionWarning: connectionWarning,
                          userDefaults: userDefaults)
                return
        }
        
        self.init(mpd: mpd,
                  name: name,
                  host: host,
                  port: port,
                  password: connectionProperties[ConnectionProperties.Password.rawValue] as? String,
                  scheduler: scheduler,
                  type: type,
                  version: version,
                  discoverMode: discoverMode,
                  connectionWarning: connectionWarning,
                  userDefaults: userDefaults)
    }
    
    deinit {
        mpdStatus.stop()

        print("Cleaning up player \(name)")
        HelpMePlease.allocDown(name: "MPDPlayer")
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
    public func copy() -> PlayerProtocol {
        return MPDPlayer.init(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler, type: type, version: version, userDefaults: userDefaults)
    }
    
    /// Store setting.value into user-defaults and perform any other required actions
    ///
    /// - Parameter setting: the settings definition, including the value
    public func updateSetting(_ setting: PlayerSetting) {
        let playerSpecificId = setting.id + "." + uniqueID

        if setting.id == MPDConnectionProperties.MPDType.rawValue {
            let selectionSetting = setting as! SelectionSetting
            let currentValue = userDefaults.integer(forKey: playerSpecificId)
            if currentValue != selectionSetting.value {
                userDefaults.set(selectionSetting.value, forKey: playerSpecificId)
                
                if selectionSetting.value == MPDType.volumio.rawValue {
                    userDefaults.set("albumart?path=", forKey: MPDConnectionProperties.coverPrefix.rawValue + "." + uniqueID)
                    userDefaults.set("", forKey: MPDConnectionProperties.coverPostfix.rawValue + "." + uniqueID)
                    userDefaults.set("", forKey: MPDConnectionProperties.alternativeCoverPostfix.rawValue + "." + uniqueID)
                    userDefaults.set("", forKey: MPDConnectionProperties.alternativeCoverHost.rawValue + "." + uniqueID)
                    _type = MPDType.volumio
                }
                else if selectionSetting.value == MPDType.bryston.rawValue {
                    userDefaults.set("music/", forKey: MPDConnectionProperties.coverPrefix.rawValue + "." + uniqueID)
                    userDefaults.set("Folder.jpg", forKey: MPDConnectionProperties.coverPostfix.rawValue + "." + uniqueID)
                    userDefaults.set("bdp_front_250.jpg", forKey: MPDConnectionProperties.alternativeCoverPostfix.rawValue + "." + uniqueID)
                    userDefaults.set("", forKey: MPDConnectionProperties.alternativeCoverHost.rawValue + "." + uniqueID)
                    _type = MPDType.bryston
                }
                else if selectionSetting.value == MPDType.runeaudio.rawValue {
                    userDefaults.set("music/", forKey: MPDConnectionProperties.coverPrefix.rawValue + "." + uniqueID)
                    userDefaults.set("Folder.jpg", forKey: MPDConnectionProperties.coverPostfix.rawValue + "." + uniqueID)
                    userDefaults.set("", forKey: MPDConnectionProperties.alternativeCoverPostfix.rawValue + "." + uniqueID)
                    userDefaults.set("", forKey: MPDConnectionProperties.alternativeCoverHost.rawValue + "." + uniqueID)
                    _type = MPDType.runeaudio
                }
                else if selectionSetting.value == MPDType.moodeaudio.rawValue {
                    userDefaults.set("coverart.php/", forKey: MPDConnectionProperties.coverPrefix.rawValue + "." + uniqueID)
                    userDefaults.set("<track>", forKey: MPDConnectionProperties.coverPostfix.rawValue + "." + uniqueID)
                    userDefaults.set("", forKey: MPDConnectionProperties.alternativeCoverPostfix.rawValue + "." + uniqueID)
                    userDefaults.set("", forKey: MPDConnectionProperties.alternativeCoverHost.rawValue + "." + uniqueID)
                    _type = MPDType.moodeaudio
                }
                else {
                    userDefaults.set("", forKey: MPDConnectionProperties.coverPrefix.rawValue + "." + uniqueID)
                    userDefaults.set("Folder.jpg", forKey: MPDConnectionProperties.coverPostfix.rawValue + "." + uniqueID)
                    userDefaults.set("", forKey: MPDConnectionProperties.alternativeCoverPostfix.rawValue + "." + uniqueID)
                    userDefaults.set("", forKey: MPDConnectionProperties.alternativeCoverHost.rawValue + "." + uniqueID)
                    _type = MPDType.classic
                }
            }
        }
        else if setting.id == MPDConnectionProperties.alternativeCoverHost.rawValue {
            let stringSetting = setting as! StringSetting
            userDefaults.set(stringSetting.value, forKey: playerSpecificId)
        }
        else if setting.id == MPDConnectionProperties.coverHttpPort.rawValue {
            let stringSetting = setting as! StringSetting
            userDefaults.set(stringSetting.value, forKey: playerSpecificId)
        }
        else if setting.id == MPDConnectionProperties.coverPrefix.rawValue {
            let stringSetting = setting as! StringSetting
            userDefaults.set(stringSetting.value, forKey: playerSpecificId)
        }
        else if setting.id == MPDConnectionProperties.coverPostfix.rawValue {
            let stringSetting = setting as! StringSetting
            userDefaults.set(stringSetting.value, forKey: playerSpecificId)
        }
        else if setting.id == MPDConnectionProperties.alternativeCoverPostfix.rawValue {
            let stringSetting = setting as! StringSetting
            userDefaults.set(stringSetting.value, forKey: playerSpecificId)
        }
        else if setting.id == ConnectionProperties.Password.rawValue {
            let stringSetting = setting as! StringSetting
            userDefaults.set(stringSetting.value, forKey: playerSpecificId)
        }
    }
    
    /// Get data for a specific setting
    ///
    /// - Parameter id: the id of the setting to load
    /// - Returns: a new PlayerSetting object containing the value of the requested setting
    public func loadSetting(id: String) -> PlayerSetting? {
        let playerSpecificId = id + "." + uniqueID
        if id == MPDConnectionProperties.MPDType.rawValue {
            return SelectionSetting.init(id: id,
                                          description: "Player Type",
                                          items: [MPDType.classic.rawValue: MPDType.classic.description,
                                                  MPDType.volumio.rawValue: MPDType.volumio.description,
                                                  MPDType.bryston.rawValue: MPDType.bryston.description,
                                                  MPDType.runeaudio.rawValue: MPDType.runeaudio.description,
                                                  MPDType.moodeaudio.rawValue: MPDType.moodeaudio.description],
                                          value: userDefaults.integer(forKey: playerSpecificId))
        }
        else if id == MPDConnectionProperties.alternativeCoverHost.rawValue {
            return StringSetting.init(id: id,
                                      description: "Alternative Cover Host",
                                      placeholder: "IP Address",
                                      value: userDefaults.string(forKey: playerSpecificId) ?? "")
        }
        else if id == MPDConnectionProperties.coverHttpPort.rawValue {
            return StringSetting.init(id: id,
                                      description: "Cover Http Port",
                                      placeholder: "Optional Port Number",
                                      value: userDefaults.string(forKey: playerSpecificId) ?? "",
                                      restriction: .numeric)
        }
        else if id == MPDConnectionProperties.coverPrefix.rawValue {
            return StringSetting.init(id: id,
                                               description: "Cover Prefix",
                                               placeholder: "Prefix",
                                               value: userDefaults.string(forKey: playerSpecificId) ?? "")
        }
        else if id == MPDConnectionProperties.coverPostfix.rawValue {
            return StringSetting.init(id: id,
                                      description: "Cover Filename",
                                      placeholder: "Filename",
                                      value: userDefaults.string(forKey: playerSpecificId) ?? "")
        }
        else if id == MPDConnectionProperties.alternativeCoverPostfix.rawValue {
            return StringSetting.init(id: id,
                                      description: "Alternative Cover Filename",
                                      placeholder: "Alternative",
                                      value: userDefaults.string(forKey: playerSpecificId) ?? "")
        }
        else if id == ConnectionProperties.Password.rawValue {
            return StringSetting.init(id: id,
                                      description: "Password",
                                      placeholder: "Password",
                                      value: userDefaults.string(forKey: playerSpecificId) ?? "",
                                      restriction: .password)
        }

        return nil
    }
}

extension MPDPlayer : Equatable {
    public static func ==(lhs: MPDPlayer, rhs: MPDPlayer) -> Bool {
        return lhs.uniqueID == rhs.uniqueID
    }
}
