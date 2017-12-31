//
//  StatusManager.swift
//  MPDConnector
//
//  Created by Berrie Kremers on 05-08-17.
//  Copyright © 2017 Kaotemba Software. All rights reserved.
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
    case Classic = "Classic"
    case Mopidy = "Mopidy"
}

public class MPDPlayer: PlayerProtocol {
    private var _name: String
    public var name: String {
        return _name
    }
    
    private var host: String
    private var port: Int
    private var password: String
    
    /// Connection to a MPD Player
    private let mpd: MPDProtocol
    
    /// Current connection status
    private var _connectionStatus = Variable<ConnectionStatus>(ConnectionStatus.Unknown)
    public var connectionStatus: Driver<ConnectionStatus> {
        return _connectionStatus.asDriver()
    }
    
    private var mpdController: MPDController
    public var controller: ControlProtocol {
        return mpdController
    }

    public var uniqueID: String {
        get {
            return "\(_name)"
        }
    }
    
    public var connectionProperties: [String: Any] {
        get {
            return [ConnectionProperties.Name.rawValue: name,
                    ConnectionProperties.Host.rawValue: host,
                    ConnectionProperties.Port.rawValue: port,
                    ConnectionProperties.Password.rawValue: password]
        }
    }
    
    private let serialScheduler = SerialDispatchQueueScheduler(internalSerialQueueName: "com.katoemba.mpdcontroller.player")
    private let bag = DisposeBag()

    // MARK: - Initialization and connecting
    
    /// Initialize a new player object
    ///
    /// - Parameters:
    ///   - mpd: MPDProtocol object used to run commands against the player
    ///   - host: Host ip-address to connect to.
    ///   - port: Port to connect to.
    ///   - password: Password to use when connection, default is ""
    public init(mpd: MPDProtocol? = nil,
                name: String, host: String, port: Int, password: String = "") {
        self.mpd = mpd ?? MPDWrapper()
        self._name = name
        self.host = host
        self.port = port
        self.password = password
        self.mpdController = MPDController.init(mpd: self.mpd,
                                                connection: nil,
                                                identification: "\(host):\(port)",
                                                disconnectedHandler: nil)
        
        self.mpdController.disconnectedHandler = { [weak self] (connection, error) in
            if [MPD_ERROR_TIMEOUT, MPD_ERROR_SYSTEM, MPD_ERROR_RESOLVER, MPD_ERROR_MALFORMED, MPD_ERROR_CLOSED].contains(error) {
                self?._connectionStatus.value = .Disconnected
                
                //let errorNumber = Int((self?.mpd.connection_get_error(connection).rawValue)!)
                //let errorMessage = self?.mpd.connection_get_error_message(connection)
                
                self?.mpd.connection_free(connection)
            }
        }
    }
    
    /// Init an instance of a MPDPlayer based on a connectionProperties dictionary
    ///
    /// - Parameters:
    ///   - mpd: MPDProtocol object used to run commands against the player
    ///   - connectionProperties: dictionary of properties
    public convenience init(mpd: MPDProtocol? = nil, connectionProperties: [String: Any]) {
        guard let name = connectionProperties[ConnectionProperties.Name.rawValue] as? String,
            let host = connectionProperties[ConnectionProperties.Host.rawValue] as? String,
            let port = connectionProperties[ConnectionProperties.Port.rawValue] as? Int else {
                self.init(mpd: mpd,
                          name: "",
                          host: "",
                          port: 6600,
                          password: "")
                return
        }
        
        self.init(mpd: mpd,
                  name: name,
                  host: host,
                  port: port,
                  password: (connectionProperties[ConnectionProperties.Password.rawValue] as? String) ?? "")
    }
    
    // MARK: - PlayerProtocol Implementations

    /// Attempt to (re)connect based on the internal variables. When successful an internal connection object will be set.
    ///
    /// - Parameter numberOfTries: Number of times to try connection, default = 3.
    public func connect(numberOfRetries: Int = 3) {
        guard _connectionStatus.value != .Connecting && _connectionStatus.value != .Connected else {
            return
        }
        
        connectToMPD()
            .subscribeOn(serialScheduler)
            .retry(numberOfRetries)
            .subscribe(onNext: { connection in
                self.mpdController.connection = connection
            },
                       onError: { _ in
                        self._connectionStatus.value = .Disconnected
            },
                       onCompleted: {
                        self._connectionStatus.value = .Connected
            })
            .disposed(by: bag)
    }
    
    /// Reactive connection function
    ///
    /// - Returns: An observable for a new connection. Will raise an error if connecting is not successful.
    public func connectToMPD() -> Observable<OpaquePointer> {
        return Observable<OpaquePointer>.create { observer in
            let connection = self.connect(host: self.host, port: self.port, password: self.password)
            if connection != nil {
                if self.mpd.connection_get_error(connection) == MPD_ERROR_SUCCESS {
                    observer.onNext(connection!)
                    observer.onCompleted()
                }
                else {
                    observer.onError(ConnectionError.internalError)
                }
            }
            
            return Disposables.create()
        }
    }
    
    public func libraryAccess() -> LibraryProtocol? {
        let connection = self.connect(host: self.host, port: self.port, password: self.password)
        if connection != nil, self.mpd.connection_get_error(connection) == MPD_ERROR_SUCCESS {
            return MPDLibrary.init(mpd: self.mpd, connection: connection, identification: "\(self.host):\(self.port)")
        }
        
        return nil
    }
    
    /// Connect to a MPD Player
    ///
    /// - Parameters:
    ///   - host: Host ip-address to connect to.
    ///   - port: Port to connect to.
    ///   - password: Password to use after connecting, default = "".
    /// - Returns: A mpd_connection object.
    private func connect(host: String, port: Int, password: String = "") -> OpaquePointer? {
        let connection = self.mpd.connection_new(host, UInt32(port), 5000)
        if self.mpd.connection_get_error(connection) == MPD_ERROR_SUCCESS {
            if password != "" {
                _ = self.mpd.run_password(connection, password: password)
            }
        }
        
        return connection
    }
    
}

extension MPDPlayer : Equatable {
    public static func ==(lhs: MPDPlayer, rhs: MPDPlayer) -> Bool {
        return lhs.uniqueID == rhs.uniqueID
    }
}
