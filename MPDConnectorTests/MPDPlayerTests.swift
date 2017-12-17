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
import RxSwift
import RxCocoa

class MPDPlayerTests: XCTestCase {
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
        
        // When creating a new MPDPlayer object and connecting to it
        mpdPlayer = MPDPlayer.init(mpd: mpdWrapper, name: "player", host: "localhost", port: 6600)
        var operation = BlockOperation(block: {
            self.mpdPlayer?.connect(numberOfRetries: 1)
        })
        
        // Then the status is set to connected
        var waitExpectation = XCTestExpectation(description: "Wait for connection")
        mpdPlayer?.connectionStatus
            .filter({ (connectionStatus) -> Bool in
                return connectionStatus == .Connected
            })
            .drive(onNext: { connectionStatus in
                // Then a new connection to an mpd server is created
                XCTAssert(self.mpdWrapper.callCount("connection_new") >= 1, "connection_new not called once")

                waitExpectation.fulfill()
            })
            .addDisposableTo(bag)

        operation.start()
        wait(for: [waitExpectation], timeout: 1.0)

        
        // Given the just created player
        
        // When cleaning up the connection
        waitExpectation = XCTestExpectation(description: "Waiting for cleanup")
        operation = BlockOperation(block: {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Then the mpd connection is freed
                if self.mpdWrapper.callCount("connection_free") == 1 {
                    waitExpectation.fulfill()
                }
            }
            
            self.mpdPlayer = nil
        })

        operation.start()
        wait(for: [waitExpectation], timeout: 1.0)
    }
    
    func testMPDPlayerCantConnect() {
        // Given nothing
        mpdWrapper.connectionErrorCount = 5
        
        // When connecting to a player fails
        mpdPlayer = MPDPlayer.init(mpd: mpdWrapper, name: "player", host: "localhost", port: 6600)
        let operation = BlockOperation(block: {
            self.mpdPlayer?.connect(numberOfRetries: 1)
        })
        
        // Then the status is set to disconnected
        let waitExpectation = XCTestExpectation(description: "Waiting for cleanup")
        mpdPlayer?.connectionStatus
            .filter({ (connectionStatus) -> Bool in
                return connectionStatus == .Disconnected
            })
            .drive(onNext: { connectionStatus in
                // Then a new connection to an mpd server is created
                XCTAssert(self.mpdWrapper.callCount("connection_new") >= 1, "connection_new not called")
                
                waitExpectation.fulfill()
            })
            .addDisposableTo(bag)
        
        operation.start()
        wait(for: [waitExpectation], timeout: 1.0)
    }

    func testMPDPlayerRetryConnect() {
        // Given nothing
        mpdWrapper.connectionErrorCount = 2
        
        // When connecting to a player fails
        mpdPlayer = MPDPlayer.init(mpd: mpdWrapper, name: "player", host: "localhost", port: 6600)
        let operation = BlockOperation(block: {
            self.mpdPlayer?.connect(numberOfRetries: 3)
        })
        
        // Then the status is set to disconnected
        let waitExpectation = XCTestExpectation(description: "Waiting for cleanup")
        mpdPlayer?.connectionStatus
            .filter({ (connectionStatus) -> Bool in
                return connectionStatus == .Connected
            })
            .drive(onNext: { connectionStatus in
                // Then a new connection to an mpd server is created
                XCTAssert(self.mpdWrapper.callCount("connection_new") == 3, "connection_new called \(self.mpdWrapper.callCount("connection_new")) instead of expected 3")
                
                waitExpectation.fulfill()
            })
            .addDisposableTo(bag)
        
        operation.start()
        wait(for: [waitExpectation], timeout: 1.0)
    }
    
    func testMPDPlayerDisconnect() {
        // Given a connected MPDPlayer
        mpdPlayer = MPDPlayer.init(mpd: mpdWrapper, name: "player", host: "localhost", port: 6600)

        var waitExpectation = XCTestExpectation(description: "Wait for connection")
        mpdPlayer?.connectionStatus
            .filter({ (connectionStatus) -> Bool in
                return connectionStatus == .Connected
            })
            .drive(onNext: { connectionStatus in
                waitExpectation.fulfill()
            })
            .addDisposableTo(bag)
        
        self.mpdPlayer?.connect(numberOfRetries: 3)
        wait(for: [waitExpectation], timeout: 1.0)

        mpdWrapper.clearAllCalls()
        
        // When a player looses its connection
        mpdWrapper.connectionError = MPD_ERROR_CLOSED
        mpdWrapper.connectionErrorMessage = "Connection lost"

        waitExpectation = XCTestExpectation(description: "Wait for disconnect")
        mpdPlayer?.connectionStatus
            .filter({ (connectionStatus) -> Bool in
                return connectionStatus == .Disconnected
            })
            .drive(onNext: { connectionStatus in
                waitExpectation.fulfill()
            })
            .addDisposableTo(bag)
        
        mpdPlayer!.controller.pause()
        wait(for: [waitExpectation], timeout: 1.0)

        // And connection is freed is called with value "pwd"
        mpdWrapper.assertCall("connection_free")
    }
    
    func testMPDPlayerValidPassword() {
        // Given nothing
        let password = "pwd"
        
        // When connecting to a player with a valid password
        mpdPlayer = MPDPlayer.init(mpd: mpdWrapper, name: "player", host: "localhost", port: 6600, password: password)
        let operation = BlockOperation(block: {
            self.mpdPlayer?.connect(numberOfRetries: 1)
        })
        
        // Then the status is set to disconnected
        let waitExpectation = XCTestExpectation(description: "Waiting for connect")
        mpdPlayer?.connectionStatus
            .filter({ (connectionStatus) -> Bool in
                return connectionStatus == .Connected
            })
            .drive(onNext: { connectionStatus in
                waitExpectation.fulfill()
            })
            .addDisposableTo(bag)
        
        operation.start()
        wait(for: [waitExpectation], timeout: 1.0)
    }
    
    func testMPDPlayerInvalidPassword() {
        // Given nothing
        mpdWrapper.connectionErrorCount = 1
        mpdWrapper.passwordValid = false
        let password = "pwd"
        
        // When connecting to a player with an invalid password
        mpdPlayer = MPDPlayer.init(mpd: mpdWrapper, name: "player", host: "localhost", port: 6600, password: password)
        let operation = BlockOperation(block: {
            self.mpdPlayer?.connect(numberOfRetries: 1)
        })
        
        // Then the status is set to disconnected
        let waitExpectation = XCTestExpectation(description: "Waiting for disconnect")
        mpdPlayer?.connectionStatus
            .filter({ (connectionStatus) -> Bool in
                return connectionStatus == .Disconnected
            })
            .drive(onNext: { connectionStatus in
                waitExpectation.fulfill()
            })
            .addDisposableTo(bag)
        
        operation.start()
        wait(for: [waitExpectation], timeout: 1.0)
    }
}
