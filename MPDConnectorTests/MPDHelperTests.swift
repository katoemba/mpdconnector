//
//  MPDHelperTests.swift
//  MPDConnectorTests
//
//  Created by Berrie Kremers on 04-01-18.
//  Copyright © 2018 Kaotemba Software. All rights reserved.
//

import Foundation
import XCTest
import ConnectorProtocol
import MPDConnector
import libmpdclient
import RxSwift
import RxCocoa
import RxBlocking

class MPDHelperTests: XCTestCase {
    var mpdPlayer: MPDPlayer?
    var mpdWrapper = MPDWrapperMock()
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
    
    func testConnectToMPDWithConnectionProperties() {
        // Given nothing
        mpdWrapper.password = ""
        let connectionProperties = [ConnectionProperties.Name.rawValue: "player",
                                    ConnectionProperties.Host.rawValue: "host",
                                    ConnectionProperties.Port.rawValue: 1000,
                                    ConnectionProperties.Password.rawValue: ""] as [String: Any]
        
        XCTAssertNotNil(try? MPDHelper.connectToMPD(mpd: mpdWrapper, connectionProperties: connectionProperties)
                                .toBlocking()
                                .first() as Any,
                        "Expected connection to be present")

        // And connection_new is called once.
        mpdWrapper.assertCall("connection_new", expectedCallCount: 1)
        // And connection_free is called once.
        mpdWrapper.assertCall("connection_free", expectedCallCount: 0)
    }

    func testConnectToMPDWithConnectionPropertiesValidPassword() {
        // Given nothing
        mpdWrapper.password = "pwd"
        let connectionProperties = [ConnectionProperties.Name.rawValue: "player",
                                    ConnectionProperties.Host.rawValue: "host",
                                    ConnectionProperties.Port.rawValue: 1000,
                                    ConnectionProperties.Password.rawValue: "pwd"] as [String: Any]
        
        XCTAssertNotNil(try? MPDHelper.connectToMPD(mpd: mpdWrapper, connectionProperties: connectionProperties)
            .toBlocking()
            .first() as Any,
                     "Expected connection to be present")
        
        // And connection_new is called once.
        mpdWrapper.assertCall("connection_new", expectedCallCount: 1)
        // And run_password is called once.
        mpdWrapper.assertCall("run_password", expectedCallCount: 1)
        // And connection_free is called once.
        mpdWrapper.assertCall("connection_free", expectedCallCount: 0)
    }

    func testConnectToMPDWithConnectionPropertiesInvalidPassword() {
        // Given nothing
        mpdWrapper.password = "other"
        let connectionProperties = [ConnectionProperties.Name.rawValue: "player",
                                    ConnectionProperties.Host.rawValue: "host",
                                    ConnectionProperties.Port.rawValue: 1000,
                                    ConnectionProperties.Password.rawValue: "pwd"] as [String: Any]
        
        // When connecting to MPD
        XCTAssertNil(try? MPDHelper.connectToMPD(mpd: mpdWrapper, connectionProperties: connectionProperties)
            .toBlocking()
            .first() as Any,
                     "Expected connection to be nil")

        // And connection_new is called once.
        mpdWrapper.assertCall("connection_new", expectedCallCount: 1)
        // And run_password is called once.
        mpdWrapper.assertCall("run_password", expectedCallCount: 1)
        // And connection_free is called once.
        mpdWrapper.assertCall("connection_free", expectedCallCount: 1)
    }
    
    func testConnectToMPDWithConnectionPropertiesTimeout() {
        // Given a timout when connecting
        // Given a problem when connecting
        mpdWrapper.password = ""
        mpdWrapper.connectionErrorCount = 1
        let connectionProperties = [ConnectionProperties.Name.rawValue: "player",
                                    ConnectionProperties.Host.rawValue: "host",
                                    ConnectionProperties.Port.rawValue: 1000,
                                    ConnectionProperties.Password.rawValue: ""] as [String: Any]
        
        // When connecting to MPD
        XCTAssertNil(try? MPDHelper.connectToMPD(mpd: mpdWrapper, connectionProperties: connectionProperties)
                            .toBlocking()
                            .first() as Any,
                     "Expected connection to be nil")

        // And connection_new is called once.
        mpdWrapper.assertCall("connection_new", expectedCallCount: 1)
        // And connection_free is called once.
        mpdWrapper.assertCall("connection_free", expectedCallCount: 1)
    }
}
