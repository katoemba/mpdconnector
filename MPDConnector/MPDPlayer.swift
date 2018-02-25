//
//  StatusManager.swift
//  MPDConnector
//
//  Created by Berrie Kremers on 05-08-17.
//  Copyright © 2017 Katoemba Software. All rights reserved.
//

import Foundation
import ConnectorProtocol
import libmpdclient
import RxSwift
import RxCocoa

enum ConnectionError: Error {
    case internalError
}

enum MPDType: String {
    case classic = "Classic"
    case mopidy = "Mopidy"
}

public enum MPDConnectionProperties: String {
    case coverPrefix = "MPD.Uri.Prefix"
    case coverPostfix = "MPD.Uri.Postfix"
}

public class MPDPlayer: PlayerProtocol {
    private let mpd: MPDProtocol

    private var _name: String
    public var name: String {
        return _name
    }
    
    private var host: String
    private var port: Int
    private var password: String
    
    /// Current status
    private var mpdStatus: MPDStatus
    public var status: StatusProtocol {
        return mpdStatus
    }
    
    public var uniqueID: String {
        get {
            return "\(_name)"
        }
    }
    
    public var connectionProperties: [String: Any] {
        get {
            let prefix = UserDefaults.standard.string(forKey: "\(MPDConnectionProperties.coverPrefix.rawValue).\(host)") ?? ""
            let postfix = UserDefaults.standard.string(forKey: "\(MPDConnectionProperties.coverPostfix.rawValue).\(host)") ?? ""
            return [ConnectionProperties.Name.rawValue: name,
                    ConnectionProperties.Host.rawValue: host,
                    ConnectionProperties.Port.rawValue: port,
                    ConnectionProperties.Password.rawValue: password,
                    MPDConnectionProperties.coverPrefix.rawValue: prefix,
                    MPDConnectionProperties.coverPostfix.rawValue: postfix]
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
                scheduler: SchedulerType? = nil) {
        self.mpd = mpd ?? MPDWrapper()
        self._name = name
        self.host = host
        self.port = port
        self.password = password
        self.scheduler = scheduler
        self.serialScheduler = scheduler ?? SerialDispatchQueueScheduler.init(qos: .background, internalSerialQueueName: "com.katoemba.mpdplayer")
        
        let prefix = UserDefaults.standard.string(forKey: "\(MPDConnectionProperties.coverPrefix.rawValue).\(host)") ?? ""
        let postfix = UserDefaults.standard.string(forKey: "\(MPDConnectionProperties.coverPostfix.rawValue).\(host)") ?? ""
        let connectionProperties = [ConnectionProperties.Name.rawValue: name,
                ConnectionProperties.Host.rawValue: host,
                ConnectionProperties.Port.rawValue: port,
                ConnectionProperties.Password.rawValue: password,
                MPDConnectionProperties.coverPrefix.rawValue: prefix,
                MPDConnectionProperties.coverPostfix.rawValue: postfix] as [String : Any]

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
                            scheduler: SchedulerType? = nil) {
        guard let name = connectionProperties[ConnectionProperties.Name.rawValue] as? String,
            let host = connectionProperties[ConnectionProperties.Host.rawValue] as? String,
            let port = connectionProperties[ConnectionProperties.Port.rawValue] as? Int else {
                self.init(mpd: mpd,
                          name: "",
                          host: "",
                          port: 6600,
                          password: "",
                          scheduler: scheduler)
                return
        }
        
        self.init(mpd: mpd,
                  name: name,
                  host: host,
                  port: port,
                  password: (connectionProperties[ConnectionProperties.Password.rawValue] as? String) ?? "",
                  scheduler: scheduler)
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
        return MPDPlayer.init(mpd: mpd, connectionProperties: connectionProperties, scheduler: scheduler)
    }
}

extension MPDPlayer : Equatable {
    public static func ==(lhs: MPDPlayer, rhs: MPDPlayer) -> Bool {
        return lhs.uniqueID == rhs.uniqueID
    }
}
