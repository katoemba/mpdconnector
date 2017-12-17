//
//  MPDControllerTests.swift
//  MPDConnector
//
//  Created by Berrie Kremers on 26-08-17.
//  Copyright © 2017 Kaotemba Software. All rights reserved.
//

import XCTest
import ConnectorProtocol
import MPDConnector
import libmpdclient
import RxSwift

class MPDControllerTests: XCTestCase {
    var mpdWrapper = MPDWrapperMock()
    var mpdPlayer: MPDPlayer?
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
        
        if self.mpdPlayer != nil {
            self.mpdPlayer = nil
        }
    }
    
    func setupConnectionToPlayer(clearAllCalls: Bool = true) {
        // Setup a mpdPlayer connection and wait until it's connected.
        mpdPlayer = MPDPlayer.init(mpd: mpdWrapper, name: "player", host: "localhost", port: 6600)
 
        let waitExpectation = XCTestExpectation(description: "Wait for connection")
        mpdPlayer?.connectionStatus
            .filter({ (connectionStatus) -> Bool in
                return connectionStatus == .Connected
            })
            .distinctUntilChanged()
            .drive(onNext: { connectionStatus in
                // Then a new connection to an mpd server is created
                XCTAssert(self.mpdWrapper.callCount("connection_new") >= 1, "connection_new not called")
                
                if clearAllCalls {
                    self.mpdWrapper.clearAllCalls()
                }

                waitExpectation.fulfill()
            })
            .disposed(by: bag)

        mpdPlayer?.connect()
        wait(for: [waitExpectation], timeout: 1.0)
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
    
    func testCommandsWhenNotConnected() {
        // Given an initialized but not connected MPDPlayer
        mpdPlayer = MPDPlayer.init(mpd: mpdWrapper, name: "player", host: "localhost", port: 6600)
        
        // When setting the volume to 0.6
        mpdPlayer?.controller.setVolume(volume: 0.6)
        
        // Then wait for 0.2 seconds and check if run_play is not called
        var waitForCallExpectation = waitForCall("run_set_volume", expectedCalls: 0, waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
        
        // When giving a play command
        mpdPlayer?.controller.play()
        
        // Then wait for 0.2 seconds and check if run_play is called
        waitForCallExpectation = waitForCall("run_play", expectedCalls: 0, waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
        
        // When giving a play(3) command
        mpdWrapper.queueLength = 10
        mpdPlayer?.controller.play(index: 3)
        
        // Then wait for 0.2 seconds and check if run_play_pos is called
        waitForCallExpectation = waitForCall("run_play_pos", expectedCalls: 0, waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
        
        // When giving a pause command
        mpdPlayer?.controller.pause()
        
        // Then wait for 0.2 seconds and check if run_pause is called
        waitForCallExpectation = waitForCall("run_pause", expectedCalls: 0, waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
        
        // When giving a pause command
        mpdPlayer?.controller.togglePlayPause()
        
        // Then wait for 0.2 seconds and check if run_toggle_pause is called
        waitForCallExpectation = waitForCall("run_toggle_pause", expectedCalls: 0, waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
        
        // When giving a skip command
        mpdPlayer?.controller.skip()
        
        // Then wait for 0.2 seconds and check if run_next is called
        waitForCallExpectation = waitForCall("run_next", expectedCalls: 0, waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
        
        // When giving a back command
        mpdPlayer?.controller.back()
        
        // Then wait for 0.2 seconds and check if run_previous is called
        waitForCallExpectation = waitForCall("run_previous", expectedCalls: 0, waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
        
        // When giving a repeat:off command
        mpdPlayer?.controller.setRepeat(repeatMode: .Off)
        
        // Then wait for 0.2 seconds and check if run_repeat is called
        waitForCallExpectation = waitForCall("run_repeat", expectedCalls: 0, waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
        
        // When giving a repeat:off command
        mpdPlayer?.controller.setRandom(randomMode: .Off)
        
        // Then wait for 0.2 seconds and check if run_random is called
        waitForCallExpectation = waitForCall("run_random", expectedCalls: 0, waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)

        // When giving a repeat:off command
        mpdPlayer?.controller.toggleRepeat()
        
        // Then wait for 0.2 seconds and check if run_random is called
        waitForCallExpectation = waitForCall("run_repeat", expectedCalls: 0, waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)

        // When giving a repeat:off command
        mpdPlayer?.controller.toggleRandom()
        
        // Then wait for 0.2 seconds and check if run_random is called
        waitForCallExpectation = waitForCall("run_random", expectedCalls: 0, waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
    }
    
    func testSetValidVolumeSentToMPD() {
        // Given an initialized MPDPlayer
        setupConnectionToPlayer()
        
        // When setting the volume to 0.6
        mpdPlayer?.controller.setVolume(volume: 0.6)
        
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
        mpdPlayer?.controller.setVolume(volume: -10.0)
        
        // Then wait for 0.2 seconds and check if run_play is called
        let waitForCallExpectation = waitForCall("run_set_volume", expectedCalls: 0, waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
        
        // Given an initialized MPDPlayer
        mpdWrapper.clearAllCalls()
        
        // When setting the volume to 1.1
        mpdPlayer?.controller.setVolume(volume: 1.1)
        
        // Then this is not passed to mpd
        wait(for: [waitForCallExpectation], timeout: 0.3)
    }
    
    func testPlaySentToMPD() {
        // Given an initialized MPDPlayer
        setupConnectionToPlayer()
        
        let waitForStatusUpdate = XCTestExpectation(description: "Wait for Status Update")
        mpdPlayer?.controller.playerStatus
            .filter({ (playerStatus) -> Bool in
                return playerStatus.playing.playPauseMode != .Paused
            })
            .drive(onNext: { playerStatus in
                waitForStatusUpdate.fulfill()
                
                // Then playing.playPauseMode = .Playing
                XCTAssert(playerStatus.playing.playPauseMode == .Playing, "playing.playingStatus expected .Playing, got \(String(describing: playerStatus.playing.playPauseMode))")
            })
            .disposed(by: bag)
        
        // When giving a play command
        mpdPlayer?.controller.play()
        
        // Then wait for a status update
        wait(for: [waitForStatusUpdate], timeout: 0.5)
        
        // Then mpd_run_pause is called with mode = true
        mpdWrapper.assertCall("run_play")
    }
    
    func testPlayWithIndexSentToMPD() {
        // Given an initialized MPDPlayer with a 30 track playqeue
        mpdWrapper.songTitle = "Creature Comfort"
        mpdWrapper.album = "Everything Now"
        mpdWrapper.artist = "Arcade Fire"
        mpdWrapper.queueLength = 30
        mpdWrapper.queueVersion = 5
        setupConnectionToPlayer()
        
        let waitForStatusUpdate = XCTestExpectation(description: "Wait for Status Update")
        mpdPlayer?.controller.playerStatus
            .filter({ (playerStatus) -> Bool in
                return playerStatus.playing.playPauseMode != .Paused
            })
            .drive(onNext: { playerStatus in
                waitForStatusUpdate.fulfill()
                
                // Then playing.playPauseMode = .Playing
                XCTAssert(playerStatus.playing.playPauseMode == .Playing, "playing.playingStatus expected .Playing, got \(String(describing: playerStatus.playing.playPauseMode))")
            })
            .disposed(by: bag)
        
        // When giving a play command
        mpdPlayer?.controller.play(index: 3)
        
        // Then wait for a status update
        wait(for: [waitForStatusUpdate], timeout: 0.5)
        
        // Then mpd_run_pause is called with mode = true
        mpdWrapper.assertCall("run_play_pos")
}
    
    func testPauseSentToMPD() {
        // Given an initialized MPDPlayer that is playing
        mpdWrapper.state = MPD_STATE_PLAY
        setupConnectionToPlayer()
        
        let waitForStatusUpdate = XCTestExpectation(description: "Wait for Status Update")
        mpdPlayer?.controller.playerStatus
            .filter({ (playerStatus) -> Bool in
                return playerStatus.playing.playPauseMode != .Playing
            })
            .drive(onNext: { playerStatus in
                waitForStatusUpdate.fulfill()
                
                // Then playing.playPauseMode = .Playing
                XCTAssert(playerStatus.playing.playPauseMode == .Paused, "playing.playingStatus expected .Paused, got \(String(describing: playerStatus.playing.playPauseMode))")
            })
            .disposed(by: bag)
        
        // When giving a pause command
        mpdPlayer?.controller.pause()
        
        // Then wait for a status update
        wait(for: [waitForStatusUpdate], timeout: 0.5)
        
        // Then mpd_run_pause is called with mode = true
        mpdWrapper.assertCall("run_pause", expectedParameters: ["mode": "\(true)"])
    }
    
    func testTogglePauseSentToMPD() {
        // Given an initialized MPDPlayer
        setupConnectionToPlayer()
        
        let waitForStatusUpdate = XCTestExpectation(description: "Wait for Status Update")
        mpdPlayer?.controller.playerStatus
            .filter({ (playerStatus) -> Bool in
                return playerStatus.playing.playPauseMode != .Paused
            })
            .drive(onNext: { playerStatus in
                waitForStatusUpdate.fulfill()
                
                // Then playing.playPauseMode = .Playing
                XCTAssert(playerStatus.playing.playPauseMode == .Playing, "playing.playingStatus expected .Playing, got \(String(describing: playerStatus.playing.playPauseMode))")
            })
            .disposed(by: bag)
        
        // When giving a pause command
        mpdPlayer?.controller.togglePlayPause()

        // Then wait for a status update
        wait(for: [waitForStatusUpdate], timeout: 0.5)
        
        // Then mpd_run_pause is called with mode = true
        mpdWrapper.assertCall("run_toggle_pause")
    }
    
    func testSkipSentToMPD() {
        // Given an initialized MPDPlayer
        mpdWrapper.queueLength = 30
        mpdWrapper.queueVersion = 5
        mpdWrapper.songIndex = 2
        setupConnectionToPlayer()
        
        let waitForStatusUpdate = XCTestExpectation(description: "Wait for Status Update")
        mpdPlayer?.controller.playerStatus
            .filter({ (playerStatus) -> Bool in
                return playerStatus.playqueue.songIndex != 0 && playerStatus.playqueue.songIndex != 2
            })
            .drive(onNext: { playerStatus in
                waitForStatusUpdate.fulfill()
                
                // Then playqueue.songIndex == 3
                XCTAssert(playerStatus.playqueue.songIndex == 3, "playqueue.songIndex expected 3, got \(String(describing: playerStatus.playqueue.songIndex))")
            })
            .disposed(by: bag)
        
        // When giving a pause command
        mpdPlayer?.controller.skip()
        
        // Then wait for a status update
        wait(for: [waitForStatusUpdate], timeout: 0.5)
        
        // Then mpd_run_pause is called with mode = true
        mpdWrapper.assertCall("run_next")
    }
    
    func testBackSentToMPD() {
        // Given an initialized MPDPlayer
        mpdWrapper.queueLength = 30
        mpdWrapper.queueVersion = 5
        mpdWrapper.songIndex = 2
        setupConnectionToPlayer()
        
        let waitForStatusUpdate = XCTestExpectation(description: "Wait for Status Update")
        mpdPlayer?.controller.playerStatus
            .filter({ (playerStatus) -> Bool in
                return playerStatus.playqueue.songIndex != 0 && playerStatus.playqueue.songIndex != 2
            })
            .drive(onNext: { playerStatus in
                waitForStatusUpdate.fulfill()
                
                // Then playqueue.songIndex == 1
                XCTAssert(playerStatus.playqueue.songIndex == 1, "playqueue.songIndex expected 1, got \(String(describing: playerStatus.playqueue.songIndex))")
            })
            .disposed(by: bag)
        
        // When giving a pause command
        mpdPlayer?.controller.back()
        
        // Then wait for a status update
        wait(for: [waitForStatusUpdate], timeout: 0.5)
        
        // Then mpd_run_pause is called with mode = true
        mpdWrapper.assertCall("run_previous")
    }
    
    func testRepeatOffSentToMPD() {
        // Given an initialized MPDPlayer
        mpdWrapper.repeatValue = true
        mpdWrapper.singleValue = false
        setupConnectionToPlayer()
        
        let waitForStatusUpdate = XCTestExpectation(description: "Wait for Status Update")
        mpdPlayer?.controller.playerStatus
            .filter({ (playerStatus) -> Bool in
                return playerStatus.playing.repeatMode != .All
            })
            .drive(onNext: { playerStatus in
                waitForStatusUpdate.fulfill()
                
                // Then playing.repeatMode == .Off
                XCTAssert(playerStatus.playing.repeatMode == .Off, "playing.repeatMode expected .Off, got \(String(describing: playerStatus.playing.repeatMode))")
            })
            .disposed(by: bag)
        
        // When giving a repeat:off command
        mpdPlayer?.controller.setRepeat(repeatMode: .Off)
        
        // Then wait for a status update
        wait(for: [waitForStatusUpdate], timeout: 0.5)
        
        // Then mpd_run_pause is called with mode = true
        mpdWrapper.assertCall("run_repeat", expectedParameters: ["mode": "\(false)"])
        mpdWrapper.assertCall("run_single", expectedParameters: ["mode": "\(false)"])
    }
    
    func testRepeatSingleSentToMPD() {
        // Given an initialized MPDPlayer
        mpdWrapper.repeatValue = false
        mpdWrapper.singleValue = false
        setupConnectionToPlayer()
        
        let waitForStatusUpdate = XCTestExpectation(description: "Wait for Status Update")
        mpdPlayer?.controller.playerStatus
            .filter({ (playerStatus) -> Bool in
                return playerStatus.playing.repeatMode != .Off
            })
            .drive(onNext: { playerStatus in
                waitForStatusUpdate.fulfill()
                
                // Then playing.repeatMode == .Single
                XCTAssert(playerStatus.playing.repeatMode == .Single, "playing.repeatMode expected .Single, got \(String(describing: playerStatus.playing.repeatMode))")
            })
            .disposed(by: bag)
        
        // When giving a repeat:single command
        mpdPlayer?.controller.setRepeat(repeatMode: .Single)
        
        // Then wait for a status update
        wait(for: [waitForStatusUpdate], timeout: 0.5)
        
        // Then mpd_run_pause is called with mode = true
        mpdWrapper.assertCall("run_repeat", expectedParameters: ["mode": "\(true)"])
        mpdWrapper.assertCall("run_single", expectedParameters: ["mode": "\(true)"])
    }
    
    func testRepeatAllSentToMPD() {
        // Given an initialized MPDPlayer
        mpdWrapper.repeatValue = false
        mpdWrapper.singleValue = false
        setupConnectionToPlayer()
        
        let waitForStatusUpdate = XCTestExpectation(description: "Wait for Status Update")
        mpdPlayer?.controller.playerStatus
            .filter({ (playerStatus) -> Bool in
                return playerStatus.playing.repeatMode != .Off
            })
            .drive(onNext: { playerStatus in
                waitForStatusUpdate.fulfill()
                
                // Then playing.repeatMode == .All
                XCTAssert(playerStatus.playing.repeatMode == .All, "playing.repeatMode expected .All, got \(String(describing: playerStatus.playing.repeatMode))")
            })
            .disposed(by: bag)
        
        // When giving a repeat:all command
        mpdPlayer?.controller.setRepeat(repeatMode: .All)
        
        // Then wait for a status update
        wait(for: [waitForStatusUpdate], timeout: 0.5)
        
        // Then mpd_run_pause is called with mode = true
        mpdWrapper.assertCall("run_repeat", expectedParameters: ["mode": "\(true)"])
    }
    
    func testRepeatAlbumSentToMPD() {
        // Given an initialized MPDPlayer
        mpdWrapper.repeatValue = false
        mpdWrapper.singleValue = false
        setupConnectionToPlayer()
        
        let waitForStatusUpdate = XCTestExpectation(description: "Wait for Status Update")
        mpdPlayer?.controller.playerStatus
            .filter({ (playerStatus) -> Bool in
                return playerStatus.playing.repeatMode != .Off
            })
            .drive(onNext: { playerStatus in
                waitForStatusUpdate.fulfill()
                
                // Then playing.repeatMode == .Allg
                XCTAssert(playerStatus.playing.repeatMode == .All, "playing.repeatMode expected .All, got \(String(describing: playerStatus.playing.repeatMode))")
            })
            .disposed(by: bag)
        
        // When giving a repeat:album command
        mpdPlayer?.controller.setRepeat(repeatMode: .Album)
        
        // Then wait for a status update
        wait(for: [waitForStatusUpdate], timeout: 0.5)
        
        // Then mpd_run_pause is called with mode = true
        mpdWrapper.assertCall("run_repeat", expectedParameters: ["mode": "\(true)"])
    }
    
    func testRepeatToggleSentToMPD() {
        // Given an initialized MPDPlayer
        mpdWrapper.repeatValue = false
        mpdWrapper.singleValue = false
        setupConnectionToPlayer()
        
        var waitForStatusUpdate = XCTestExpectation(description: "Wait for Status Update")
        mpdPlayer?.controller.playerStatus
            .filter({ (playerStatus) -> Bool in
                return playerStatus.playing.repeatMode == .All
            })
            .drive(onNext: { playerStatus in
                waitForStatusUpdate.fulfill()
                
                // Then playing.repeatMode == .Allg
                XCTAssert(playerStatus.playing.repeatMode == .All, "playing.repeatMode expected .All, got \(String(describing: playerStatus.playing.repeatMode))")
            })
            .disposed(by: bag)
        
        // When giving a repeat:album command
        mpdPlayer?.controller.toggleRepeat()
        
        // Then wait for a status update
        wait(for: [waitForStatusUpdate], timeout: 0.5)
        
        // Then mpd_run_pause is called with mode = true
        mpdWrapper.assertCall("run_repeat", expectedParameters: ["mode": "\(true)"])
        mpdWrapper.assertCall("run_single", expectedParameters: ["mode": "\(false)"])

        mpdWrapper.clearAllCalls()
        waitForStatusUpdate = XCTestExpectation(description: "Wait for Status Update")
        mpdPlayer?.controller.playerStatus
            .filter({ (playerStatus) -> Bool in
                return playerStatus.playing.repeatMode == .Single
            })
            .drive(onNext: { playerStatus in
                waitForStatusUpdate.fulfill()
                
                // Then playing.repeatMode == .Allg
                XCTAssert(playerStatus.playing.repeatMode == .Single, "playing.repeatMode expected .Single, got \(String(describing: playerStatus.playing.repeatMode))")
            })
            .disposed(by: bag)
        
        // When giving a repeat:album command
        mpdPlayer?.controller.toggleRepeat()
        
        // Then wait for a status update
        wait(for: [waitForStatusUpdate], timeout: 0.5)
        
        // Then mpd_run_pause is called with mode = true
        mpdWrapper.assertCall("run_repeat", expectedParameters: ["mode": "\(true)"])
        mpdWrapper.assertCall("run_single", expectedParameters: ["mode": "\(true)"])

        mpdWrapper.clearAllCalls()
        waitForStatusUpdate = XCTestExpectation(description: "Wait for Status Update")
        mpdPlayer?.controller.playerStatus
            .filter({ (playerStatus) -> Bool in
                return playerStatus.playing.repeatMode == .Off
            })
            .drive(onNext: { playerStatus in
                waitForStatusUpdate.fulfill()
                
                // Then playing.repeatMode == .Allg
                XCTAssert(playerStatus.playing.repeatMode == .Off, "playing.repeatMode expected .Off, got \(String(describing: playerStatus.playing.repeatMode))")
            })
            .disposed(by: bag)
        
        // When giving a repeat:album command
        mpdPlayer?.controller.toggleRepeat()
        
        // Then wait for a status update
        wait(for: [waitForStatusUpdate], timeout: 0.5)
        
        // Then mpd_run_pause is called with mode = true
        mpdWrapper.assertCall("run_repeat", expectedParameters: ["mode": "\(false)"])
        mpdWrapper.assertCall("run_single", expectedParameters: ["mode": "\(false)"])
    }
    
    func testRandomOnOffSentToMPD() {
        // Given an initialized MPDPlayer
        mpdWrapper.random = false
        setupConnectionToPlayer()
        
        var waitForStatusUpdate = XCTestExpectation(description: "Wait for Status Update")
        mpdPlayer?.controller.playerStatus
            .filter({ (playerStatus) -> Bool in
                return playerStatus.playing.randomMode != .Off
            })
            .drive(onNext: { playerStatus in
                waitForStatusUpdate.fulfill()
                
                // Then playing.randomMode == .On
                XCTAssert(playerStatus.playing.randomMode == .On, "playing.randomMode expected .On, got \(String(describing: playerStatus.playing.randomMode))")
            })
            .disposed(by: bag)
        
        // When giving a shuffle:on command
        mpdPlayer?.controller.setRandom(randomMode: .On)
        
        // Then wait for a status update
        wait(for: [waitForStatusUpdate], timeout: 0.5)
        
        // Then mpd_run_pause is called with mode = true
        mpdWrapper.assertCall("run_random", expectedParameters: ["mode": "\(true)"])
        
        mpdWrapper.clearAllCalls()
        waitForStatusUpdate = XCTestExpectation(description: "Wait for Status Update")
        mpdPlayer?.controller.playerStatus
            .filter({ (playerStatus) -> Bool in
                return playerStatus.playing.randomMode != .On
            })
            .drive(onNext: { playerStatus in
                waitForStatusUpdate.fulfill()
                
                // Then playing.randomMode == .Off,
                XCTAssert(playerStatus.playing.randomMode == .Off, "playing.randomMode expected .Off, got \(String(describing: playerStatus.playing.randomMode))")
            })
            .disposed(by: bag)
        
        // When giving a shuffle:off command
        mpdPlayer?.controller.setRandom(randomMode: .Off)
        
        // Then wait for a status update
        wait(for: [waitForStatusUpdate], timeout: 0.5)

        // Then mpd_run_random is called with mode = true
        mpdWrapper.assertCall("run_random", expectedParameters: ["mode": "\(false)"])
    }
 
    func testToggleRandomSentToMPD() {
        // Given an initialized MPDPlayer
        mpdWrapper.random = false
        setupConnectionToPlayer()
        
        var waitForStatusUpdate = XCTestExpectation(description: "Wait for Status Update")
        mpdPlayer?.controller.playerStatus
            .filter({ (playerStatus) -> Bool in
                return playerStatus.playing.randomMode == .On
            })
            .drive(onNext: { playerStatus in
                waitForStatusUpdate.fulfill()
                
                // Then playing.randomMode == .On
                XCTAssert(playerStatus.playing.randomMode == .On, "playing.randomMode expected .On, got \(String(describing: playerStatus.playing.randomMode))")
            })
            .disposed(by: bag)
        
        // When giving a shuffle:on command
        mpdPlayer?.controller.toggleRandom()
        
        // Then wait for a status update
        wait(for: [waitForStatusUpdate], timeout: 0.5)
        
        // Then mpd_run_pause is called with mode = true
        mpdWrapper.assertCall("run_random", expectedParameters: ["mode": "\(true)"])
        
        mpdWrapper.clearAllCalls()
        waitForStatusUpdate = XCTestExpectation(description: "Wait for Status Update")
        mpdPlayer?.controller.playerStatus
            .filter({ (playerStatus) -> Bool in
                return playerStatus.playing.randomMode == .On
            })
            .drive(onNext: { playerStatus in
                waitForStatusUpdate.fulfill()
                
                // Then playing.randomMode == .Off,
                XCTAssert(playerStatus.playing.randomMode == .On, "playing.randomMode expected .On, got \(String(describing: playerStatus.playing.randomMode))")
            })
            .disposed(by: bag)
        
        // When giving a shuffle:off command
        mpdPlayer?.controller.toggleRandom()
        
        // Then wait for a status update
        wait(for: [waitForStatusUpdate], timeout: 0.5)
        
        // Then mpd_run_random is called with mode = true
        mpdWrapper.assertCall("run_random", expectedParameters: ["mode": "\(false)"])
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
        
        let waitForStatusUpdate = XCTestExpectation(description: "Wait for Status Update")
        mpdPlayer?.controller.playerStatus
            .filter({ (playerStatus) -> Bool in
                return playerStatus.currentSong.title == "Creature Comfort"
            })
            .drive(onNext: { playerStatus in
                waitForStatusUpdate.fulfill()

                // Then currentSong.song = "Creature Comfort"
                XCTAssert(playerStatus.currentSong.title == "Creature Comfort", "currentSong.title expected 'Creature Comfort', got \(String(describing: playerStatus.currentSong.title))")

                // Then currentSong.album = "Everything Now"
                XCTAssert(playerStatus.currentSong.album == "Everything Now", "currentSong.album expected 'Everything Now', got \(String(describing: playerStatus.currentSong.album))")
                
                // Then currentSong.artist = "Arcade Fire"
                XCTAssert(playerStatus.currentSong.artist == "Arcade Fire", "currentSong.artist expected 'Arcade Fire', got \(String(describing: playerStatus.currentSong.artist))")
            })
            .disposed(by: bag)

        mpdPlayer?.controller.playerStatus
            .filter({ (playerStatus) -> Bool in
                return playerStatus.time.elapsedTime != 0
            })
            .drive(onNext: { playerStatus in
                waitForStatusUpdate.fulfill()
                
                // Then time.elapsedTime = 20
                XCTAssert(playerStatus.time.elapsedTime == 20, "time.elapsedTime expected 20, got \(String(describing: playerStatus.time.elapsedTime))")
                
                // Then time.trackTime = 30
                XCTAssert(playerStatus.time.trackTime == 30, "time.trackTime expected 30, got \(String(describing: playerStatus.time.trackTime))")
            })
            .disposed(by: bag)

        mpdPlayer?.controller.playerStatus
            .filter({ (playerStatus) -> Bool in
                return playerStatus.playing.playPauseMode != .Paused
            })
            .drive(onNext: { playerStatus in
                waitForStatusUpdate.fulfill()
                
                // Then playing.repeatMode = .All
                XCTAssert(playerStatus.playing.repeatMode == .All, "playing.artist expected .All, got \(String(describing: playerStatus.playing.repeatMode))")
                
                // Then playing.randomMode = .On
                XCTAssert(playerStatus.playing.randomMode == .On, "playing.artist expected .On, got \(String(describing: playerStatus.playing.randomMode))")
                
                // Then playing.playingStatus = .Playing
                XCTAssert(playerStatus.playing.playPauseMode == .Playing, "playing.playingStatus expected .Playing, got \(String(describing: playerStatus.playing.playPauseMode))")
            })
            .disposed(by: bag)

        mpdPlayer?.controller.playerStatus
            .filter({ (playerStatus) -> Bool in
                return playerStatus.volume != 0.0
            })
            .drive(onNext: { playerStatus in
                waitForStatusUpdate.fulfill()
                
                // Then volume = 0.1
                XCTAssert(playerStatus.volume == 0.1, "volume expected 0.1, got \(String(describing: playerStatus.volume))")
            })
            .disposed(by: bag)

        // Then wait for 1.0 seconds and check if run_status is called
        wait(for: [waitForStatusUpdate], timeout: 1.0)
        
        // Then mpd_run_status/mpd_status_free are called.
        mpdWrapper.assertCall("run_status")
        mpdWrapper.assertCall("status_free")
        
        // Then mpd_run_current_song/mpd_song_free are called.
        mpdWrapper.assertCall("run_current_song")
        mpdWrapper.assertCall("song_free")
    }
 
    func testFetchPlayqueue() {
        // Given an initialized MPDPlayer
        mpdWrapper.songTitle = "Creature Comfort"
        mpdWrapper.album = "Everything Now"
        mpdWrapper.artist = "Arcade Fire"
        mpdWrapper.queueLength = 30
        mpdWrapper.queueVersion = 5
        mpdWrapper.availableSongs = 5
        setupConnectionToPlayer()

        // When asking for 5 songs
        var songs = mpdPlayer!.controller.getPlayqueueSongs(start: 3, end: 8)

        // Then 5 songs are returned
        XCTAssert(songs.count == 5, "songs.count expected 6, got \(songs.count)")
        XCTAssert(songs[0].title == "Creature Comfort", "song.title expected 'Creature Comfort', got \(String(describing: songs[0].title))")
        XCTAssert(songs[0].album == "Everything Now", "song.album expected 'Everything Now', got \(String(describing: songs[0].album))")
        XCTAssert(songs[0].artist == "Arcade Fire", "song.artist expected 'Arcade Fire', got \(String(describing: songs[0].artist))")
        XCTAssert(songs[0].position == 3, "song.position expected 3, got \(songs[0].position)")
        XCTAssert(songs[4].position == 7, "song.position expected 8, got \(songs[4].position)")
        
        // When asking for 5 songs but only 3 are available
        mpdWrapper.availableSongs = 3
        songs = mpdPlayer!.controller.getPlayqueueSongs(start: 28, end: 32)

        // Then 3 songs are returned
        XCTAssert(songs.count == 3, "songs.count expected 3, got \(songs.count)")
        XCTAssert(songs[0].title == "Creature Comfort", "song.title expected 'Creature Comfort', got \(String(describing: songs[0].title))")
        XCTAssert(songs[0].album == "Everything Now", "song.album expected 'Everything Now', got \(String(describing: songs[0].album))")
        XCTAssert(songs[0].artist == "Arcade Fire", "song.artist expected 'Arcade Fire', got \(String(describing: songs[0].artist))")
        XCTAssert(songs[0].position == 28, "song.position expected 28, got \(songs[0].position)")
        XCTAssert(songs[2].position == 30, "song.position expected 30, got \(songs[2].position)")
    }

}
