//
//  MPDPlayerTests.swift
//  MPDConnector
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

import XCTest
import ConnectorProtocol
import MPDConnector
import libmpdclient
import RxSwift
import RxCocoa

class MPDPlayerTests: XCTestCase {
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
    
    func waitForCall(_ functionName: String, expectedCalls: Int = 1, waitTime: Float = 0.5) -> XCTestExpectation {
        let waitExpectation = expectation(description: "Wait for timeout")
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(waitTime)) {
            if self.mpdWrapper.callCount(functionName) == expectedCalls {
                waitExpectation.fulfill()
            }
        }
        
        return waitExpectation
    }
    
    func testMPDPlayerStatusShared() {
        // Given a mpd player
        let connectionProperties = [ConnectionProperties.Name.rawValue: "player",
                                    ConnectionProperties.Host.rawValue: "host",
                                    ConnectionProperties.Port.rawValue: 1000,
                                    ConnectionProperties.Password.rawValue: ""] as [String: Any]
        
        // When creating a new MPDPlayer object and connecting to it
        let mpdPlayer = MPDPlayer.init(mpd: mpdWrapper, connectionProperties: connectionProperties)
        
        // It holds a shared Status object
        let status1 = mpdPlayer.status as! MPDStatus
        let status2 = mpdPlayer.status as! MPDStatus

        XCTAssert(status1 === status2, "Expected shared status object, got different objects")
    }
    
    func testMPDPlayerControlNotShared() {
        // Given a mpd player
        let connectionProperties = [ConnectionProperties.Name.rawValue: "player",
                                    ConnectionProperties.Host.rawValue: "host",
                                    ConnectionProperties.Port.rawValue: 1000,
                                    ConnectionProperties.Password.rawValue: ""] as [String: Any]
        
        // When creating a new MPDPlayer object and connecting to it
        let mpdPlayer = MPDPlayer.init(mpd: mpdWrapper, connectionProperties: connectionProperties)
        
        // It holds a shared Status object
        let control1 = mpdPlayer.control as! MPDControl
        let control2 = mpdPlayer.control as! MPDControl
        
        XCTAssert(control1 !== control2, "Expected separate control objects, got the same object")
    }

    func testMPDPlayerBrowseNotShared() {
        // Given a mpd player
        let connectionProperties = [ConnectionProperties.Name.rawValue: "player",
                                    ConnectionProperties.Host.rawValue: "host",
                                    ConnectionProperties.Port.rawValue: 1000,
                                    ConnectionProperties.Password.rawValue: ""] as [String: Any]
        
        // When creating a new MPDPlayer object and connecting to it
        let mpdPlayer = MPDPlayer.init(mpd: mpdWrapper, connectionProperties: connectionProperties)
        
        // It holds a shared Status object
        let browse1 = mpdPlayer.browse as! MPDBrowse
        let browse2 = mpdPlayer.browse as! MPDBrowse
        
        XCTAssert(browse1 !== browse2, "Expected separate control objects, got the same object")
    }
    
    func testMPDPlayerEqual() {
        // Given 2 players both named "Player 1"
        let connectionProperties1 = [ConnectionProperties.Name.rawValue: "Player 1",
                                    ConnectionProperties.Host.rawValue: "host",
                                    ConnectionProperties.Port.rawValue: 1000,
                                    ConnectionProperties.Password.rawValue: ""] as [String: Any]
        let connectionProperties2 = [ConnectionProperties.Name.rawValue: "Player 1",
                                     ConnectionProperties.Host.rawValue: "host",
                                     ConnectionProperties.Port.rawValue: 1000,
                                     ConnectionProperties.Password.rawValue: ""] as [String: Any]

        // When creating player objects for them
        let mpdPlayer1 = MPDPlayer.init(mpd: mpdWrapper, connectionProperties: connectionProperties1)
        let mpdPlayer2 = MPDPlayer.init(mpd: mpdWrapper, connectionProperties: connectionProperties2)

        // They are viewed as equal
        XCTAssert(mpdPlayer1 == mpdPlayer2, "Expected players to be equal, got that they are different")
    }

    func testMPDPlayerDifferent() {
        // Given 2 players named "Player 1" and "Player 2"
        let connectionProperties1 = [ConnectionProperties.Name.rawValue: "Player 1",
                                     ConnectionProperties.Host.rawValue: "host 1",
                                     ConnectionProperties.Port.rawValue: 1000,
                                     ConnectionProperties.Password.rawValue: ""] as [String: Any]
        let connectionProperties2 = [ConnectionProperties.Name.rawValue: "Player 1",
                                     ConnectionProperties.Host.rawValue: "host 2",
                                     ConnectionProperties.Port.rawValue: 1000,
                                     ConnectionProperties.Password.rawValue: ""] as [String: Any]
        
        // When creating player objects for them
        let mpdPlayer1 = MPDPlayer.init(mpd: mpdWrapper, connectionProperties: connectionProperties1)
        let mpdPlayer2 = MPDPlayer.init(mpd: mpdWrapper, connectionProperties: connectionProperties2)
        
        // They are viewed as equal
        XCTAssert(mpdPlayer1 != mpdPlayer2, "Expected players to be different, got that they are equal")
    }
    
    func testActivateDeactivate() {
        // Given a mpd player
        let connectionProperties = [ConnectionProperties.Name.rawValue: "player",
                                    ConnectionProperties.Host.rawValue: "host",
                                    ConnectionProperties.Port.rawValue: 1000,
                                    ConnectionProperties.Password.rawValue: ""] as [String: Any]
        self.mpdWrapper.songIndex = 5
        
        // When creating a new MPDStatus object and starting it
        let mpdPlayer = MPDPlayer.init(mpd: mpdWrapper, connectionProperties: connectionProperties)
        mpdPlayer.activate()
        
        // And changing the songIndex, stopping and changing the songIndex again
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.mpdWrapper.songIndex = 6
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            mpdPlayer.deactivate()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.mpdWrapper.songIndex = 7
        }
        
        // Then only the songIndex values before the 'stop' are reported.
        let playerStatusResults = mpdPlayer.status.playerStatusObservable
            .toBlocking(timeout: 0.8)
            .materialize()
        
        switch playerStatusResults {
        case .failed(let playerStatusArray, _):
            let songIndexArray = playerStatusArray.map({ (status) -> Int in
                status.playqueue.songIndex
            })
            XCTAssert(songIndexArray == [0, 5, 6], "Expected reported song indexes [0, 5, 6], got \(songIndexArray)")
        default:
            print("Default")
        }
    }
    
}
