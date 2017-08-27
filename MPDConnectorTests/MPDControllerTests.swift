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

class MPDControllerTests: XCTestCase {
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
            player.controller.stopListeningForStatusUpdates()
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
    
    func testCommandsWhenNotConnected() {
        // Given an initialized but not connected MPDPlayer
        mpdPlayer = MPDPlayer.init(mpd: mpdWrapper, host: "localhost", port: 6600,
                                   connectedHandler: { (mpdPlayer) in
                                    self.mpdConnectedExpectation?.fulfill()
        },
                                   disconnectedHandler: { (mpdPlayer, errorNumber, errorMessage) in
        })
        
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
        mpdPlayer?.controller.setShuffle(shuffleMode: .Off)
        
        // Then wait for 0.2 seconds and check if run_random is called
        waitForCallExpectation = waitForCall("run_random", expectedCalls: 0, waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
        
        // When giving a fetchStatus command
        mpdPlayer?.controller.fetchStatus()
        
        // Then wait for 0.2 seconds and check if run_status is called
        waitForCallExpectation = waitForCall("run_status", expectedCalls: 0, waitTime: 0.2)
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
        
        // When giving a play command
        mpdPlayer?.controller.play()
        
        // Then wait for 0.2 seconds and check if run_play is called
        let waitForCallExpectation = waitForCall("run_play", waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
        
        // Then mpd_run_play is called
        mpdWrapper.assertCall("run_play")
        
        // Then mpd_run_status/mpd_status_free are called.
        mpdWrapper.assertCall("run_status")
        mpdWrapper.assertCall("status_free")
    }
    
    func testPlayWithIndexSentToMPD() {
        // Given an initialized MPDPlayer with a 30 track playqeue
        mpdWrapper.songTitle = "Creature Comfort"
        mpdWrapper.album = "Everything Now"
        mpdWrapper.artist = "Arcade Fire"
        mpdWrapper.queueLength = 30
        mpdWrapper.queueVersion = 5
        setupConnectionToPlayer()
        mpdPlayer?.controller.fetchStatus()
        
        // Then wait for 0.2 seconds and check if run_status is called
        var waitForCallExpectation = waitForCall("run_status", waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
        mpdWrapper.clearAllCalls()
        
        // When giving a play command
        mpdPlayer?.controller.play(index: 3)
        
        // Then wait for 0.2 seconds and check if run_play is called
        waitForCallExpectation = waitForCall("run_play_pos", waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
        
        // Then mpd_run_play is called
        mpdWrapper.assertCall("run_play_pos")
        
        // Then mpd_run_status/mpd_status_free are called.
        mpdWrapper.assertCall("run_status")
        mpdWrapper.assertCall("status_free")
    }
    
    func testPauseSentToMPD() {
        // Given an initialized MPDPlayer
        setupConnectionToPlayer()
        
        // When giving a pause command
        mpdPlayer?.controller.pause()
        
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
        mpdPlayer?.controller.togglePlayPause()
        
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
        mpdPlayer?.controller.skip()
        
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
        mpdPlayer?.controller.back()
        
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
        mpdPlayer?.controller.setRepeat(repeatMode: .Off)
        
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
        mpdPlayer?.controller.setRepeat(repeatMode: .Single)
        
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
        mpdPlayer?.controller.setRepeat(repeatMode: .All)
        
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
        mpdPlayer?.controller.setRepeat(repeatMode: .Album)
        
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
        mpdPlayer?.controller.setShuffle(shuffleMode: .Off)
        
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
        mpdPlayer?.controller.setShuffle(shuffleMode: .On)
        
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
        mpdPlayer?.controller.fetchStatus()
        
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
        XCTAssert(mpdPlayer?.controller.playerStatus.volume == 0.1, "playerStatus.volume expected 0.1, got \(String(describing: mpdPlayer?.controller.playerStatus.volume))")
        
        // Then playerStatus.elapsedTime = 20
        XCTAssert(mpdPlayer?.controller.playerStatus.elapsedTime == 20, "playerStatus.elapsedTime expected 10, got \(String(describing: mpdPlayer?.controller.playerStatus.elapsedTime))")
        
        // Then playerStatus.trackTime = 30
        XCTAssert(mpdPlayer?.controller.playerStatus.trackTime == 30, "playerStatus.trackTime expected 20, got \(String(describing: mpdPlayer?.controller.playerStatus.trackTime))")
        
        // Then playerStatus.song = "Creature Comfort"
        XCTAssert(mpdPlayer?.controller.playerStatus.song == "Creature Comfort", "playerStatus.songTitle expected 'Creature Comfort', got \(String(describing: mpdPlayer?.controller.playerStatus.song))")
        
        // Then playerStatus.album = "Everything Now"
        XCTAssert(mpdPlayer?.controller.playerStatus.album == "Everything Now", "playerStatus.album expected 'Everything Now', got \(String(describing: mpdPlayer?.controller.playerStatus.album))")
        
        // Then playerStatus.artist = "Arcade Fire"
        XCTAssert(mpdPlayer?.controller.playerStatus.artist == "Arcade Fire", "playerStatus.artist expected 'Arcade Fire', got \(String(describing: mpdPlayer?.controller.playerStatus.artist))")
        
        // Then playerStatus.repeatMode = .All
        XCTAssert(mpdPlayer?.controller.playerStatus.repeatMode == .All, "playerStatus.artist expected .All, got \(String(describing: mpdPlayer?.controller.playerStatus.repeatMode))")
        
        // Then playerStatus.shuffleMode = .On
        XCTAssert(mpdPlayer?.controller.playerStatus.shuffleMode == .On, "playerStatus.artist expected .On, got \(String(describing: mpdPlayer?.controller.playerStatus.shuffleMode))")
        
        // Then playerStatus.playingStatus = .Playing
        XCTAssert(mpdPlayer?.controller.playerStatus.playingStatus == .Playing, "playerStatus.playingStatus expected .Playing, got \(String(describing: mpdPlayer?.controller.playerStatus.playingStatus))")
    }
    
    func testFetchPlayqueue() {
        // Given an initialized MPDPlayer
        mpdWrapper.songTitle = "Creature Comfort"
        mpdWrapper.album = "Everything Now"
        mpdWrapper.artist = "Arcade Fire"
        mpdWrapper.queueLength = 30
        mpdWrapper.queueVersion = 5
        setupConnectionToPlayer()
        
        // When giving a fetchStatus command
        mpdPlayer?.controller.fetchStatus()
        
        // Then wait for 0.2 seconds and check if run_status is called
        var waitForCallExpectation = waitForCall("run_status", waitTime: 0.2)
        wait(for: [waitForCallExpectation], timeout: 0.3)
        
        // Then mpd_run_status/mpd_status_free are called.
        mpdWrapper.assertCall("run_status")
        mpdWrapper.assertCall("status_free")
        
        // Then playerStatus.playqueueLength = 30
        XCTAssert(mpdPlayer?.controller.playqueueLength == 30, "player.playqueueLength expected 30, got \(String(describing: mpdPlayer?.controller.playqueueLength))")
        
        // Then playerStatus.playqueueVersion = 5
        XCTAssert(mpdPlayer?.controller.playqueueVersion == 5, "player.playqueueVersion expected 5, got \(String(describing: mpdPlayer?.controller.playqueueVersion))")
        
        // When fetching the song at index 0
        mpdWrapper.availableSongs = 5
        waitForCallExpectation = expectation(description: "Songs Found")
        mpdPlayer?.controller.getPlayqueueSongs(start: 3, end: 8,
                                     songsFound: { (songs) in
                                        XCTAssert(songs.count == 5, "songs.count expected 5, got \(songs.count)")
                                        XCTAssert(songs[0].title == "Creature Comfort", "playerStatus.songTitle expected 'Creature Comfort', got \(String(describing: songs[0].title))")
                                        XCTAssert(songs[0].album == "Everything Now", "playerStatus.album expected 'Everything Now', got \(String(describing: songs[0].album))")
                                        XCTAssert(songs[0].artist == "Arcade Fire", "playerStatus.artist expected 'Arcade Fire', got \(String(describing: songs[0].artist))")
                                        waitForCallExpectation.fulfill()
        })
        // Check that the songFound block is called
        wait(for: [waitForCallExpectation], timeout: 0.2)
    }
}
