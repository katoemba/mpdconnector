//
//  MPDPlayerTests.swift
//  MPDConnector
//
//  Created by Berrie Kremers on 09-08-17.
//  Copyright © 2017 Kaotemba Software. All rights reserved.
//

import XCTest
import ConnectorProtocol
import MPDConnector
import libmpdclient

class MPDPlayerTests: XCTestCase {    
    var mpdWrapper = MPDWrapperMock()
    var mpdPlayer: MPDPlayer?
    var mpdConnectedExpectation: XCTestExpectation?
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.

        mpdWrapper = MPDWrapperMock()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()

        self.mpdPlayer = nil
    }
    
    func setupConnectionToPlayer(clearAllCalls: Bool = true) {
        // Setup a mpdPlayer connection and wait until it's connected.
        mpdConnectedExpectation = expectation(description: "Connected to MPD Player")
        mpdPlayer = MPDPlayer.init(mpd: mpdWrapper, host: "localhost", port: 6600,
                                   connectedHandler: { (mpdPlayer) in
                                    self.mpdConnectedExpectation?.fulfill()
        },
                                   disconnectedHandler: { (mpdPlayer, errorNumber, errorMessage) in
        })
        mpdPlayer?.connect()
        waitForExpectations(timeout: 1.0, handler: nil)
        
        if clearAllCalls {
            mpdWrapper.clearAllCalls()
        }
    }
    
    func waitForCall(_ functionName: String, expectedCalls: Int = 1, waitTime: Float = 0.5) -> XCTestExpectation {
        let waitExpectation = expectation(description: "Wait for timeout")
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(waitTime)) {
            if self.mpdWrapper.callCount(functionName) == expectedCalls {
                waitExpectation.fulfill()
            }
        }
        
        return waitExpectation
    }
    
    func testMPDPlayerInitializationAndCleanup() {
        // Given nothing
        
        // When creating a new MPDPlayer object
        setupConnectionToPlayer(clearAllCalls: false)
        
        // Then a new connection to an mpd server is created
        XCTAssert(self.mpdWrapper.callCount("connection_new") == 1, "connection_new not called once")
        
        // And the status is .Connected
        XCTAssert(self.mpdPlayer!.connectionStatus == .Connected, "Expected connectionStatus \(ConnectionStatus.Connected), got '\(self.mpdPlayer!.connectionStatus)'")
        
        // Given an existing MPDPlayer object (created during setup)
        
        // When cleaning up the connection
        let waitExpectation = expectation(description: "Waiting for cleanup")
        let operation = BlockOperation(block: {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if self.mpdWrapper.callCount("connection_free") == 1 {
                    waitExpectation.fulfill()
                }
            }
            
            self.mpdPlayer = nil
        })
        operation.start()

        // Then the mpd connection is freed
        waitForExpectations(timeout: 1.0, handler: nil)
    }
    
    func testMPDPlayerCantConnect() {
        // Given nothing
        mpdWrapper.connectionError = MPD_ERROR_RESOLVER
        mpdWrapper.connectionErrorMessage = "An error"
        
        // When connecting to a player fails
        
        // Then the disconnectedHandler gets called
        let mpdDisconnectedExpectation = expectation(description: "Not connected to MPD Player")
        mpdPlayer = MPDPlayer.init(mpd: mpdWrapper, host: "localhost", port: 6600,
                                   connectedHandler: { (mpdPlayer) in
        },
                                   disconnectedHandler: { (mpdPlayer, errorNumber, errorMessage) in
                                    mpdDisconnectedExpectation.fulfill()
                                    XCTAssert(errorNumber == Int(MPD_ERROR_RESOLVER.rawValue), "Expected errorNumber \(MPD_ERROR_RESOLVER), got \(errorNumber)")
                                    XCTAssert(errorMessage == "An error", "Expected errorMessage 'An error', got '\(errorMessage)'")
        })
        mpdPlayer?.connect()
        waitForExpectations(timeout: 1.0, handler: nil)
        
        // And the status is .Disconnected
        XCTAssert(self.mpdPlayer!.connectionStatus == .Disconnected, "Expected connectionStatus \(ConnectionStatus.Disconnected), got '\(self.mpdPlayer!.connectionStatus)'")
    }

    func testMPDPlayerDisconnect() {
        // Given an initialized MPDPlayer
        let mpdConnectedExpectation = expectation(description: "Connected to MPD Player")
        let mpdDisconnectedExpectation = expectation(description: "Not connected to MPD Player")
        mpdPlayer = MPDPlayer.init(mpd: mpdWrapper, host: "localhost", port: 6600,
                                   connectedHandler: { (mpdPlayer) in
                                    mpdConnectedExpectation.fulfill()
        },
                                   disconnectedHandler: { (mpdPlayer, errorNumber, errorMessage) in
                                    mpdDisconnectedExpectation.fulfill()
                                    XCTAssert(errorNumber == Int(MPD_ERROR_CLOSED.rawValue), "Expected errorNumber \(MPD_ERROR_CLOSED), got \(errorNumber)")
                                    XCTAssert(errorMessage == "Connection lost", "Expected errorMessage 'Connection lost', got '\(errorMessage)'")
        })
        mpdPlayer?.connect()
        wait(for: [mpdConnectedExpectation], timeout: 1.0)
        XCTAssert(mpdPlayer!.connectionStatus == .Connected, "Expected connectionStatus \(ConnectionStatus.Connected), got '\(mpdPlayer!.connectionStatus)'")

        mpdWrapper.clearAllCalls()
        
        // When a player looses its connection
        mpdWrapper.connectionError = MPD_ERROR_CLOSED
        mpdWrapper.connectionErrorMessage = "Connection lost"
        mpdPlayer!.controller.pause()

        // Then the disconnectedHandler gets called
        wait(for: [mpdDisconnectedExpectation], timeout: 1.0)
        
        // And the status is .Disconnected
        XCTAssert(self.mpdPlayer!.connectionStatus == .Disconnected, "Expected connectionStatus \(ConnectionStatus.Disconnected), got '\(self.mpdPlayer!.connectionStatus)'")

        // And connection is freed is called with value "pwd"
        mpdWrapper.assertCall("connection_free")

        mpdWrapper.clearAllCalls()

        // When a subsequent call is made
        mpdPlayer!.controller.pause()
        
        // Then the status remains .Disconnected
        XCTAssert(self.mpdPlayer!.connectionStatus == .Disconnected, "Expected connectionStatus \(ConnectionStatus.Disconnected), got '\(self.mpdPlayer!.connectionStatus)'")

        // And connection_free is not called this time
        XCTAssert(mpdWrapper.callCount("connection_free") == 0, "mpd_connection_free called unexpectedly")
    }
    
    func testMPDPlayerValidPassword() {
        // Given nothing
        let password = "pwd"
        
        // When connecting to a player with a valid password
        
        // Then the disconnectedHandler gets called
        let mpdConnectedExpectation = expectation(description: "Not connected to MPD Player")
        mpdPlayer = MPDPlayer.init(mpd: mpdWrapper, host: "localhost", port: 6600, password: password,
                                   connectedHandler: { (mpdPlayer) in
                                    mpdConnectedExpectation.fulfill()
        },
                                   disconnectedHandler: { (mpdPlayer, errorNumber, errorMessage) in
        })
        mpdPlayer?.connect()
        waitForExpectations(timeout: 1.0, handler: nil)
        
        // And mpd_run_password is called with value "pwd"
        mpdWrapper.assertCall("run_password", expectedParameters: ["password": "\(password)"])

        // And the status is .Connected
        XCTAssert(self.mpdPlayer!.connectionStatus == .Connected, "Expected connectionStatus \(ConnectionStatus.Connected), got '\(self.mpdPlayer!.connectionStatus)'")
    }
    
    func testMPDPlayerInvalidPassword() {
        // Given nothing
        mpdWrapper.passwordValid = false
        mpdWrapper.connectionErrorMessage = "An error"
        let password = "pwd"
        
        // When connecting to a player with an invalid password
        
        // Then the disconnectedHandler gets called
        let mpdDisconnectedExpectation = expectation(description: "Not connected to MPD Player")
        mpdPlayer = MPDPlayer.init(mpd: mpdWrapper, host: "localhost", port: 6600, password: password,
                                   connectedHandler: { (mpdPlayer) in
        },
                                   disconnectedHandler: { (mpdPlayer, errorNumber, errorMessage) in
                                    mpdDisconnectedExpectation.fulfill()
                                    XCTAssert(errorNumber == Int(MPD_ERROR_SERVER.rawValue), "Expected errorNumber \(MPD_ERROR_SERVER), got \(errorNumber)")
                                    XCTAssert(errorMessage == "An error", "Expected errorMessage 'An error', got '\(errorMessage)'")
        })
        mpdPlayer?.connect()
        waitForExpectations(timeout: 1.0, handler: nil)

        // And mpd_run_password is called with value "pwd"
        mpdWrapper.assertCall("run_password", expectedParameters: ["password": "\(password)"])
        
        // And the status is .Disconnected
        XCTAssert(self.mpdPlayer!.connectionStatus == .Disconnected, "Expected connectionStatus \(ConnectionStatus.Disconnected), got '\(self.mpdPlayer!.connectionStatus)'")
    }
}
