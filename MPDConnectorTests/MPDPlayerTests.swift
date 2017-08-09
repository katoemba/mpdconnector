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
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.

        mpdWrapper = MPDWrapperMock()
        mpdPlayer = MPDPlayer.init(mpd: mpdWrapper)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()

        if let player = self.mpdPlayer {
            player.stopListeningForStatusUpdates()
            self.mpdPlayer = nil
        }
    }
    
    func testMPDPlayerInitializationAndCleanup() {
        // Given nothing
        
        // When creating a new MPDPlayer object (done during setup)
        
        // Then a new connection to an mpd server is created
        var callCount = 0
        if let callInfos = mpdWrapper.calls["connection_new"] {
            callCount = callInfos.count
        }
        XCTAssert(callCount == 1, "connection_new not called once")
        
        // Given an existing MPDPlayer object (created during setup)
        
        // When cleaning up the connection
        let waitExpectation = expectation(description: "Waiting for cleanup")
        let operation = BlockOperation(block: {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let callInfos = self.mpdWrapper.calls["connection_free"] {
                    if callInfos.count == 1 {
                        waitExpectation.fulfill()
                    }
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

    func testSetValidVolumeSentToMPD() {
        // Given an initialized MPDPlayer
        
        // When setting the volume to 0.6
        mpdPlayer?.setVolume(volume: 0.6)
        
        // Then mpd_run_set_volume is called with value 60
        var callCount = 0
        var callValue = -1
        if let callInfos = mpdWrapper.calls["run_set_volume"] {
            callCount = callInfos.count
            callValue = Int(callInfos[0]["volume"] as! UInt32)
        }
        XCTAssert(callCount == 1, "run_set_volume not called once")
        XCTAssert(callValue == 60, "Incorrect volume sent to run_set_volume")
    }

    func testSetInvalidVolumeNotSentToMPD() {
        // Given an initialized MPDPlayer
        
        // When setting the volume to -10.0
        mpdPlayer?.setVolume(volume: -10.0)
        
        // Then this is not passed to mpd
        var callCount = 0
        if let callInfos = mpdWrapper.calls["run_set_volume"] {
            callCount = callInfos.count
        }
        XCTAssert(callCount == 0, "run_set_volume should not be called with invalid input")

        // Given an initialized MPDPlayer
        
        // When setting the volume to 1.1
        mpdPlayer?.setVolume(volume: 1.1)
        
        // Then this is not passed to mpd
        callCount = 0
        if let callInfos = mpdWrapper.calls["run_set_volume"] {
            callCount = callInfos.count
        }
        XCTAssert(callCount == 0, "run_set_volume should not be called with invalid input")
    }
    
    func testPlaySentToMPD() {
        // Given an initialized MPDPlayer
        
        // When giving a play command
        mpdPlayer?.play()
        
        // Then mpd_run_play is called
        var callCount = 0
        if let callInfos = mpdWrapper.calls["run_play"] {
            callCount = callInfos.count
        }
        XCTAssert(callCount == 1, "run_play not called once")
    }
    
    func testPauseSentToMPD() {
        // Given an initialized MPDPlayer
        
        // When giving a pause command
        mpdPlayer?.pause()
        
        // Then mpd_run_pause is called with mode = true
        var callCount = 0
        var callValue = false
        if let callInfos = mpdWrapper.calls["run_pause"] {
            callCount = callInfos.count
            callValue = callInfos[0]["mode"] as! Bool
        }
        XCTAssert(callCount == 1, "run_pause not called once")
        XCTAssert(callValue == true, "Invalid mode sent to run_pause")
    }

    func testSkipSentToMPD() {
        // Given an initialized MPDPlayer
        
        // When giving a skip command
        mpdPlayer?.skip()
        
        // Then mpd_run_next is called
        var callCount = 0
        if let callInfos = mpdWrapper.calls["run_next"] {
            callCount = callInfos.count
        }
        XCTAssert(callCount == 1, "run_next not called once")
    }
    
    func testBackSentToMPD() {
        // Given an initialized MPDPlayer
        
        // When giving a back command
        mpdPlayer?.back()
        
        // Then mpd_run_next is called
        var callCount = 0
        if let callInfos = mpdWrapper.calls["run_previous"] {
            callCount = callInfos.count
        }
        XCTAssert(callCount == 1, "run_previous not called once")
    }
    
    func testRepeatOffSentToMPD() {
        // Given an initialized MPDPlayer
        
        // When giving a repeat:off command
        mpdPlayer?.setRepeat(repeatMode: .Off)
        
        // Then mpd_run_repeat is called with mode: false
        var callCount = 0
        var callValue = false
        if let callInfos = mpdWrapper.calls["run_repeat"] {
            callCount = callInfos.count
            callValue = callInfos[0]["mode"] as! Bool
        }
        XCTAssert(callCount == 1, "run_repeat not called once")
        XCTAssert(callValue == false, "Invalid mode sent to run_repeat")
    }

    func testRepeatSingleSentToMPD() {
        // Given an initialized MPDPlayer
        
        // When giving a repeat:single command
        mpdPlayer?.setRepeat(repeatMode: .Single)
        
        // Then mpd_run_repeat is called with mode: true
        var callCount = 0
        var callValue = false
        if let callInfos = mpdWrapper.calls["run_repeat"] {
            callCount = callInfos.count
            callValue = callInfos[0]["mode"] as! Bool
        }
        XCTAssert(callCount == 1, "run_repeat not called once")
        XCTAssert(callValue == true, "Invalid mode sent to run_repeat")
    }

    func testRepeatAllSentToMPD() {
        // Given an initialized MPDPlayer
        
        // When giving a repeat:all command
        mpdPlayer?.setRepeat(repeatMode: .All)
        
        // Then mpd_run_repeat is called with mode: true
        var callCount = 0
        var callValue = false
        if let callInfos = mpdWrapper.calls["run_repeat"] {
            callCount = callInfos.count
            callValue = callInfos[0]["mode"] as! Bool
        }
        XCTAssert(callCount == 1, "run_repeat not called once")
        XCTAssert(callValue == true, "Invalid mode sent to run_repeat")
    }

    func testRepeatAlbumSentToMPD() {
        // Given an initialized MPDPlayer
        
        // When giving a repeat:album command
        mpdPlayer?.setRepeat(repeatMode: .Album)
        
        // Then mpd_run_repeat is called with mode: true
        var callCount = 0
        var callValue = false
        if let callInfos = mpdWrapper.calls["run_repeat"] {
            callCount = callInfos.count
            callValue = callInfos[0]["mode"] as! Bool
        }
        XCTAssert(callCount == 1, "run_repeat not called once")
        XCTAssert(callValue == true, "Invalid mode sent to run_repeat")
    }
    
    func testShuffleOffSentToMPD() {
        // Given an initialized MPDPlayer
        
        // When giving a repeat:off command
        mpdPlayer?.setShuffle(shuffleMode: .Off)
        
        // Then mpd_run_random is called with mode: false
        var callCount = 0
        var callValue = false
        if let callInfos = mpdWrapper.calls["run_random"] {
            callCount = callInfos.count
            callValue = callInfos[0]["mode"] as! Bool
        }
        XCTAssert(callCount == 1, "run_random not called once")
        XCTAssert(callValue == false, "Invalid mode sent to run_random")
    }
    
    func testShuffleOnSentToMPD() {
        // Given an initialized MPDPlayer
        
        // When giving a repeat:single command
        mpdPlayer?.setShuffle(shuffleMode: .On)
        
        // Then mpd_run_random is called with mode: true
        var callCount = 0
        var callValue = false
        if let callInfos = mpdWrapper.calls["run_random"] {
            callCount = callInfos.count
            callValue = callInfos[0]["mode"] as! Bool
        }
        XCTAssert(callCount == 1, "run_random not called once")
        XCTAssert(callValue == true, "Invalid mode sent to run_random")
    }
    
    func testFetchStatus() {
        // Given an initialized MPDPlayer
        mpdWrapper.clearAllCalls()
        mpdWrapper.volume = 10
        mpdWrapper.elapsedTime = 20
        mpdWrapper.trackTime = 30
        mpdWrapper.songTitle = "Creature Comfort"
        mpdWrapper.album = "Everything Now"
        mpdWrapper.artist = "Arcade Fire"
        mpdWrapper.repeatValue = true
        mpdWrapper.random = true
        mpdWrapper.state = MPD_STATE_PLAY
        
        // When giving a fetchStatus command
        mpdPlayer?.fetchStatus()
        
        // Then mpd_run_status/mpd_status_free are called.
        var callRunStatusCount = 0
        var callStatusFreeCount = 0
        if let callInfos = mpdWrapper.calls["run_status"] {
            callRunStatusCount = callInfos.count
        }
        if let callInfos = mpdWrapper.calls["status_free"] {
            callStatusFreeCount = callInfos.count
        }
        XCTAssert(callRunStatusCount == 1, "run_status not called once")
        XCTAssert(callStatusFreeCount == 1, "status_free not called once")

        // Then mpd_run_current_song/mpd_song_free are called.
        var callRunCurrentSongCount = 0
        var callSongFreeCount = 0
        if let callInfos = mpdWrapper.calls["run_current_song"] {
            callRunCurrentSongCount = callInfos.count
        }
        if let callInfos = mpdWrapper.calls["song_free"] {
            callSongFreeCount = callInfos.count
        }
        XCTAssert(callRunCurrentSongCount == 1, "run_current_song not called once")
        XCTAssert(callSongFreeCount == 1, "song_free not called once")
        
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
