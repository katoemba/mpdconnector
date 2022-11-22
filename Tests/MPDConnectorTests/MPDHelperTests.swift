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
        let connectionProperties = [ConnectionProperties.name.rawValue: "player",
                                    ConnectionProperties.host.rawValue: "host",
                                    ConnectionProperties.port.rawValue: 1000,
                                    ConnectionProperties.password.rawValue: ""] as [String: Any]
        
        let conn = try! MPDHelper.connectToMPD(mpd: mpdWrapper, connectionProperties: connectionProperties, scheduler: MainScheduler.instance)
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
        let connectionProperties = [ConnectionProperties.name.rawValue: "player",
                                    ConnectionProperties.host.rawValue: "host",
                                    ConnectionProperties.port.rawValue: 1000,
                                    ConnectionProperties.password.rawValue: "pwd"] as [String: Any]
        
        let conn = try! MPDHelper.connectToMPD(mpd: mpdWrapper, connectionProperties: connectionProperties, scheduler: MainScheduler.instance)
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
        let connectionProperties = [ConnectionProperties.name.rawValue: "player",
                                    ConnectionProperties.host.rawValue: "host",
                                    ConnectionProperties.port.rawValue: 1000,
                                    ConnectionProperties.password.rawValue: "pwd"] as [String: Any]
        
        // When connecting to MPD
        let conn = try! MPDHelper.connectToMPD(mpd: mpdWrapper, connectionProperties: connectionProperties, scheduler: MainScheduler.instance)
            .toBlocking()
            .first() ?? nil
        XCTAssertNil(conn, "Expected connection to be nil")

        // And connection_new is called once.
        mpdWrapper.assertCall("connection_new", expectedCallCount: 4)
        // And run_password is called once.
        mpdWrapper.assertCall("run_password", expectedCallCount: 4)
        // And connection_free is called once.
        mpdWrapper.assertCall("connection_free", expectedCallCount: 4)
    }
    
    func testConnectToMPDWithConnectionPropertiesTimeout() {
        // Given a timout when connecting
        // Given a problem when connecting
        mpdWrapper.password = ""
        mpdWrapper.connectionErrorCount = 4
        let connectionProperties = [ConnectionProperties.name.rawValue: "player",
                                    ConnectionProperties.host.rawValue: "host",
                                    ConnectionProperties.port.rawValue: 1000,
                                    ConnectionProperties.password.rawValue: ""] as [String: Any]
        
        // When connecting to MPD
        let conn = try! MPDHelper.connectToMPD(mpd: mpdWrapper, connectionProperties: connectionProperties, scheduler: MainScheduler.instance)
            .toBlocking()
            .first() ?? nil
        XCTAssertNil(conn, "Expected connection to be nil")

        // And connection_new is called once.
        mpdWrapper.assertCall("connection_new", expectedCallCount: 4)
        // And connection_free is called once.
        mpdWrapper.assertCall("connection_free", expectedCallCount: 4)
    }

    func testConnectToMPDRetry() {
        // Given a problem when connecting
        mpdWrapper.password = ""
        mpdWrapper.connectionErrorCount = 2
        let connectionProperties = [ConnectionProperties.name.rawValue: "player",
                                    ConnectionProperties.host.rawValue: "host",
                                    ConnectionProperties.port.rawValue: 1000,
                                    ConnectionProperties.password.rawValue: ""] as [String: Any]
        
        // When connecting to MPD
        let conn = try! MPDHelper.connectToMPD(mpd: mpdWrapper, connectionProperties: connectionProperties, scheduler: MainScheduler.instance)
            .toBlocking()
            .first() ?? nil
        XCTAssertNotNil(conn, "Expected connection to be present")

        // And connection_new is called once.
        mpdWrapper.assertCall("connection_new", expectedCallCount: 3)
        // And connection_free is called once.
        mpdWrapper.assertCall("connection_free", expectedCallCount: 2)
    }
    
    func testHostToUse() {
        XCTAssertEqual(MPDHelper.hostToUse([ConnectionProperties.name.rawValue: "player",
                                            ConnectionProperties.host.rawValue: "host",
                                            ConnectionProperties.port.rawValue: 1000,
                                            ConnectionProperties.password.rawValue: ""] as [String: Any]), "host")

        XCTAssertEqual(MPDHelper.hostToUse([ConnectionProperties.name.rawValue: "player",
                                            ConnectionProperties.host.rawValue: "host",
                                            MPDConnectionProperties.ipAddress.rawValue: "127.0.0.1",
                                            ConnectionProperties.port.rawValue: 1000,
                                            ConnectionProperties.password.rawValue: ""] as [String: Any]), "host")

        XCTAssertEqual(MPDHelper.hostToUse([ConnectionProperties.name.rawValue: "player",
                                            ConnectionProperties.host.rawValue: "host",
                                            MPDConnectionProperties.ipAddress.rawValue: "127.0.0.1",
                                            MPDConnectionProperties.connectToIpAddress.rawValue: true,
                                            ConnectionProperties.port.rawValue: 1000,
                                            ConnectionProperties.password.rawValue: ""] as [String: Any]), "127.0.0.1")

        XCTAssertEqual(MPDHelper.hostToUse([ConnectionProperties.name.rawValue: "player",
                                            ConnectionProperties.host.rawValue: "host",
                                            MPDConnectionProperties.ipAddress.rawValue: "127.0.0.1",
                                            MPDConnectionProperties.connectToIpAddress.rawValue: false,
                                            ConnectionProperties.port.rawValue: 1000,
                                            ConnectionProperties.password.rawValue: ""] as [String: Any]), "host")

        XCTAssertEqual(MPDHelper.hostToUse([ConnectionProperties.name.rawValue: "player",
                                            ConnectionProperties.host.rawValue: "host",
                                            MPDConnectionProperties.connectToIpAddress.rawValue: true,
                                            ConnectionProperties.port.rawValue: 1000,
                                            ConnectionProperties.password.rawValue: ""] as [String: Any]), "host")
    }
    
    func testCompareVersion() {
        var result: ComparisonResult
        
        result = MPDHelper.compareVersion(leftVersion: "0.1.0", rightVersion: "0.1.0")
        XCTAssert(result == .orderedSame, "Expected 0.1.0 and 0.1.0 to be equal")

        result = MPDHelper.compareVersion(leftVersion: "0.1", rightVersion: "0.1")
        XCTAssert(result == .orderedSame, "Expected 0.1 and 0.1 to be equal")
        
        result = MPDHelper.compareVersion(leftVersion: "0.1.23", rightVersion: "0.1")
        XCTAssert(result == .orderedSame, "Expected 0.1.23 and 0.1 to be equal")
        
        result = MPDHelper.compareVersion(leftVersion: "1", rightVersion: "1.1.1")
        XCTAssert(result == .orderedSame, "Expected 1 and 1.1.1 to be equal")
        
        result = MPDHelper.compareVersion(leftVersion: "1.3.28", rightVersion: "2")
        XCTAssert(result == .orderedAscending, "Expected 1.3.28 and 2 to be ascending")
        
        result = MPDHelper.compareVersion(leftVersion: "0.1.0", rightVersion: "0.1.1")
        XCTAssert(result == .orderedAscending, "Expected 0.1.0 and 0.1.1 to be ascending")

        result = MPDHelper.compareVersion(leftVersion: "0.1.255", rightVersion: "0.2.0")
        XCTAssert(result == .orderedAscending, "Expected 0.1.255 and 0.2.0 to be ascending")
        
        result = MPDHelper.compareVersion(leftVersion: "1.1.255", rightVersion: "1.2.0")
        XCTAssert(result == .orderedAscending, "Expected 1.1.255 and 1.2.0 to be ascending")
        
        result = MPDHelper.compareVersion(leftVersion: "2.16.28", rightVersion: "3.0.0")
        XCTAssert(result == .orderedAscending, "Expected 2.16.28 and 3.0.0 to be ascending")
        
        result = MPDHelper.compareVersion(leftVersion: "2.16.28", rightVersion: "2.16.29")
        XCTAssert(result == .orderedAscending, "Expected 2.16.28 and 2.16.29 to be ascending")

        result = MPDHelper.compareVersion(leftVersion: "2", rightVersion: "1.3.28")
        XCTAssert(result == .orderedDescending, "Expected 2 and 1.3.28 to be descending")
        
        result = MPDHelper.compareVersion(leftVersion: "0.1.1", rightVersion: "0.1.0")
        XCTAssert(result == .orderedDescending, "Expected 0.1.1 and 0.1.0 to be descending")

        result = MPDHelper.compareVersion(leftVersion: "0.2.0", rightVersion: "0.1.255")
        XCTAssert(result == .orderedDescending, "Expected 0.2.0 and 0.1.255 to be descending")

        result = MPDHelper.compareVersion(leftVersion: "1.2.0", rightVersion: "1.1.255")
        XCTAssert(result == .orderedDescending, "Expected 1.2.0 and 1.1.255 to be descending")

        result = MPDHelper.compareVersion(leftVersion: "3.0.0", rightVersion: "2.16.28")
        XCTAssert(result == .orderedDescending, "Expected 3.0.0 and 2.16.28 to be descending")

        result = MPDHelper.compareVersion(leftVersion: "2.16.29", rightVersion: "2.16.28")
        XCTAssert(result == .orderedDescending, "Expected 2.16.29 and 2.16.28 to be descending")
    }
    
    func testVolumeAdjustment() {
        XCTAssertEqual(MPDHelper.adjustedVolumeToPlayer(0.0, volumeAdjustment: nil), 0.0)
        XCTAssertLessThan(MPDHelper.adjustedVolumeToPlayer(0.2, volumeAdjustment: nil) - 0.2, 0.000001)
        XCTAssertLessThan(MPDHelper.adjustedVolumeToPlayer(0.4, volumeAdjustment: nil) - 0.4, 0.000001)
        XCTAssertLessThan(MPDHelper.adjustedVolumeToPlayer(0.5, volumeAdjustment: nil) - 0.5, 0.000001)
        XCTAssertLessThan(MPDHelper.adjustedVolumeToPlayer(0.6, volumeAdjustment: nil) - 0.6, 0.000001)
        XCTAssertLessThan(MPDHelper.adjustedVolumeToPlayer(0.8, volumeAdjustment: nil) - 0.8, 0.000001)
        XCTAssertEqual(MPDHelper.adjustedVolumeToPlayer(1.0, volumeAdjustment: nil), 1.0)

        XCTAssertEqual(MPDHelper.adjustedVolumeToPlayer(0.0, volumeAdjustment: 0.2), 0.0)
        XCTAssertLessThan(MPDHelper.adjustedVolumeToPlayer(0.2, volumeAdjustment: 0.2) - 0.08, 0.000001)
        XCTAssertLessThan(MPDHelper.adjustedVolumeToPlayer(0.4, volumeAdjustment: 0.2) - 0.16, 0.000001)
        XCTAssertLessThan(MPDHelper.adjustedVolumeToPlayer(0.5, volumeAdjustment: 0.2) - 0.2, 0.000001)
        XCTAssertLessThan(MPDHelper.adjustedVolumeToPlayer(0.6, volumeAdjustment: 0.2) - 0.36, 0.000001)
        XCTAssertLessThan(MPDHelper.adjustedVolumeToPlayer(0.8, volumeAdjustment: 0.2) - 0.68, 0.000001)
        XCTAssertEqual(MPDHelper.adjustedVolumeToPlayer(1.0, volumeAdjustment: 0.2), 1.0)

        XCTAssertEqual(MPDHelper.adjustedVolumeFromPlayer(0.0, volumeAdjustment: 0.2), 0.0)
        XCTAssertLessThan(MPDHelper.adjustedVolumeFromPlayer(0.08, volumeAdjustment: 0.2) - 0.2, 0.000001)
        XCTAssertLessThan(MPDHelper.adjustedVolumeFromPlayer(0.16, volumeAdjustment: 0.2) - 0.4, 0.000001)
        XCTAssertLessThan(MPDHelper.adjustedVolumeFromPlayer(0.2, volumeAdjustment: 0.2) - 0.5, 0.000001)
        XCTAssertLessThan(MPDHelper.adjustedVolumeFromPlayer(0.36, volumeAdjustment: 0.2) - 0.6, 0.000001)
        XCTAssertLessThan(MPDHelper.adjustedVolumeFromPlayer(0.68, volumeAdjustment: 0.2) - 0.8, 0.000001)
        XCTAssertEqual(MPDHelper.adjustedVolumeFromPlayer(1.0, volumeAdjustment: 0.2), 1.0)
    }
}
