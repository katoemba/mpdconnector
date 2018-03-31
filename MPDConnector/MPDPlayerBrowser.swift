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

/// Class to monitor mpdPlayers appearing and disappearing from the network.
public class MPDPlayerBrowser: PlayerBrowserProtocol {
    private let mpdNetServiceBrowser : NetServiceBrowser
    private let volumioNetServiceBrowser : NetServiceBrowser
    private let backgroundScheduler = ConcurrentDispatchQueueScheduler.init(qos: .background)

    public let addPlayerObservable : Observable<PlayerProtocol>
    public let removePlayerObservable : Observable<PlayerProtocol>
    
    private var isListening = false

    public init() {
        mpdNetServiceBrowser = NetServiceBrowser()
        volumioNetServiceBrowser = NetServiceBrowser()

        // Create an observable that monitors when new players are discovered.
        let addMPDPlayerObservable = mpdNetServiceBrowser.rx.serviceAdded
            .map({ (netService) -> MPDPlayer in
                
                return MPDPlayer.init(name: netService.name, host: netService.hostName ?? "Unknown", port: netService.port)
            })
            .asObservable()

        // Create an observable that monitors for http services, and then checks if this is a volumio player.
        let addVolumioPlayerObservable = volumioNetServiceBrowser.rx.serviceAdded
            .observeOn(backgroundScheduler)
            .filter({ (netService) -> Bool in
                // Check if an MPD player is present at the default port
                let mpd = MPDWrapper()
                if let connection = MPDHelper.connect(mpd: mpd, host: netService.hostName ?? "Unknown", port: 6600, password: "") {
                    mpd.connection_free(connection)
                    return true
                }
                return false
            })
            .flatMap({ (netService) -> Observable<NetService> in
                return Observable.create { observer in
                    // Make a request to the player for the state
                    let session = URLSession.shared
                    let request = URLRequest(url: URL(string: "http://\(netService.hostName ?? "Unknown"):\(netService.port)/api/v1/getstate")!)
                    let task = session.dataTask(with: request){
                        (data, response, error) -> Void in
                        if error == nil {
                            if let data = data {
                                do {
                                    // When getting back sensible data, we can assume this is a Volumio player
                                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                                        ,json["album"] != nil, json["artist"] != nil {
                                        observer.onNext(netService)
                                    }
                                }
                                catch {
                                }
                            }
                        }
                        observer.onCompleted()
                    }
                    task.resume()
                    
                    return Disposables.create()
                }
            })
            .map({ (netService) -> MPDPlayer in
                return MPDPlayer.init(name: netService.name, host: netService.hostName ?? "Unknown", port: 6600, type: .volumio)
            })
            .asObservable()
        
        // Merge the detected players, and get a version out of them.
        addPlayerObservable = Observable.merge(addMPDPlayerObservable, addVolumioPlayerObservable)
            .observeOn(backgroundScheduler)
            .map({ (player) -> PlayerProtocol in
                let mpd = MPDWrapper()
                if let connection = MPDHelper.connect(mpd: mpd, connectionProperties: player.connectionProperties) {
                    let version = mpd.connection_get_server_version(connection)
                    mpd.connection_free(connection)
                    
                    return MPDPlayer.init(connectionProperties: player.connectionProperties,
                                          type: player.type,
                                          version: version)
                }

                return player
            })
            .observeOn(MainScheduler.instance)
            .asObservable()
        
        // Create an observable that monitors when players disappear from the network.
        let removeMPDPlayerObservable = mpdNetServiceBrowser.rx.serviceRemoved
            .map({ (netService) -> PlayerProtocol in
                return MPDPlayer.init(name: netService.name, host: netService.hostName ?? "Unknown", port: netService.port)
            })
            .asObservable()

        // Create an observable that monitors when players disappear from the network.
        let removeVolumioPlayerObservable = volumioNetServiceBrowser.rx.serviceRemoved
            .map({ (netService) -> PlayerProtocol in
                return MPDPlayer.init(name: netService.name, host: netService.hostName ?? "Unknown", port: 6600)
            })
            .asObservable()
        
        removePlayerObservable = Observable.merge(removeMPDPlayerObservable, removeVolumioPlayerObservable)
            .observeOn(MainScheduler.instance)
            .asObservable()
    }
    
    /// Start listening for players on the local domain.
    public func startListening() {
        guard isListening == false else {
            return
        }
        
        isListening = true
        mpdNetServiceBrowser.searchForServices(ofType: "_mpd._tcp.", inDomain: "local.")
        volumioNetServiceBrowser.searchForServices(ofType: "_http._tcp.", inDomain: "local.")
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
}
