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
    case classic = 1
    case mopidy = 2
    case volumio = 3
    case bryston = 4
    
    var description: String {
        switch self {
        case .classic:
            return "Classic MPD"
        case .mopidy:
            return "Mopidy"
        case .volumio:
            return "Volumio"
        case .bryston:
            return "Bryston"
        }
    }
}

public enum MPDConnectionProperties: String {
    case MPDType = "type"
    case coverPrefix = "MPD.Uri.Prefix"
    case coverPostfix = "MPD.Uri.Postfix"
    case alternativeCoverPostfix = "MPD.Uri.AlternativePostfix"
}

public class MPDPlayer: PlayerProtocol {
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
    private var password: String
    private var _type: MPDType
    public var type: MPDType {
        return _type
    }
    
    private var _version: String
    public var version: String {
        return _version
    }
    public var description: String {
        return _type.description + " " + _version
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

    private static func uniqueIDForPlayer(host: String, port: Int) -> String {
        return "\(host)"
    }

    public var model: String {
        get {
            return type.description
        }
    }
    
    public var connectionProperties: [String: Any] {
        get {
            let prefix = (self.loadSetting(id: MPDConnectionProperties.coverPrefix.rawValue) as? StringSetting)?.value ?? ""
            let postfix = (self.loadSetting(id: MPDConnectionProperties.coverPostfix.rawValue) as? StringSetting)?.value ?? ""
            let alternativePostfix = (self.loadSetting(id: MPDConnectionProperties.alternativeCoverPostfix.rawValue) as? StringSetting)?.value ?? ""
            return [ConnectionProperties.Name.rawValue: name,
                    ConnectionProperties.Host.rawValue: host,
                    ConnectionProperties.Port.rawValue: port,
                    ConnectionProperties.Password.rawValue: password,
                    MPDConnectionProperties.coverPrefix.rawValue: prefix,
                    MPDConnectionProperties.coverPostfix.rawValue: postfix,
                    MPDConnectionProperties.alternativeCoverPostfix.rawValue: alternativePostfix,
                    MPDConnectionProperties.MPDType.rawValue: type.rawValue]
        }
    }
    
    public var settings: [PlayerSettingGroup] {
        get {
            let mpdDBStatusObservable = (self.browse as! MPDBrowse).databaseStatus()
            let reloadingObservable = Observable<Int>
                .interval(RxTimeInterval(2), scheduler: MainScheduler.instance)
                .flatMap( { _ in
                    mpdDBStatusObservable
                })
            
            return [PlayerSettingGroup(title: "Player Type", description: "", settings:[loadSetting(id: MPDConnectionProperties.MPDType.rawValue)!]),
                    PlayerSettingGroup(title: "Cover Art", description: "", settings:[loadSetting(id: MPDConnectionProperties.coverPrefix.rawValue)!,
                                                                                      loadSetting(id: MPDConnectionProperties.coverPostfix.rawValue)!,
                                                                                      loadSetting(id: MPDConnectionProperties.alternativeCoverPostfix.rawValue)!]),
                    PlayerSettingGroup(title: "MPD Database", description: "", settings:[DynamicSetting.init(id: "MPDDBStatus", description: "Database Status", titleObservable: Observable.merge(mpdDBStatusObservable, reloadingObservable)),
                                                                                         ActionSetting.init(id: "MPDReload", description: "Update DB", action: { () in
                        (self.browse as! MPDBrowse).updateDB()
                    })])]
        }
    }
    
    /// Create a unique object for every request for a control object
    public var control: ControlProtocol {
        get {
            // Use serialScheduler to synchronize commands across multiple MPDControl instances.
            return MPDControl.init(mpd: mpd, connectionProperties: connectionProperties, identification: uniqueID, scheduler: serialScheduler, playerStatusObservable: mpdStatus.playerStatusObservable)
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
                password: String = "",
                scheduler: SchedulerType? = nil,
                type: MPDType = .classic,
                version: String = "",
                discoverMode: DiscoverMode = .automatic) {
        self.mpd = mpd ?? MPDWrapper()
        self._name = name
        self.host = host
        self.port = port
        self.password = password
        self.scheduler = scheduler
        self.serialScheduler = scheduler ?? SerialDispatchQueueScheduler.init(qos: .background, internalSerialQueueName: "com.katoemba.mpdplayer")
        _version = version
        _discoverMode = discoverMode
        let initialUniqueID = MPDPlayer.uniqueIDForPlayer(host: host, port: port)
        let defaultTypeInt = UserDefaults.standard.integer(forKey: "\(MPDConnectionProperties.MPDType.rawValue).\(initialUniqueID)")
        if defaultTypeInt > 0 {
            _type = MPDType(rawValue: defaultTypeInt)!
        }
        else {
            // Note: using _name here instead of _uniqueId because that is not yet available.
            let defaults = UserDefaults.standard
            if type == MPDType.volumio {
                defaults.set("albumart?path=", forKey: MPDConnectionProperties.coverPrefix.rawValue + "." + initialUniqueID)
                defaults.set("", forKey: MPDConnectionProperties.coverPostfix.rawValue + "." + initialUniqueID)
                defaults.set("", forKey: MPDConnectionProperties.alternativeCoverPostfix.rawValue + "." + initialUniqueID)
            }
            else if type == MPDType.bryston {
                defaults.set("music", forKey: MPDConnectionProperties.coverPrefix.rawValue + "." + initialUniqueID)
                defaults.set("Folder.jpg", forKey: MPDConnectionProperties.coverPostfix.rawValue + "." + initialUniqueID)
                defaults.set("bdp_front_250.jpg", forKey: MPDConnectionProperties.alternativeCoverPostfix.rawValue + "." + initialUniqueID)
            }
            else {
                defaults.set("", forKey: MPDConnectionProperties.coverPrefix.rawValue + "." + initialUniqueID)
                defaults.set("Folder.jpg", forKey: MPDConnectionProperties.coverPostfix.rawValue + "." + initialUniqueID)
                defaults.set("", forKey: MPDConnectionProperties.alternativeCoverPostfix.rawValue + "." + initialUniqueID)
            }
            defaults.set(type.rawValue, forKey: MPDConnectionProperties.MPDType.rawValue + "." + initialUniqueID)
            _type = type
        }
        _type = defaultTypeInt > 0 ? MPDType(rawValue: defaultTypeInt)! : type

        // Note: using _name here instead of _uniqueId because that is not yet available.
        let prefix = UserDefaults.standard.string(forKey: "\(MPDConnectionProperties.coverPrefix.rawValue).\(initialUniqueID)") ?? ""
        let postfix = UserDefaults.standard.string(forKey: "\(MPDConnectionProperties.coverPostfix.rawValue).\(initialUniqueID)") ?? ""
        let alternativePostfix = UserDefaults.standard.string(forKey: "\(MPDConnectionProperties.alternativeCoverPostfix.rawValue).\(initialUniqueID)") ?? ""
        let connectionProperties = [ConnectionProperties.Name.rawValue: name,
                ConnectionProperties.Host.rawValue: host,
                ConnectionProperties.Port.rawValue: port,
                ConnectionProperties.Password.rawValue: password,
                MPDConnectionProperties.coverPrefix.rawValue: prefix,
                MPDConnectionProperties.coverPostfix.rawValue: postfix,
                MPDConnectionProperties.alternativeCoverPostfix.rawValue: alternativePostfix,
                MPDConnectionProperties.MPDType.rawValue: _type] as [String : Any]

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
                            discoverMode: DiscoverMode = .automatic) {
        guard let name = connectionProperties[ConnectionProperties.Name.rawValue] as? String,
            let host = connectionProperties[ConnectionProperties.Host.rawValue] as? String,
            let port = connectionProperties[ConnectionProperties.Port.rawValue] as? Int else {
                self.init(mpd: mpd,
                          name: "",
                          host: "",
                          port: 6600,
                          password: "",
                          scheduler: scheduler,
                          type: type,
                          version: version,
                          discoverMode: discoverMode)
                return
        }
        
        self.init(mpd: mpd,
                  name: name,
                  host: host,
                  port: port,
                  password: (connectionProperties[ConnectionProperties.Password.rawValue] as? String) ?? "",
                  scheduler: scheduler,
                  type: type,
                  version: version,
                  discoverMode: discoverMode)
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
        return MPDPlayer.init(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler, type: type, version: version)
    }
    
    /// Store setting.value into user-defaults and perform any other required actions
    ///
    /// - Parameter setting: the settings definition, including the value
    public func updateSetting(_ setting: PlayerSetting) {
        let playerSpecificId = setting.id + "." + uniqueID
        let defaults = UserDefaults.standard

        if setting.id == MPDConnectionProperties.MPDType.rawValue {
            let selectionSetting = setting as! SelectionSetting
            let currentValue = defaults.integer(forKey: playerSpecificId)
            if currentValue != selectionSetting.value {
                defaults.set(selectionSetting.value, forKey: playerSpecificId)
                
                if selectionSetting.value == MPDType.volumio.rawValue {
                    defaults.set("albumart?path=", forKey: MPDConnectionProperties.coverPrefix.rawValue + "." + uniqueID)
                    defaults.set("", forKey: MPDConnectionProperties.coverPostfix.rawValue + "." + uniqueID)
                    defaults.set("", forKey: MPDConnectionProperties.alternativeCoverPostfix.rawValue + "." + uniqueID)
                    _type = MPDType.volumio
                }
                else if selectionSetting.value == MPDType.bryston.rawValue {
                    defaults.set("music/", forKey: MPDConnectionProperties.coverPrefix.rawValue + "." + uniqueID)
                    defaults.set("Folder.jpg", forKey: MPDConnectionProperties.coverPostfix.rawValue + "." + uniqueID)
                    defaults.set("bdp_front_250.jpg", forKey: MPDConnectionProperties.alternativeCoverPostfix.rawValue + "." + uniqueID)
                    _type = MPDType.bryston
                }
                else {
                    defaults.set("", forKey: MPDConnectionProperties.coverPrefix.rawValue + "." + uniqueID)
                    defaults.set("Folder.jpg", forKey: MPDConnectionProperties.coverPostfix.rawValue + "." + uniqueID)
                    defaults.set("", forKey: MPDConnectionProperties.alternativeCoverPostfix.rawValue + "." + uniqueID)
                    _type = MPDType.classic
                }
            }
        }
        else if setting.id == MPDConnectionProperties.coverPrefix.rawValue {
            let stringSetting = setting as! StringSetting
            defaults.set(stringSetting.value, forKey: playerSpecificId)
        }
        else if setting.id == MPDConnectionProperties.coverPostfix.rawValue {
            let stringSetting = setting as! StringSetting
            defaults.set(stringSetting.value, forKey: playerSpecificId)
        }
        else if setting.id == MPDConnectionProperties.alternativeCoverPostfix.rawValue {
            let stringSetting = setting as! StringSetting
            defaults.set(stringSetting.value, forKey: playerSpecificId)
        }
    }
    
    /// Get data for a specific setting
    ///
    /// - Parameter id: the id of the setting to load
    /// - Returns: a new PlayerSetting object containing the value of the requested setting
    public func loadSetting(id: String) -> PlayerSetting? {
        let playerSpecificId = id + "." + uniqueID
        let defaults = UserDefaults.standard
        if id == MPDConnectionProperties.MPDType.rawValue {
            return SelectionSetting.init(id: id,
                                          description: "Player Type",
                                          items: [MPDType.classic.rawValue: MPDType.classic.description,
                                                  MPDType.volumio.rawValue: MPDType.volumio.description,
                                                  MPDType.bryston.rawValue: MPDType.bryston.description],
                                          value: defaults.integer(forKey: playerSpecificId))
        }
        else if id == MPDConnectionProperties.coverPrefix.rawValue {
            return StringSetting.init(id: id,
                                               description: "Cover Prefix",
                                               placeholder: "Prefix",
                                               value: defaults.string(forKey: playerSpecificId) ?? "")
        }
        else if id == MPDConnectionProperties.coverPostfix.rawValue {
            return StringSetting.init(id: id,
                                      description: "Cover Filename",
                                      placeholder: "Filename",
                                      value: defaults.string(forKey: playerSpecificId) ?? "")
        }
        else if id == MPDConnectionProperties.alternativeCoverPostfix.rawValue {
            return StringSetting.init(id: id,
                                      description: "Alternative Cover Filename",
                                      placeholder: "Alternative",
                                      value: defaults.string(forKey: playerSpecificId) ?? "")
        }

        return nil
    }
}

extension MPDPlayer : Equatable {
    public static func ==(lhs: MPDPlayer, rhs: MPDPlayer) -> Bool {
        return lhs.uniqueID == rhs.uniqueID
    }
}
