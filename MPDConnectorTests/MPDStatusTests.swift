//
//  MPDStatusTests.swift
//  MPDConnectorTests
//
//  Created by Berrie Kremers on 04-01-18.
//  Copyright © 2018 Kaotemba Software. All rights reserved.
//

import XCTest
import ConnectorProtocol
import MPDConnector
import libmpdclient
import RxSwift
import RxCocoa

class MPDStatusTests: XCTestCase {
    var mpdPlayer: MPDPlayer?
    var mpdWrapper = MPDWrapperMock()
    var mpdConnectedExpectation: XCTestExpectation?
    let bag = DisposeBag()
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
        
        mpdWrapper = MPDWrapperMock()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testStartAndStopConnection() {
        // Given a mpd player
        let connectionProperties = [ConnectionProperties.Name.rawValue: "player",
                                    ConnectionProperties.Host.rawValue: "host",
                                    ConnectionProperties.Port.rawValue: 1000,
                                    ConnectionProperties.Password.rawValue: ""] as [String: Any]
        
        // When creating a new MPDStatus object and starting it
        let status = MPDStatus.init(mpd: mpdWrapper, connectionProperties: connectionProperties)
        status.start()
        
        // And then stop, start and stop again
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            status.stop()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            status.start()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            status.stop()
        }

        // Then the statuses .online, .offline, .online, .offline are reported
        let connectionResults = status.connectionStatusObservable
            .distinctUntilChanged()
            .toBlocking(timeout: 0.2)
            .materialize()

        switch connectionResults {
        case .failed(let connectionStatusArray, _):
            XCTAssert(connectionStatusArray == [.online, .offline, .online, .offline], "Expected reported statuses [.online, .offline, .online, .offline], got \(connectionStatusArray)")
        default:
            print("Default")
        }
    }

    func testStartAndStop() {
        // Given a mpd player
        let connectionProperties = [ConnectionProperties.Name.rawValue: "player",
                                    ConnectionProperties.Host.rawValue: "host",
                                    ConnectionProperties.Port.rawValue: 1000,
                                    ConnectionProperties.Password.rawValue: ""] as [String: Any]
        self.mpdWrapper.volume = 20
        
        // When creating a new MPDStatus object and starting it
        let status = MPDStatus.init(mpd: mpdWrapper, connectionProperties: connectionProperties)
        status.start()
        
        // And changing the volume, stopping and changing the volume again
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.mpdWrapper.volume = 30
            status.forceStatusRefresh()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            status.stop()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.mpdWrapper.volume = 40
            status.forceStatusRefresh()
        }
        
        // Then only the volume values before the 'stop' are reported.
        let playerStatusResults = status.playerStatusObservable
            .toBlocking(timeout: 0.2)
            .materialize()
        
        switch playerStatusResults {
        case .failed(let playerStatusArray, _):
            let volumeArray = playerStatusArray.map({ (status) -> Float in
                status.volume
            })
            XCTAssert(volumeArray == [0.0, 0.2, 0.3], "Expected reported volumes [0.0, 0.2, 0.3], got \(volumeArray)")
        default:
            print("Default")
        }
    }
    
    func testDisconnect() {
        // Given a mpd player
        let connectionProperties = [ConnectionProperties.Name.rawValue: "player",
                                    ConnectionProperties.Host.rawValue: "host",
                                    ConnectionProperties.Port.rawValue: 1000,
                                    ConnectionProperties.Password.rawValue: ""] as [String: Any]
        
        // When creating a new MPDStatus object and starting it
        let status = MPDStatus.init(mpd: mpdWrapper, connectionProperties: connectionProperties)
        status.start()
        
        // And then force a disconnect
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.mpdWrapper.connectionError = MPD_ERROR_TIMEOUT
            status.forceStatusRefresh()
        }
        
        // Then the statuses .online, .offline are reported
        let connectionResults = status.connectionStatusObservable
            .distinctUntilChanged()
            .toBlocking(timeout: 0.1)
            .materialize()
        
        switch connectionResults {
        case .failed(let connectionStatusArray, _):
            XCTAssert(connectionStatusArray == [.online, .offline], "Expected reported statuses [.online, .offline], got \(connectionStatusArray)")
        default:
            print("Default")
        }

        // And when we start again and disconnect again on the same object
        status.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.mpdWrapper.connectionError = MPD_ERROR_TIMEOUT
            status.forceStatusRefresh()
        }
        
        // Then the statuses .online, .offline are reported
        let connectionResults2ndTime = status.connectionStatusObservable
            .distinctUntilChanged()
            .toBlocking(timeout: 0.1)
            .materialize()
        
        switch connectionResults2ndTime {
        case .failed(let connectionStatusArray, _):
            XCTAssert(connectionStatusArray == [.online, .offline], "Expected reported statuses [.online, .offline], got \(connectionStatusArray)")
        default:
            print("Default")
        }
    }

    func testMultipleStarts() {
        // Given a mpd player
        let connectionProperties = [ConnectionProperties.Name.rawValue: "player",
                                    ConnectionProperties.Host.rawValue: "host",
                                    ConnectionProperties.Port.rawValue: 1000,
                                    ConnectionProperties.Password.rawValue: ""] as [String: Any]
        
        // When creating a new MPDStatus object and starting it twice
        let status = MPDStatus.init(mpd: mpdWrapper, connectionProperties: connectionProperties)
        status.start()
        status.start()

        // Then the statuses .online is reported once
        let connectionResults = status.connectionStatusObservable
            .toBlocking(timeout: 0.1)
            .materialize()
        
        switch connectionResults {
        case .failed(let connectionStatusArray, _):
            XCTAssert(connectionStatusArray == [.online], "Expected reported statuses [.online], got \(connectionStatusArray)")
        default:
            print("Default")
        }
    }

    func testImmediateStartStop() {
        // Given a mpd player
        let connectionProperties = [ConnectionProperties.Name.rawValue: "player",
                                    ConnectionProperties.Host.rawValue: "host",
                                    ConnectionProperties.Port.rawValue: 1000,
                                    ConnectionProperties.Password.rawValue: ""] as [String: Any]
        
        // When creating a new MPDStatus object and starting/stopping it twice
        let status = MPDStatus.init(mpd: mpdWrapper, connectionProperties: connectionProperties)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            status.start()
            status.stop()
            status.start()
            status.stop()
        }

        // Then the statuses .unknown, .online, .offline, .online, .offline are reported
        let connectionResults = status.connectionStatusObservable
            .distinctUntilChanged()
            .toBlocking(timeout: 0.1)
            .materialize()

        switch connectionResults {
        case .failed(let connectionStatusArray, _):
            XCTAssert(connectionStatusArray == [.unknown, .online, .offline, .online, .offline], "Expected reported statuses [.unknown,.online, .offline, .online, .offline], got \(connectionStatusArray)")
        default:
            print("Default")
        }
    }

}

