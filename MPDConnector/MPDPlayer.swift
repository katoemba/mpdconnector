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

public class MPDPlayer: PlayerProtocol {
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
            return "mpd:\(host):\(port)"
        }
    }
    
    public var connectionProperties: [String: Any] {
        get {
            return ["host": host, "port": port, "password": password]
        }
    }
    
    private let serialScheduler = SerialDispatchQueueScheduler(internalSerialQueueName: "com.katoemba.mpdcontroller.player")
    private let bag = DisposeBag()

    // MARK: - Initialization and connecting
    
    /// Initialize a new player object
    ///
    /// - Parameters:
    ///   - host: Host ip-address to connect to.
    ///   - port: Port to connect to.
    ///   - password: Password to use when connection, default is ""
    ///   - connectedHandler: Optional handler that is called when a successful (re)connection is made
    ///   - disconnectedHandler: Optional handler that is called when a connection can't be made or is lost
    public init(mpd: MPDProtocol? = nil,
                host: String, port: Int, password: String = "") {
        self.mpd = mpd ?? MPDWrapper()
        self.host = host
        self.port = port
        self.password = password
        self.mpdController = MPDController.init(mpd: self.mpd,
                                                connection: nil,
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
            .addDisposableTo(bag)
    }
    
    
    /// Reactive connection function
    ///
    /// - Returns: An observable that will attempt to connect to mpd when triggered
    private func connectToMPD() -> Observable<OpaquePointer?> {
        return Observable<OpaquePointer?>.create { observer in
            let connection = self.connect(host: self.host, port: self.port, password: self.password)
            if connection != nil {
                if self.mpd.connection_get_error(connection) == MPD_ERROR_SUCCESS {
                    observer.onNext(connection)
                    observer.onCompleted()
                }
                else {
                    observer.onError(ConnectionError.internalError)
                }
            }
            
            return Disposables.create()
        }
    }

    /// Connect to a MPD Player
    ///
    /// - Parameters:
    ///   - host: Host ip-address to connect to.
    ///   - port: Port to connect to.
    ///   - password: Password to use after connecting, default = "".
    /// - Returns: A mpd_connection object.
    private func connect(host: String, port: Int, password: String = "") -> OpaquePointer? {
        let connection = self.mpd.connection_new(host, UInt32(port), 1000)
        if self.mpd.connection_get_error(connection) == MPD_ERROR_SUCCESS {
            if password != "" {
                _ = self.mpd.run_password(connection, password: password)
            }
        }
        
        return connection
    }
}
