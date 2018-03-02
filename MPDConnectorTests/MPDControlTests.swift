//
//  MPDControlTests.swift
//  MPDConnector
//
//  Created by Berrie Kremers on 26-08-17.
//  Copyright © 2017 Katoemba Software. All rights reserved.
//

import XCTest
import ConnectorProtocol
import MPDConnector
import libmpdclient
import RxSwift
import RxTest

class MPDControlTests: XCTestCase {
    var mpdWrapper = MPDWrapperMock()
    var mpdPlayer: MPDPlayer?
    var mpdConnectedExpectation: XCTestExpectation?
    let bag = DisposeBag()
    var testScheduler = TestScheduler(initialClock: 0)
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
        
        testScheduler = TestScheduler(initialClock: 0)
        mpdWrapper = MPDWrapperMock()
        mpdPlayer = MPDPlayer.init(mpd: mpdWrapper, name: "player", host: "localhost", port: 6600, password: "", scheduler: testScheduler)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
        
        if self.mpdPlayer != nil {
            self.mpdPlayer = nil
        }
    }
    
    func testSetValidVolumeSentToMPD() {
        testScheduler.scheduleAt(50) {
            self.mpdPlayer?.control.setVolume(volume: 0.6)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_set_volume", expectedParameters: ["volume": "\(60)"])
        }
        
        testScheduler.start()
    }

    func testSetInvalidVolumeNotSentToMPD() {
        testScheduler.scheduleAt(50) {
            self.mpdPlayer?.control.setVolume(volume: -10.0)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_set_volume", expectedCallCount: 0)
        }
        
        testScheduler.scheduleAt(150) {
            self.mpdWrapper.clearAllCalls()
            self.mpdPlayer?.control.setVolume(volume: 1.1)
        }
        testScheduler.scheduleAt(200) {
            self.mpdWrapper.assertCall("run_set_volume", expectedCallCount: 0)
        }
        
        testScheduler.start()
    }
    
    func testPlaySentToMPD() {
        testScheduler.scheduleAt(50) {
            self.mpdPlayer?.control.play()
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_play")
        }
        
        testScheduler.start()
    }
    
    func testPlayWithIndexSentToMPD() {
        testScheduler.scheduleAt(50) {
            self.mpdPlayer?.control.play(index: 3)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_play_pos", expectedCallCount: 1, expectedParameters: ["song_pos": "3"])
        }
        
        testScheduler.start()
    }
    
    func testPlayWithInvalidIndexNotSentToMPD() {
        testScheduler.scheduleAt(50) {
            self.mpdPlayer?.control.play(index: -1)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_play_pos", expectedCallCount: 0)
        }
        
        testScheduler.start()
    }
    
    func testPauseSentToMPD() {
        testScheduler.scheduleAt(50) {
            self.mpdPlayer?.control.pause()
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_pause", expectedParameters: ["mode": "\(true)"])
        }

        testScheduler.start()
    }

    func testTogglePauseSentToMPD() {
        testScheduler.scheduleAt(50) {
            self.mpdPlayer?.control.togglePlayPause()
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_toggle_pause")
        }
        
        testScheduler.start()
    }
    
    func testSkipSentToMPD() {
        testScheduler.scheduleAt(50) {
            self.mpdPlayer?.control.skip()
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_next")
        }
        
        testScheduler.start()
    }
    
    func testBackSentToMPD() {
        testScheduler.scheduleAt(50) {
            self.mpdPlayer?.control.back()
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_previous")
        }
        
        testScheduler.start()
    }

    func testShuffleSentToMPD() {
        testScheduler.scheduleAt(50) {
            self.mpdPlayer?.control.shufflePlayqueue()
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_shuffle", expectedParameters: [:])
        }
        
        testScheduler.start()
    }
    
    func testRepeatOffSentToMPD() {
        testScheduler.scheduleAt(50) {
            self.mpdPlayer?.control.setRepeat(repeatMode: .Off)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_repeat", expectedParameters: ["mode": "\(false)"])
            self.mpdWrapper.assertCall("run_single", expectedParameters: ["mode": "\(false)"])
        }
        
        testScheduler.start()
    }
    
    func testRepeatSingleSentToMPD() {
        testScheduler.scheduleAt(50) {
            self.mpdPlayer?.control.setRepeat(repeatMode: .Single)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_repeat", expectedParameters: ["mode": "\(true)"])
            self.mpdWrapper.assertCall("run_single", expectedParameters: ["mode": "\(true)"])
        }
        
        testScheduler.start()
    }
    
    func testRepeatAllSentToMPD() {
        testScheduler.scheduleAt(50) {
            self.mpdPlayer?.control.setRepeat(repeatMode: .All)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_repeat", expectedParameters: ["mode": "\(true)"])
            self.mpdWrapper.assertCall("run_single", expectedParameters: ["mode": "\(false)"])
        }
        
        testScheduler.start()
    }
    
    func testRepeatAlbumSentToMPD() {
        testScheduler.scheduleAt(50) {
            self.mpdPlayer?.control.setRepeat(repeatMode: .Album)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_repeat", expectedParameters: ["mode": "\(true)"])
            self.mpdWrapper.assertCall("run_single", expectedParameters: ["mode": "\(false)"])
        }
        
        testScheduler.start()
    }
    
    func testRepeatToggleSentToMPD() {
        let mpdStatus = self.mpdPlayer?.status as! MPDStatus
        var playerStatus = PlayerStatus()

        testScheduler.scheduleAt(10) {
            playerStatus.playing.repeatMode = .Off
            mpdStatus.testSetPlayerStatus(playerStatus: playerStatus)
        }
        testScheduler.scheduleAt(50) {
            self.mpdPlayer?.control.toggleRepeat()
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_repeat", expectedParameters: ["mode": "\(true)"])
            self.mpdWrapper.assertCall("run_single", expectedParameters: ["mode": "\(false)"])
        }
        testScheduler.scheduleAt(110) {
            playerStatus.playing.repeatMode = .All
            mpdStatus.testSetPlayerStatus(playerStatus: playerStatus)
        }
        testScheduler.scheduleAt(150) {
            self.mpdWrapper.clearAllCalls()
            self.mpdPlayer?.control.toggleRepeat()
        }
        testScheduler.scheduleAt(200) {
            self.mpdWrapper.assertCall("run_repeat", expectedParameters: ["mode": "\(true)"])
            self.mpdWrapper.assertCall("run_single", expectedParameters: ["mode": "\(true)"])
        }
        testScheduler.scheduleAt(210) {
            playerStatus.playing.repeatMode = .Single
            mpdStatus.testSetPlayerStatus(playerStatus: playerStatus)
        }
        testScheduler.scheduleAt(250) {
            self.mpdWrapper.clearAllCalls()
            self.mpdPlayer?.control.toggleRepeat()
        }
        testScheduler.scheduleAt(300) {
            self.mpdWrapper.assertCall("run_repeat", expectedParameters: ["mode": "\(false)"])
            self.mpdWrapper.assertCall("run_single", expectedParameters: ["mode": "\(false)"])
        }

        testScheduler.start()
    }
    
    func testRandomOnOffSentToMPD() {
        testScheduler.scheduleAt(50) {
            self.mpdPlayer?.control.setRandom(randomMode: .On)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_random", expectedParameters: ["mode": "\(true)"])
        }
        testScheduler.scheduleAt(150) {
            self.mpdWrapper.clearAllCalls()
            self.mpdPlayer?.control.setRandom(randomMode: .Off)
        }
        testScheduler.scheduleAt(200) {
            self.mpdWrapper.assertCall("run_random", expectedParameters: ["mode": "\(false)"])
        }

        testScheduler.start()
    }
 
    func testToggleRandomSentToMPD() {
        let mpdStatus = self.mpdPlayer?.status as! MPDStatus
        var playerStatus = PlayerStatus()
        
        testScheduler.scheduleAt(10) {
            playerStatus.playing.randomMode = .Off
            mpdStatus.testSetPlayerStatus(playerStatus: playerStatus)
        }
        testScheduler.scheduleAt(50) {
            self.mpdPlayer?.control.toggleRandom()
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_random", expectedParameters: ["mode": "\(true)"])
        }
        testScheduler.scheduleAt(110) {
            playerStatus.playing.randomMode = .On
            mpdStatus.testSetPlayerStatus(playerStatus: playerStatus)
        }
        testScheduler.scheduleAt(150) {
            self.mpdWrapper.clearAllCalls()
            self.mpdPlayer?.control.toggleRandom()
        }
        testScheduler.scheduleAt(200) {
            self.mpdWrapper.assertCall("run_random", expectedParameters: ["mode": "\(false)"])
        }
        
        testScheduler.start()
    }
    
    func testAddOneSongReplace() {
        testScheduler.scheduleAt(50) {
            var song = Song()
            song.title = "Title"
            song.id = "1"
            self.mpdPlayer?.control.addSong(song, addMode: .replace)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_clear")
            self.mpdWrapper.assertCall("run_add_id_to", expectedParameters: ["uri": "1", "to": "0"])
            self.mpdWrapper.assertCall("run_play_pos", expectedParameters: ["song_pos": "0"])
        }
        
        testScheduler.start()
    }

    func testAddOneSongNext() {
        let mpdStatus = self.mpdPlayer?.status as! MPDStatus
        var playerStatus = PlayerStatus()

        testScheduler.scheduleAt(10) {
            playerStatus.playqueue.length = 10
            playerStatus.playqueue.songIndex = 4
            mpdStatus.testSetPlayerStatus(playerStatus: playerStatus)
        }
        testScheduler.scheduleAt(50) {
            var song = Song()
            song.title = "Title"
            song.id = "1"
            self.mpdPlayer?.control.addSong(song, addMode: .addNext)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_clear", expectedCallCount: 0)
            self.mpdWrapper.assertCall("run_add_id_to", expectedParameters: ["uri": "1", "to": "5"])
            self.mpdWrapper.assertCall("run_play_pos", expectedCallCount: 0)
        }
        
        testScheduler.start()
    }

    func testAddOneSongAtEnd() {
        let mpdStatus = self.mpdPlayer?.status as! MPDStatus
        var playerStatus = PlayerStatus()
        
        testScheduler.scheduleAt(10) {
            playerStatus.playqueue.length = 10
            playerStatus.playqueue.songIndex = 4
            mpdStatus.testSetPlayerStatus(playerStatus: playerStatus)
        }
        testScheduler.scheduleAt(50) {
            var song = Song()
            song.title = "Title"
            song.id = "1"
            self.mpdPlayer?.control.addSong(song, addMode: .addAtEnd)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_clear", expectedCallCount: 0)
            self.mpdWrapper.assertCall("run_add_id_to", expectedParameters: ["uri": "1", "to": "10"])
            self.mpdWrapper.assertCall("run_play_pos", expectedCallCount: 0)
        }
        
        testScheduler.start()
    }
    
    func testAddOneSongNextAndPlay() {
        let mpdStatus = self.mpdPlayer?.status as! MPDStatus
        var playerStatus = PlayerStatus()
        
        testScheduler.scheduleAt(10) {
            playerStatus.playqueue.length = 10
            playerStatus.playqueue.songIndex = 4
            mpdStatus.testSetPlayerStatus(playerStatus: playerStatus)
        }
        testScheduler.scheduleAt(50) {
            var song = Song()
            song.title = "Title"
            song.id = "1"
            self.mpdPlayer?.control.addSong(song, addMode: .addNextAndPlay)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_clear", expectedCallCount: 0)
            self.mpdWrapper.assertCall("run_add_id_to", expectedParameters: ["uri": "1", "to": "5"])
            self.mpdWrapper.assertCall("run_play_pos", expectedParameters: ["song_pos": "5"])
        }
        
        testScheduler.start()
    }
    
    func testMoveSong() {
        testScheduler.scheduleAt(50) {
            _ = self.mpdPlayer?.control.moveSong(from: 3, to: 7)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_move", expectedParameters: ["from": "3", "to": "7"])
        }
        
        testScheduler.start()
    }
    
    func testDeleteSong() {
        testScheduler.scheduleAt(50) {
            _ = self.mpdPlayer?.control.deleteSong(5)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_delete", expectedParameters: ["pos": "5"])
        }
        
        testScheduler.start()
    }
}
