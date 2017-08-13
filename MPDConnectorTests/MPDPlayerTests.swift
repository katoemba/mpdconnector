//
//  MPDConnectorTests.swift
//  MPDConnectorTests
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

        if let player = self.mpdPlayer {
            player.stopListeningForStatusUpdates()
            self.mpdPlayer = nil
        }
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
            
            if let player = self.mpdPlayer {
                player.stopListeningForStatusUpdates()
                self.mpdPlayer = nil
            }
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
        mpdPlayer!.pause()

        // Then the disconnectedHandler gets called
        wait(for: [mpdDisconnectedExpectation], timeout: 1.0)
        
        // And the status is .Disconnected
        XCTAssert(self.mpdPlayer!.connectionStatus == .Disconnected, "Expected connectionStatus \(ConnectionStatus.Disconnected), got '\(self.mpdPlayer!.connectionStatus)'")

        // And connection is freed is called with value "pwd"
        mpdWrapper.assertCall("connection_free")

        mpdWrapper.clearAllCalls()

        // When a subsequent call is made
        mpdPlayer!.pause()
        
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
    
    func testCommandsWhenNotConnected() {
        // Given an initialized but not connected MPDPlayer
        mpdPlayer = MPDPlayer.init(mpd: mpdWrapper, host: "localhost", port: 6600,
                                   connectedHandler: { (mpdPlayer) in
                                    self.mpdConnectedExpectation?.fulfill()
        },
                                   disconnectedHandler: { (mpdPlayer, errorNumber, errorMessage) in
        })
        
        // When setting the volume to 0.6
        mpdPlayer?.setVolume(volume: 0.6)
        
        // Then wait for 0.2 seconds and check if run_play is not called
        var waitForCallExpectation = waitForCall("run_set_volume", expectedCalls: 0, waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)

        // When giving a play command
        mpdPlayer?.play()
        
        // Then wait for 0.2 seconds and check if run_play is called
        waitForCallExpectation = waitForCall("run_play", expectedCalls: 0, waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
        
        // When giving a pause command
        mpdPlayer?.pause()
        
        // Then wait for 0.2 seconds and check if run_pause is called
        waitForCallExpectation = waitForCall("run_pause", expectedCalls: 0, waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)

        // When giving a pause command
        mpdPlayer?.togglePlayPause()
        
        // Then wait for 0.2 seconds and check if run_toggle_pause is called
        waitForCallExpectation = waitForCall("run_toggle_pause", expectedCalls: 0, waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)

        // When giving a skip command
        mpdPlayer?.skip()
        
        // Then wait for 0.2 seconds and check if run_next is called
        waitForCallExpectation = waitForCall("run_next", expectedCalls: 0, waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)

        // When giving a back command
        mpdPlayer?.back()
        
        // Then wait for 0.2 seconds and check if run_previous is called
        waitForCallExpectation = waitForCall("run_previous", expectedCalls: 0, waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)

        // When giving a repeat:off command
        mpdPlayer?.setRepeat(repeatMode: .Off)
        
        // Then wait for 0.2 seconds and check if run_repeat is called
        waitForCallExpectation = waitForCall("run_repeat", expectedCalls: 0, waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)

        // When giving a repeat:off command
        mpdPlayer?.setShuffle(shuffleMode: .Off)
        
        // Then wait for 0.2 seconds and check if run_random is called
        waitForCallExpectation = waitForCall("run_random", expectedCalls: 0, waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)

        // When giving a fetchStatus command
        mpdPlayer?.fetchStatus()
        
        // Then wait for 0.2 seconds and check if run_status is called
        waitForCallExpectation = waitForCall("run_status", expectedCalls: 0, waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
    }
    
    func testSetValidVolumeSentToMPD() {
        // Given an initialized MPDPlayer
        setupConnectionToPlayer()
        
        // When setting the volume to 0.6
        mpdPlayer?.setVolume(volume: 0.6)
        
        // Then wait for 0.2 seconds and check if run_set_volume is called
        let waitForCallExpectation = waitForCall("run_set_volume", waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
        

        // Then mpd_run_set_volume is called with value 60
        mpdWrapper.assertCall("run_set_volume", expectedParameters: ["volume": "\(60)"])
    }

    func testSetInvalidVolumeNotSentToMPD() {
        // Given an initialized MPDPlayer
        setupConnectionToPlayer()
        
        // When setting the volume to -10.0
        mpdPlayer?.setVolume(volume: -10.0)
        
        // Then wait for 0.2 seconds and check if run_play is called
        let waitForCallExpectation = waitForCall("run_set_volume", expectedCalls: 0, waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)

        // Given an initialized MPDPlayer
        mpdWrapper.clearAllCalls()
        
        // When setting the volume to 1.1
        mpdPlayer?.setVolume(volume: 1.1)
        
        // Then this is not passed to mpd
        wait(for: [waitForCallExpectation], timeout: 0.3)
    }
    
    func testPlaySentToMPD() {
        // Given an initialized MPDPlayer
        setupConnectionToPlayer()
        
        // When giving a play command
        mpdPlayer?.play()
        
        // Then wait for 0.2 seconds and check if run_play is called
        let waitForCallExpectation = waitForCall("run_play", waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
        
        // Then mpd_run_play is called
        mpdWrapper.assertCall("run_play")
        
        // Then mpd_run_status/mpd_status_free are called.
        mpdWrapper.assertCall("run_status")
        mpdWrapper.assertCall("status_free")
    }

    func testPauseSentToMPD() {
        // Given an initialized MPDPlayer
        setupConnectionToPlayer()
        
        // When giving a pause command
        mpdPlayer?.pause()
        
        // Then wait for 0.2 seconds and check if run_pause is called
        let waitForCallExpectation = waitForCall("run_pause", waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)

        mpdWrapper.assertCall("run_pause", expectedParameters: ["mode": "\(true)"])
        
        // Then mpd_run_status/mpd_status_free are called.
        mpdWrapper.assertCall("run_status")
        mpdWrapper.assertCall("status_free")
    }

    func testTogglePauseSentToMPD() {
        // Given an initialized MPDPlayer
        setupConnectionToPlayer()
        
        // When giving a pause command
        mpdPlayer?.togglePlayPause()
        
        // Then wait for 0.2 seconds and check if run_toggle_pause is called
        let waitForCallExpectation = waitForCall("run_toggle_pause", waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
        
        // Then mpd_run_pause is called with mode = true
        mpdWrapper.assertCall("run_toggle_pause")
        
        // Then mpd_run_status/mpd_status_free are called.
        mpdWrapper.assertCall("run_status")
        mpdWrapper.assertCall("status_free")
    }
    
    func testSkipSentToMPD() {
        // Given an initialized MPDPlayer
        setupConnectionToPlayer()
        
        // When giving a skip command
        mpdPlayer?.skip()
        
        // Then wait for 0.2 seconds and check if run_next is called
        let waitForCallExpectation = waitForCall("run_next", waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
        
        // Then mpd_run_next is called
        mpdWrapper.assertCall("run_next")
        
        // Then mpd_run_status/mpd_status_free are called.
        mpdWrapper.assertCall("run_status")
        mpdWrapper.assertCall("status_free")
    }
    
    func testBackSentToMPD() {
        // Given an initialized MPDPlayer
        setupConnectionToPlayer()
        
        // When giving a back command
        mpdPlayer?.back()
        
        // Then wait for 0.2 seconds and check if run_previous is called
        let waitForCallExpectation = waitForCall("run_previous", waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
        
        // Then mpd_run_next is called
        mpdWrapper.assertCall("run_previous")
        
        // Then mpd_run_status/mpd_status_free are called.
        mpdWrapper.assertCall("run_status")
        mpdWrapper.assertCall("status_free")
    }
    
    func testRepeatOffSentToMPD() {
        // Given an initialized MPDPlayer
        setupConnectionToPlayer()
        
        // When giving a repeat:off command
        mpdPlayer?.setRepeat(repeatMode: .Off)
        
        // Then wait for 0.2 seconds and check if run_repeat is called
        let waitForCallExpectation = waitForCall("run_repeat", waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
        
        // Then mpd_run_repeat is called with mode: false
        mpdWrapper.assertCall("run_repeat", expectedParameters: ["mode": "\(false)"])
        
        // Then mpd_run_status/mpd_status_free are called.
        mpdWrapper.assertCall("run_status")
        mpdWrapper.assertCall("status_free")
    }

    func testRepeatSingleSentToMPD() {
        // Given an initialized MPDPlayer
        setupConnectionToPlayer()
        
        // When giving a repeat:single command
        mpdPlayer?.setRepeat(repeatMode: .Single)
        
        // Then wait for 0.2 seconds and check if run_repeat is called
        let waitForCallExpectation = waitForCall("run_repeat", waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
        
        // Then mpd_run_repeat is called with mode: true
        mpdWrapper.assertCall("run_repeat", expectedParameters: ["mode": "\(true)"])
        
        // Then mpd_run_status/mpd_status_free are called.
        mpdWrapper.assertCall("run_status")
        mpdWrapper.assertCall("status_free")
    }

    func testRepeatAllSentToMPD() {
        // Given an initialized MPDPlayer
        setupConnectionToPlayer()
        
        // When giving a repeat:all command
        mpdPlayer?.setRepeat(repeatMode: .All)
        
        // Then wait for 0.2 seconds and check if run_repeat is called
        let waitForCallExpectation = waitForCall("run_repeat", waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
        
        // Then mpd_run_repeat is called with mode: true
        mpdWrapper.assertCall("run_repeat", expectedParameters: ["mode": "\(true)"])
        
        // Then mpd_run_status/mpd_status_free are called.
        mpdWrapper.assertCall("run_status")
        mpdWrapper.assertCall("status_free")
    }

    func testRepeatAlbumSentToMPD() {
        // Given an initialized MPDPlayer
        setupConnectionToPlayer()
        
        // When giving a repeat:album command
        mpdPlayer?.setRepeat(repeatMode: .Album)
        
        // Then wait for 0.2 seconds and check if run_repeat is called
        let waitForCallExpectation = waitForCall("run_repeat", waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
        
        // Then mpd_run_repeat is called with mode: true
        mpdWrapper.assertCall("run_repeat", expectedParameters: ["mode": "\(true)"])
        
        // Then mpd_run_status/mpd_status_free are called.
        mpdWrapper.assertCall("run_status")
        mpdWrapper.assertCall("status_free")
    }
    
    func testShuffleOffSentToMPD() {
        // Given an initialized MPDPlayer
        setupConnectionToPlayer()
        
        // When giving a repeat:off command
        mpdPlayer?.setShuffle(shuffleMode: .Off)
        
        // Then wait for 0.2 seconds and check if run_random is called
        let waitForCallExpectation = waitForCall("run_random", waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
        
        // Then mpd_run_random is called with mode: false
        mpdWrapper.assertCall("run_random", expectedParameters: ["mode": "\(false)"])
        
        // Then mpd_run_status/mpd_status_free are called.
        mpdWrapper.assertCall("run_status")
        mpdWrapper.assertCall("status_free")
    }
    
    func testShuffleOnSentToMPD() {
        // Given an initialized MPDPlayer
        setupConnectionToPlayer()
        
        // When giving a repeat:single command
        mpdPlayer?.setShuffle(shuffleMode: .On)
        
        // Then wait for 0.2 seconds and check if run_random is called
        let waitForCallExpectation = waitForCall("run_random", waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
        
        // Then mpd_run_random is called with mode: true
        mpdWrapper.assertCall("run_random", expectedParameters: ["mode": "\(true)"])
        
        // Then mpd_run_status/mpd_status_free are called.
        mpdWrapper.assertCall("run_status")
        mpdWrapper.assertCall("status_free")
    }
    
    func testFetchStatus() {
        // Given an initialized MPDPlayer
        mpdWrapper.volume = 10
        mpdWrapper.elapsedTime = 20
        mpdWrapper.trackTime = 30
        mpdWrapper.songTitle = "Creature Comfort"
        mpdWrapper.album = "Everything Now"
        mpdWrapper.artist = "Arcade Fire"
        mpdWrapper.repeatValue = true
        mpdWrapper.random = true
        mpdWrapper.state = MPD_STATE_PLAY
        setupConnectionToPlayer()
        
        // When giving a fetchStatus command
        mpdPlayer?.fetchStatus()
        
        // Then wait for 0.2 seconds and check if run_status is called
        let waitForCallExpectation = waitForCall("run_status", waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
        
        // Then mpd_run_status/mpd_status_free are called.
        mpdWrapper.assertCall("run_status")
        mpdWrapper.assertCall("status_free")

        // Then mpd_run_current_song/mpd_song_free are called.
        mpdWrapper.assertCall("run_current_song")
        mpdWrapper.assertCall("song_free")
        
        // Then playerStatus.volume = 0.1
        XCTAssert(mpdPlayer?.playerStatus.volume == 0.1, "playerStatus.volume expected 0.1, got \(String(describing: mpdPlayer?.playerStatus.volume))")

        // Then playerStatus.elapsedTime = 20
        XCTAssert(mpdPlayer?.playerStatus.elapsedTime == 20, "playerStatus.elapsedTime expected 10, got \(String(describing: mpdPlayer?.playerStatus.elapsedTime))")

        // Then playerStatus.trackTime = 30
        XCTAssert(mpdPlayer?.playerStatus.trackTime == 30, "playerStatus.trackTime expected 20, got \(String(describing: mpdPlayer?.playerStatus.trackTime))")
        
        // Then playerStatus.song = "Creature Comfort"
        XCTAssert(mpdPlayer?.playerStatus.song == "Creature Comfort", "playerStatus.songTitle expected 'Creature Comfort', got \(String(describing: mpdPlayer?.playerStatus.song))")
        
        // Then playerStatus.album = "Everything Now"
        XCTAssert(mpdPlayer?.playerStatus.album == "Everything Now", "playerStatus.album expected 'Everything Now', got \(String(describing: mpdPlayer?.playerStatus.album))")
        
        // Then playerStatus.artist = "Arcade Fire"
        XCTAssert(mpdPlayer?.playerStatus.artist == "Arcade Fire", "playerStatus.artist expected 'Arcade Fire', got \(String(describing: mpdPlayer?.playerStatus.artist))")
        
        // Then playerStatus.repeatMode = .All
        XCTAssert(mpdPlayer?.playerStatus.repeatMode == .All, "playerStatus.artist expected .All, got \(String(describing: mpdPlayer?.playerStatus.repeatMode))")
        
        // Then playerStatus.shuffleMode = .On
        XCTAssert(mpdPlayer?.playerStatus.shuffleMode == .On, "playerStatus.artist expected .On, got \(String(describing: mpdPlayer?.playerStatus.shuffleMode))")
        
        // Then playerStatus.playingStatus = .Playing
        XCTAssert(mpdPlayer?.playerStatus.playingStatus == .Playing, "playerStatus.playingStatus expected .Playing, got \(String(describing: mpdPlayer?.playerStatus.playingStatus))")
    }
}
