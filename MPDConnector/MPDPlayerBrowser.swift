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
import ConnectorProtocol
import RxSwift
import libmpdclient

/// Class to monitor mpdPlayers appearing and disappearing from the network.
public class MPDPlayerBrowser: PlayerBrowserProtocol {
    private let mpdNetServiceBrowser : NetServiceBrowser
    private let volumioNetServiceBrowser : NetServiceBrowser
    private let backgroundScheduler = ConcurrentDispatchQueueScheduler.init(qos: .background)

    private let addManualPlayerSubject = PublishSubject<MPDPlayer>()
    private let removeManualPlayerSubject = PublishSubject<PlayerProtocol>()
    public let addPlayerObservable : Observable<PlayerProtocol>
    public let removePlayerObservable : Observable<PlayerProtocol>
    
    private var isListening = false
    private var userDefaults: UserDefaults

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
        mpdNetServiceBrowser = NetServiceBrowser()
        volumioNetServiceBrowser = NetServiceBrowser()

        // Create an observable that monitors when new players are discovered.
        let mpdPlayerObservable = mpdNetServiceBrowser.rx.serviceAdded
            .map({ (netService) -> (String, String, Int, MPDType) in
                let initialUniqueID = MPDPlayer.uniqueIDForPlayer(host: netService.hostName ?? "Unknown", port: netService.port)
                let typeInt = userDefaults.integer(forKey: "\(MPDConnectionProperties.MPDType.rawValue).\(initialUniqueID)")
                let mpdType = MPDType.init(rawValue: typeInt) ?? .unknown

                return (netService.name, netService.hostName ?? "Unknown", netService.port, mpdType)
            })
            .flatMap({ (name, host, port, type) -> Observable<(String, String, Int, MPDType)> in
                // Check if this is a Bryston player
                return Observable.create { observer in
                    if type != .unknown {
                        observer.onNext((name, host, port, type))
                        observer.onCompleted()
                    }
                    else {
                        // Make a request to the player for the api version
                        let session = URLSession.shared
                        let request = URLRequest(url: URL(string: "http://\(host)/bdbapiver")!)
                        let task = session.dataTask(with: request) {
                            (data, response, error) -> Void in
                            if error == nil, let status = (response as? HTTPURLResponse)?.statusCode, status == 200,
                                let data = data, let responseString = String(data: data, encoding: String.Encoding.utf8),
                                responseString.starts(with: "1") {
                                observer.onNext((name, host, port, .bryston))
                            }
                            else {
                                observer.onNext((name, host, port, type))
                            }
                            observer.onCompleted()
                        }
                        
                        task.resume()
                    }
                    
                    return Disposables.create()
                }
            })
            .flatMap({ (name, host, port, type) -> Observable<(String, String, Int, MPDType)> in
                // Check if this is a Rune Audio based player
                Observable.create { observer in
                    if type != .unknown {
                        observer.onNext((name, host, port, type))
                        observer.onCompleted()
                    }
                    else {
                        // Make a request to the player for the stats command
                        let session = URLSession.shared
                        let request = URLRequest(url: URL(string: "http://\(host)/command/?cmd=stats")!)
                        let task = session.dataTask(with: request){
                            (data, response, error) -> Void in
                            if error == nil, let data = data,
                                let responseString = String(data: data, encoding: String.Encoding.utf8),
                                responseString.contains("db_update") {
                                observer.onNext((name, host, port, .runeaudio))
                            }
                            else {
                                observer.onNext((name, host, port, type))
                            }
                            observer.onCompleted()
                        }
                        task.resume()
                    }
                    
                    return Disposables.create()
                }
            })
            .map({ (name, host, port, type) -> MPDPlayer in
                return MPDPlayer.init(name: name, host: host, port: port, type: type == .unknown ? .classic : type, userDefaults: userDefaults)
            })
            .share(replay: 1)

        // Create an observable that monitors for http services, and then checks if this is a volumio player.
        let httpPlayerObservable = volumioNetServiceBrowser.rx.serviceAdded
            .observeOn(backgroundScheduler)
            .filter({ (netService) -> Bool in
                netService.name.contains("[runeaudio]") == false && netService.name.contains("bryston") == false
            })
            .filter({ (netService) -> Bool in
                // Check if an MPD player is present at the default port
                let mpd = MPDWrapper()
                if let connection = MPDHelper.connect(mpd: mpd, host: netService.hostName ?? "Unknown", port: 6600, password: "") {
                    mpd.connection_free(connection)
                    return true
                }
                return false
            })
            .map({ (netService) -> (String, String, Int, MPDType) in
                let initialUniqueID = MPDPlayer.uniqueIDForPlayer(host: netService.hostName ?? "Unknown", port: netService.port)
                let typeInt = userDefaults.integer(forKey: "\(MPDConnectionProperties.MPDType.rawValue).\(initialUniqueID)")
                let mpdType = MPDType.init(rawValue: typeInt) ?? .unknown
                
                return (netService.name, netService.hostName ?? "Unknown", netService.port, mpdType)
            })
            .flatMap({ (name, host, port, type) -> Observable<(String, String, Int, MPDType)> in
                    // Check if this is a Volumio based player
                    Observable.create { observer in
                        if type != .unknown {
                            observer.onNext((name, host, 6600, type))
                            observer.onCompleted()
                        }
                        else {
                            // Make a request to the player for the state
                            let session = URLSession.shared
                            let request = URLRequest(url: URL(string: "http://\(host):\(port)/api/v1/getstate")!)
                            let task = session.dataTask(with: request){
                                (data, response, error) -> Void in
                                if error == nil {
                                    if let data = data {
                                        do {
                                            // When getting back sensible data, we can assume this is a Volumio player
                                            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                                                ,json["album"] != nil, json["artist"] != nil {
                                                observer.onNext((name, host, 6600, .volumio))
                                            }
                                        }
                                        catch {
                                        }
                                    }
                                }
                                observer.onCompleted()
                            }
                            task.resume()
                        }
                    
                        return Disposables.create()
                    }
                })
            .map({ (name, host, port, type) -> MPDPlayer in
                return MPDPlayer.init(name: name, host: host, port: port, type: type == .unknown ? .classic : type, userDefaults: userDefaults)
            })
            .share(replay: 1)

        // Merge the detected players, and get a version out of them.
        addPlayerObservable = Observable.merge(mpdPlayerObservable, httpPlayerObservable, addManualPlayerSubject)
            .observeOn(backgroundScheduler)
            .map({ (player) -> PlayerProtocol in
                let mpd = MPDWrapper()
                if let connection = MPDHelper.connect(mpd: mpd, connectionProperties: player.connectionProperties) {
                    var connectionWarning = nil as String?
                    let version = mpd.connection_get_server_version(connection)
                    if version < "0.19.0" {
                        connectionWarning = "MPD version \(version) too low, 0.19.0 required"
                    }
                    
                    let mpdStatus = mpd.run_status(connection)
                    if  mpd.connection_get_error(connection) == MPD_ERROR_SERVER,
                        mpd.connection_get_server_error(connection) == MPD_SERVER_ERROR_PERMISSION {
                        connectionWarning = "Player requires a password"
                    }
                    if mpdStatus != nil {
                        mpd.status_free(mpdStatus)
                    }
                    mpd.connection_free(connection)

                    return MPDPlayer.init(connectionProperties: player.connectionProperties,
                                          type: player.type,
                                          version: version,
                                          discoverMode: player.discoverMode,
                                          connectionWarning: connectionWarning,
                                          userDefaults: userDefaults)
                }

                return player
            })
            .observeOn(MainScheduler.instance)
        
        // Create an observable that monitors when players disappear from the network.
        let removeMPDPlayerObservable = mpdNetServiceBrowser.rx.serviceRemoved
            .map({ (netService) -> PlayerProtocol in
                return MPDPlayer.init(name: netService.name, host: netService.hostName ?? "Unknown", port: netService.port, userDefaults: userDefaults)
            })
            .asObservable()

        // Create an observable that monitors when players disappear from the network.
        let removeVolumioPlayerObservable = volumioNetServiceBrowser.rx.serviceRemoved
            .map({ (netService) -> PlayerProtocol in
                return MPDPlayer.init(name: netService.name, host: netService.hostName ?? "Unknown", port: 6600, userDefaults: userDefaults)
            })
            .asObservable()
        
        removePlayerObservable = Observable.merge(removeMPDPlayerObservable, removeVolumioPlayerObservable, removeManualPlayerSubject)
            .observeOn(MainScheduler.instance)
            .asObservable()
    }
    
    /// Start listening for players on the local domain.
    public func startListening() {
        guard isListening == false else {
            return
        }
        
        isListening = true
        mpdNetServiceBrowser.searchForServices(ofType: "_mpd._tcp.", inDomain: "")
        volumioNetServiceBrowser.searchForServices(ofType: "_http._tcp.", inDomain: "")
        
        let persistedPlayers = userDefaults.dictionary(forKey: "mpd.browser.manualplayers") ?? [String: [String: Any]]()
        for persistedPlayer in persistedPlayers.keys {
            addManualPlayerSubject.onNext(MPDPlayer.init(connectionProperties: persistedPlayers[persistedPlayer] as! [String: Any], discoverMode: .manual, userDefaults: userDefaults))
        }
    }
    
    /// Stop listening for players.
    public func stopListening() {
        guard isListening == true else {
            return
        }

        isListening = false
        mpdNetServiceBrowser.stop()
        volumioNetServiceBrowser.stop()
    }
    
    /// Manually create a player based on the connection properties
    ///
    /// - Parameter connectionProperties: dictionary of connection properties
    /// - Returns: An observable on which a created Player can published.
    public func playerForConnectionProperties(_ connectionProperties: [String: Any]) -> Observable<PlayerProtocol?> {
        return MPDHelper.connectToMPD(mpd: MPDWrapper(), connectionProperties: connectionProperties, scheduler: backgroundScheduler)
            .flatMapFirst({ [weak self] (connection) -> Observable<PlayerProtocol?> in
                guard let weakSelf = self else { return Observable.just(nil) }
                if (connection != nil) {
                    MPDWrapper().connection_free(connection)
                    return Observable.just(MPDPlayer.init(connectionProperties: connectionProperties, userDefaults: weakSelf.userDefaults))
                }
                return Observable.just(nil)
            })
            .observeOn(MainScheduler.instance)
    }
    
    public func persistPlayer(_ connectionProperties: [String: Any]) {
        var persistedPlayers = userDefaults.dictionary(forKey: "mpd.browser.manualplayers") ?? [String: [String: Any]]()
        
        if persistedPlayers[connectionProperties[ConnectionProperties.Name.rawValue] as! String] != nil {
            removeManualPlayerSubject.onNext(MPDPlayer.init(connectionProperties: connectionProperties, userDefaults: userDefaults))
        }
        persistedPlayers[connectionProperties[ConnectionProperties.Name.rawValue] as! String] = connectionProperties
        addManualPlayerSubject.onNext(MPDPlayer.init(connectionProperties: connectionProperties, discoverMode: .manual, userDefaults: userDefaults))

        userDefaults.set(persistedPlayers, forKey: "mpd.browser.manualplayers")
    }
    
    public func removePlayer(_ player: PlayerProtocol) {
        var persistedPlayers = userDefaults.dictionary(forKey: "mpd.browser.manualplayers") ?? [String: [String: Any]]()
        
        if persistedPlayers[player.name] != nil {
            removeManualPlayerSubject.onNext(player)
            persistedPlayers.removeValue(forKey: player.name)
            userDefaults.set(persistedPlayers, forKey: "mpd.browser.manualplayers")
        }
    }
}
