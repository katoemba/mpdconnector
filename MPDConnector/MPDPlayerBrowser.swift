//
//  PlayerManager.swift
//  MPDConnector_iOS
//
//  Created by Berrie Kremers on 26-09-17.
//  Copyright © 2017 Kaotemba Software. All rights reserved.
//

import Foundation
import ConnectorProtocol
import RxSwift

/// Class to monitor mpdPlayers appearing and disappearing from the network.
public class MPDPlayerBrowser: PlayerBrowserProtocol {
    private let netServiceBrowser : NetServiceBrowser
    public let addPlayerObservable : Observable<PlayerProtocol>
    public let removePlayerObservable : Observable<PlayerProtocol>
    
    private var isListening = false

    public init() {
        netServiceBrowser = NetServiceBrowser()
        
        // Create an observable that monitors when new players are discovered.
        addPlayerObservable = netServiceBrowser.rx.serviceAdded
            .map({ (netService) -> PlayerProtocol in
                return MPDPlayer.init(name: netService.name, host: netService.hostName ?? "Unknown", port: netService.port)
            })
            .asObservable()

        // Create an observable that monitors when players disappear from the network.
        removePlayerObservable = netServiceBrowser.rx.serviceRemoved
            .map({ (netService) -> PlayerProtocol in
                return MPDPlayer.init(name: netService.name, host: netService.hostName ?? "Unknown", port: netService.port)
            })
            .asObservable()
    }
    
    /// Start listening for players on the local domain.
    public func startListening() {
        guard isListening == false else {
            return
        }
        
        isListening = true
        netServiceBrowser.searchForServices(ofType: "_mpd._tcp.", inDomain: "local.")
    }
    
    /// Stop listening for players.
    public func stopListening() {
        guard isListening == true else {
            return
        }

        isListening = false
        netServiceBrowser.stop()
    }
}
