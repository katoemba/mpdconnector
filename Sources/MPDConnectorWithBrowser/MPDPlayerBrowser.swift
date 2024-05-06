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
#if os(iOS)
import UIKit
#endif
import ConnectorProtocol
import RxSwift
import libmpdclient
import SWXMLHash
import RxNetService
import MPDConnector
import SwiftMPD

/// Class to monitor mpdPlayers appearing and disappearing from the network.
public class MPDPlayerBrowser: PlayerBrowserProtocol {
    struct MPDConnectionData {
        let name: String
        let host: String
        let ip: String?
        let port: Int
        let type: MPDType
        
        func withType(_ newType: MPDType) -> MPDConnectionData {
            MPDConnectionData(name: name, host: host, ip: ip, port: port, type: newType)
        }

        func withPortAndType(_ newPort: Int, _ newType: MPDType) -> MPDConnectionData {
            MPDConnectionData(name: name, host: host, ip: ip, port: newPort, type: newType)
        }

        func withNameAndPortAndType(_ newName: String, _ newPort: Int, _ newType: MPDType) -> MPDConnectionData {
            MPDConnectionData(name: newName, host: host, ip: ip, port: newPort, type: newType)
        }
    }
    
    public var controllerType: String {
        MPDPlayer.controllerType
    }
    private let mpdNetServiceBrowser : NetServiceBrowser
    private let volumioNetServiceBrowser : NetServiceBrowser
    private let httpNetServiceBrowser : NetServiceBrowser
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
        httpNetServiceBrowser = NetServiceBrowser()
        
        // Create an observable that monitors when new players are discovered.
        let mpdPlayerObservable = mpdNetServiceBrowser.rx.serviceAdded
            .map({ (netService) -> (MPDConnectionData) in
                let initialUniqueID = MPDPlayer.uniqueIDForPlayer(host: netService.hostName ?? "Unknown", port: netService.port)
                let typeInt = userDefaults.integer(forKey: "\(MPDConnectionProperties.MPDType.rawValue).\(initialUniqueID)")
                let mpdType = MPDType.init(rawValue: typeInt) ?? .unknown
                
                return (MPDConnectionData(name: netService.name, host: netService.hostName ?? "Unknown", ip: netService.firstIPv4Address, port: netService.port, type: mpdType))
            })
            .flatMap({ (connectionData) -> Observable<MPDConnectionData> in
                // Check if this is a Bryston player
                return Observable.create { observer in
                    if connectionData.type != .unknown {
                        observer.onNext(connectionData)
                        observer.onCompleted()
                    }
                    else {
                        // Make a request to the player for the api version
                        let session = URLSession.shared
                        if let url = URL(string: "http://\(connectionData.host)/bdbapiver") {
                            let request = URLRequest(url: url)
                            let task = session.dataTask(with: request) {
                                (data, response, error) -> Void in
                                if error == nil, let status = (response as? HTTPURLResponse)?.statusCode, status == 200,
                                    let data = data, let responseString = String(data: data, encoding: String.Encoding.utf8),
                                    responseString.starts(with: "1") {
                                    observer.onNext(connectionData.withType(.bryston))
                                }
                                else {
                                    observer.onNext(connectionData)
                                }
                                observer.onCompleted()
                            }
                            task.resume()
                        }
                        else {
                            observer.onCompleted()
                        }
                    }
                    
                    return Disposables.create()
                }
            })
            .flatMap({ (connectionData) -> Observable<MPDConnectionData> in
                // Check if this is a Rune Audio based player
                Observable.create { observer in
                    if connectionData.type != .unknown {
                        observer.onNext(connectionData)
                        observer.onCompleted()
                    }
                    else {
                        // Make a request to the player for the stats command
                        let session = URLSession.shared
                        if let url = URL(string: "http://\(connectionData.host)/command/?cmd=stats") {
                            let request = URLRequest(url: url)
                            let task = session.dataTask(with: request){
                                (data, response, error) -> Void in
                                if error == nil, let data = data,
                                    let responseString = String(data: data, encoding: String.Encoding.utf8),
                                    responseString.contains("db_update") {
                                    observer.onNext(connectionData.withType(.runeaudio))
                                }
                                else {
                                    observer.onNext(connectionData)
                                }
                                observer.onCompleted()
                            }
                            task.resume()
                        }
                        else {
                            observer.onCompleted()
                        }
                    }
                    
                    return Disposables.create()
                }
            })
            .map({ (connectionData) -> MPDConnectionData in
                connectionData.withType((connectionData.type == .unknown && (connectionData.name.lowercased().contains("chord") || connectionData.host.lowercased().contains("chord") ||
                                                                                connectionData.host.lowercased().contains("2go") || connectionData.host.lowercased().contains("2 go") ||
                                                                                connectionData.host.lowercased().contains("hugo") || connectionData.host.lowercased().contains("hugo"))) ? .chord : connectionData.type)
            })
            .map({ (connectionData) -> MPDPlayer in
                return MPDPlayer.init(name: connectionData.name, host: connectionData.host, ipAddress: connectionData.ip, port: connectionData.port, type: connectionData.type == .unknown ? .classic : connectionData.type, userDefaults: userDefaults)
            })
            .share(replay: 1)
        
        // Create an observable that monitors for http services, and then checks if this is a volumio player.
        let httpPlayerObservable = httpNetServiceBrowser.rx.serviceAdded
            .observe(on: backgroundScheduler)
            .filter({ (netService) -> Bool in
                netService.name.contains("[runeaudio]") == false && netService.name.contains("bryston") == false
            })
            .filter({ (netService) -> Bool in
                // Check if an MPD player is present at the default port
                let mpd = MPDWrapper()
                if MPDHelper.connect(mpd: mpd, host: netService.hostName ?? (netService.firstIPv4Address ?? "Unknown"), port: 6600, password: "") != nil {
                    return true
                }
                return false
            })
            .map({ (netService) -> (MPDConnectionData) in
                let initialUniqueID = MPDPlayer.uniqueIDForPlayer(host: netService.hostName ?? "Unknown", port: netService.port)
                let typeInt = userDefaults.integer(forKey: "\(MPDConnectionProperties.MPDType.rawValue).\(initialUniqueID)")
                let mpdType = MPDType.init(rawValue: typeInt) ?? .unknown
                
                return MPDConnectionData(name: netService.name, host: netService.hostName ?? "Unknown", ip: netService.firstIPv4Address, port: netService.port, type: mpdType)
            })
        
        let volumioHttpPlayerObservable = httpPlayerObservable
            .flatMap({ (connectionData) -> Observable<MPDConnectionData> in
                // Check if this is a Volumio based player
                Observable.create { observer in
                    if connectionData.type != .unknown {
                        observer.onNext(connectionData.withPortAndType(6600, connectionData.type))
                        observer.onCompleted()
                    }
                    else {
                        // Make a request to the player for the state
                        let session = URLSession.shared
                        if let url = URL(string: "http://\(connectionData.host):\(connectionData.port)/api/v1/getstate") {
                            let request = URLRequest(url: url)
                            let task = session.dataTask(with: request){
                                (data, response, error) -> Void in
                                if error == nil {
                                    if let data = data {
                                        do {
                                            // When getting back sensible data, we can assume this is a Volumio player
                                            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                                                ,json["album"] != nil, json["artist"] != nil {
                                                observer.onNext(connectionData.withPortAndType(6600, .volumio))
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
                        else {
                            observer.onCompleted()
                        }
                    }
                    
                    return Disposables.create()
                }
            })
            .map({ (connectionData) -> MPDPlayer in
                return MPDPlayer.init(name: connectionData.name, host: connectionData.host, ipAddress: connectionData.ip, port: connectionData.port, type: connectionData.type == .unknown ? .classic : connectionData.type, userDefaults: userDefaults)
            })
            .share(replay: 1)
        
        let moodeAudioHttpPlayerObservable = httpPlayerObservable
            .flatMap({ (connectionData) -> Observable<MPDConnectionData> in
                // Check if this is a Moode based player
                Observable.create { observer in
                    if connectionData.type != .unknown {
                        let abbreviatedName = connectionData.name.replacingOccurrences(of: "moOde audio player: ", with: "")
                        observer.onNext(connectionData.withNameAndPortAndType(abbreviatedName, 6600, connectionData.type))
                        observer.onCompleted()
                    }
                    else {
                        // Make a request to the player for the state
                        let session = URLSession.shared
                        if let url = URL(string: "http://\(connectionData.host):\(connectionData.port)/browserconfig.xml") {
                            let request = URLRequest(url: url)
                            let task = session.dataTask(with: request){
                                (data, response, error) -> Void in
                                if error == nil {
                                    if let data = data {
                                        let xml = XMLHash.parse(data)
                                        let browserConfig = xml["browserconfig"]
                                        if browserConfig.children.count > 0 {
                                            let abbreviatedName = connectionData.name.replacingOccurrences(of: "moOde audio player: ", with: "")
                                            observer.onNext(connectionData.withNameAndPortAndType(abbreviatedName, 6600, .moodeaudio))
                                        }
                                    }
                                }
                                observer.onCompleted()
                            }
                            task.resume()
                        }
                        else {
                            observer.onCompleted()
                        }
                    }
                    
                    return Disposables.create()
                }
            })
            .map({ (connectionData) -> MPDPlayer in
                return MPDPlayer.init(name: connectionData.name, host: connectionData.host, ipAddress: connectionData.ip, port: connectionData.port, type: connectionData.type == .unknown ? .classic : connectionData.type, userDefaults: userDefaults)
            })
            .share(replay: 1)

        let volumio3PlayerObservable = volumioNetServiceBrowser.rx.serviceAdded
            .map({ (netService) -> MPDPlayer in
                return MPDPlayer.init(name: netService.name, host: netService.hostName ?? "volumio", ipAddress: netService.firstIPv4Address, port: 6600, type: .volumio, userDefaults: userDefaults)
            })
            .share(replay: 1)

        // Merge the detected players, and get a version out of them.
        addPlayerObservable = Observable.merge(mpdPlayerObservable, volumioHttpPlayerObservable, moodeAudioHttpPlayerObservable, volumio3PlayerObservable, addManualPlayerSubject)
            .observe(on: backgroundScheduler)
            .map({ (player) -> PlayerProtocol in
                let mpd = MPDWrapper()
                let connectionProperties = player.connectionProperties
                let mpdConnection = MPDHelper.connect(mpd: mpd, connectionProperties: connectionProperties)
                if let connection = mpdConnection?.connection {
                    var connectionWarning = nil as String?
                    let version = mpd.connection_get_server_version(connection)
                    if MPDHelper.compareVersion(leftVersion: version, rightVersion: "0.19.0") == .orderedAscending {
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
                    
                    // Check for tag-type albumartist here, and set warning in case not found.
                    if connectionWarning == nil {
                        var tagTypes = [String]()
                        _ = mpd.send_list_tag_types(connection)
                        while let pair = mpd.recv_tag_type_pair(connection) {
                            tagTypes.append(pair.1)
                        }
                        _ = mpd.response_finish(connection)
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
                    
                    var commands = [String]()
                    _ = mpd.send_allowed_commands(connection)
                    while let command = mpd.recv_pair_named(connection, name: "command") {
                        commands.append(command.1)
                    }
                    _ = mpd.response_finish(connection)
                    
                    return MPDPlayer.init(connectionProperties: player.connectionProperties,
                                          type: player.type,
                                          version: version,
                                          discoverMode: player.discoverMode,
                                          connectionWarning: connectionWarning,
                                          userDefaults: userDefaults,
                                          commands: commands)
                }
                
                return player
            })
            .observe(on: MainScheduler.instance)
        
        // Create an observable that monitors when players disappear from the network.
        let removeMPDPlayerObservable = mpdNetServiceBrowser.rx.serviceRemoved
            .map({ (netService) -> PlayerProtocol in
                return MPDPlayer.init(name: netService.name, host: netService.hostName ?? "Unknown", ipAddress: netService.firstIPv4Address, port: netService.port, userDefaults: userDefaults)
            })
            .asObservable()
        
        // Create an observable that monitors when players disappear from the network.
        let removeHttpPlayerObservable = httpNetServiceBrowser.rx.serviceRemoved
            .map({ (netService) -> PlayerProtocol in
                return MPDPlayer.init(name: netService.name, host: netService.hostName ?? "Unknown", ipAddress: netService.firstIPv4Address, port: 6600, userDefaults: userDefaults)
            })
            .asObservable()
        
        removePlayerObservable = Observable.merge(removeMPDPlayerObservable, removeHttpPlayerObservable, removeManualPlayerSubject)
            .observe(on: MainScheduler.instance)
            .asObservable()
    }
    
    /// Start listening for players on the local domain.
    public func startListening() {
        guard isListening == false else {
            return
        }
        
        isListening = true
        mpdNetServiceBrowser.searchForServices(ofType: "_mpd._tcp.", inDomain: "")
        volumioNetServiceBrowser.searchForServices(ofType: "_Volumio._tcp.", inDomain: "")
        httpNetServiceBrowser.searchForServices(ofType: "_http._tcp.", inDomain: "")
        
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
        httpNetServiceBrowser.stop()
        
#if os(iOS)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard UIApplication.shared.applicationState != .active else {
                return
            }

            MPDConnection.cleanup()
        }
#endif
    }
    
    /// Manually create a player based on the connection properties
    ///
    /// - Parameter connectionProperties: dictionary of connection properties
    /// - Returns: An observable on which a created Player can published.
    public func playerForConnectionProperties(_ connectionProperties: [String: Any]) -> Observable<PlayerProtocol?> {
        guard connectionProperties[ConnectionProperties.controllerType.rawValue] as? String == MPDPlayer.controllerType,
              MPDHelper.hostToUse(connectionProperties) != "",
              let port = connectionProperties[ConnectionProperties.port.rawValue] as? Int else { return Observable.just(nil) }

        let userDefaults = self.userDefaults
        return Observable<PlayerProtocol?>.fromAsync {
            let hostToUse = MPDHelper.hostToUse(connectionProperties)
            let _ = try await SwiftMPD.MPDConnector(.init(ipAddress: hostToUse, port: port, connectTimeout: 3)).getVersion()
            
            return MPDPlayer(connectionProperties: connectionProperties, userDefaults: userDefaults)
        }
        .catchAndReturn(nil)
        .observe(on: MainScheduler.instance)
    }
    
    public func persistPlayer(_ connectionProperties: [String: Any]) {
        guard connectionProperties[ConnectionProperties.controllerType.rawValue] as? String == MPDPlayer.controllerType else { return }
        
        var persistedPlayers = userDefaults.dictionary(forKey: "mpd.browser.manualplayers") ?? [String: [String: Any]]()
        
        if persistedPlayers[connectionProperties[ConnectionProperties.name.rawValue] as! String] != nil {
            removeManualPlayerSubject.onNext(MPDPlayer.init(connectionProperties: connectionProperties, userDefaults: userDefaults))
        }
        persistedPlayers[connectionProperties[ConnectionProperties.name.rawValue] as! String] = connectionProperties
        addManualPlayerSubject.onNext(MPDPlayer.init(connectionProperties: connectionProperties, discoverMode: .manual, userDefaults: userDefaults))
        
        userDefaults.set(persistedPlayers, forKey: "mpd.browser.manualplayers")
    }
    
    public func removePlayer(_ player: PlayerProtocol) {
        guard player.controllerType == MPDPlayer.controllerType else { return }
        
        var persistedPlayers = userDefaults.dictionary(forKey: "mpd.browser.manualplayers") ?? [String: [String: Any]]()
        
        if persistedPlayers[player.name] != nil {
            removeManualPlayerSubject.onNext(player)
            persistedPlayers.removeValue(forKey: player.name)
            userDefaults.set(persistedPlayers, forKey: "mpd.browser.manualplayers")
        }
    }
    
    public var addManualPlayerSettings: [PlayerSettingGroup] {
        get {
            let hostSetting = StringSetting.init(id: ConnectionProperties.host.rawValue,
                                                 description: "IP Address",
                                                 placeholder: "IP Address or Hostname",
                                                 value: "",
                                                 restriction: .regular)
            hostSetting.validation = { (setting, value) -> String? in
                ((value as? String?) ?? "") == "" ? "Enter a valid ip-address for the player." : nil
            }

            let portSetting = StringSetting.init(id: ConnectionProperties.port.rawValue,
                                                 description: "Port",
                                                 placeholder: "Portnumber",
                                                 value: "6600",
                                                 restriction: .numeric)
            portSetting.validation = { (setting, value) -> String? in
                ((value as? Int?) ?? 0) == 0 ? "Enter a valid port number for the player (default = 6600)." : nil
            }

            let nameSetting = StringSetting.init(id: ConnectionProperties.name.rawValue,
                                                 description: "Name",
                                                 placeholder: "Player name",
                                                 value: "",
                                                 restriction: .regular)
            nameSetting.validation = { (setting, value) -> String? in
                ((value as? String?) ?? "") == "" ? "Enter a name for the player." : nil
            }

            let passwordSetting = StringSetting.init(id: ConnectionProperties.password.rawValue,
                                                     description: "Password",
                                                     placeholder: "Password",
                                                     value: "",
                                                     restriction: .password)
            
            return [PlayerSettingGroup(title: "Connection Settings", description: "Some players can't be automatically detected. In that case you can add it manually by entering the connection settings here.\n" +
                "After entering them, click 'Test' to let Rigelian test if it can connect to the player.\n\n" +
                "For details on the connection settings, refer to the documentation that comes with your player.",
                                       settings:[nameSetting, hostSetting, portSetting, passwordSetting])]
        }
    }
}
