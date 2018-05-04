//
//  MPDHelperTests.swift
//  MPDConnectorTests
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
        
        let conn = try! MPDHelper.connectToMPD(mpd: mpdWrapper, connectionProperties: connectionProperties)
            .toBlocking()
            .first() ?? nil
        XCTAssertNotNil(conn, "Expected connection to be present")

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
        
        let conn = try! MPDHelper.connectToMPD(mpd: mpdWrapper, connectionProperties: connectionProperties)
            .toBlocking()
            .first() ?? nil
        XCTAssertNotNil(conn, "Expected connection to be present")

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
        let conn = try! MPDHelper.connectToMPD(mpd: mpdWrapper, connectionProperties: connectionProperties)
            .toBlocking()
            .first() ?? nil
        XCTAssertNil(conn, "Expected connection to be nil")

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
        let conn = try! MPDHelper.connectToMPD(mpd: mpdWrapper, connectionProperties: connectionProperties)
            .toBlocking()
            .first() ?? nil
        XCTAssertNil(conn, "Expected connection to be nil")

        // And connection_new is called once.
        mpdWrapper.assertCall("connection_new", expectedCallCount: 1)
        // And connection_free is called once.
        mpdWrapper.assertCall("connection_free", expectedCallCount: 1)
    }
}
