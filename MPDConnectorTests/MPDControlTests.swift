//
//  MPDControlTests.swift
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
        mpdPlayer = MPDPlayer.init(mpd: mpdWrapper, name: "player", host: "localhost", port: 6600, scheduler: testScheduler)
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
    
    func testSetSeek() {
        let mpdStatus = self.mpdPlayer?.status as! MPDStatus
        var playerStatus = PlayerStatus()
        
        testScheduler.scheduleAt(10) {
            var song = Song()
            song.length = 100
            song.position = 5
            playerStatus.currentSong = song
            mpdStatus.testSetPlayerStatus(playerStatus: playerStatus)
        }
        testScheduler.scheduleAt(50) {
            self.mpdPlayer?.control.setSeek(seconds: 10)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_seek", expectedParameters: ["pos": "5", "t": "10"])
        }

        testScheduler.start()
    }
    
    func testSetInvalidSeek() {
        let mpdStatus = self.mpdPlayer?.status as! MPDStatus
        var playerStatus = PlayerStatus()
        
        testScheduler.scheduleAt(10) {
            var song = Song()
            song.length = 100
            song.position = 5
            playerStatus.currentSong = song
            mpdStatus.testSetPlayerStatus(playerStatus: playerStatus)
        }
        testScheduler.scheduleAt(50) {
            self.mpdPlayer?.control.setSeek(seconds: 200)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_seek", expectedCallCount: 0)
        }
        
        testScheduler.start()
    }
    
    func testSetRelativeSeek() {
        let mpdStatus = self.mpdPlayer?.status as! MPDStatus
        var playerStatus = PlayerStatus()
        
        testScheduler.scheduleAt(10) {
            var song = Song()
            song.length = 100
            song.position = 6
            playerStatus.currentSong = song
            mpdStatus.testSetPlayerStatus(playerStatus: playerStatus)
        }
        testScheduler.scheduleAt(50) {
            self.mpdPlayer?.control.setSeek(percentage: 0.3)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_seek", expectedParameters: ["pos": "6", "t": "30"])
        }
        
        testScheduler.start()
    }
    
    func testSetInvalidRelativeSeek() {
        let mpdStatus = self.mpdPlayer?.status as! MPDStatus
        var playerStatus = PlayerStatus()
        
        testScheduler.scheduleAt(10) {
            var song = Song()
            song.length = 100
            song.position = 6
            playerStatus.currentSong = song
            mpdStatus.testSetPlayerStatus(playerStatus: playerStatus)
        }
        testScheduler.scheduleAt(50) {
            self.mpdPlayer?.control.setSeek(percentage: 1.3)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_seek", expectedCallCount: 0)
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

    func testAddFiftySongsReplace() {
        testScheduler.scheduleAt(50) {
            var songs = [Song]()
            for i in 1...50 {
                var song = Song()
                song.title = "Title"
                song.id = "\(i)"
                songs.append(song)
            }
            self.mpdPlayer?.control.addSongs(songs, addMode: .replace)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_clear")
            self.mpdWrapper.assertCall("command_list_begin", expectedCallCount: 2, expectedParameters: ["discrete_ok": "false"])
            self.mpdWrapper.assertCall("send_add_id_to", expectedCallCount: 50)
            self.mpdWrapper.assertCall("command_list_end", expectedCallCount: 2)
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
    
    func testSavePlaylist() {
        testScheduler.scheduleAt(50) {
            _ = self.mpdPlayer?.control.savePlaylist("Name of the Game")
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_save", expectedParameters: ["name": "Name of the Game"])
        }
        
        testScheduler.start()
    }
    
    func testClearPlayqueue() {
        testScheduler.scheduleAt(50) {
            _ = self.mpdPlayer?.control.clearPlayqueue()
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_clear")
        }
        
        testScheduler.start()
    }
    
    func testAddPlaylist() {
        testScheduler.scheduleAt(50) {
            var playlist = Playlist()
            playlist.id = "plist"
            _ = self.mpdPlayer?.control.addPlaylist(playlist, addMode: .replace, shuffle: false, startWithSong: 3)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_clear", expectedCallCount: 1)
            self.mpdWrapper.assertCall("run_load", expectedParameters: ["name": "plist"])
            self.mpdWrapper.assertCall("run_shuffle", expectedCallCount: 0)
            self.mpdWrapper.assertCall("run_play_pos", expectedParameters: ["song_pos": "3"])
        }
        
        testScheduler.start()
    }

    func testAddShufflePlaylist() {
        testScheduler.scheduleAt(50) {
            var playlist = Playlist()
            playlist.id = "plist"
            _ = self.mpdPlayer?.control.addPlaylist(playlist, addMode: .replace, shuffle: true, startWithSong: 0)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_clear", expectedCallCount: 1)
            self.mpdWrapper.assertCall("run_load", expectedParameters: ["name": "plist"])
            self.mpdWrapper.assertCall("run_shuffle", expectedCallCount: 1)
            self.mpdWrapper.assertCall("run_play_pos", expectedParameters: ["song_pos": "0"])
        }
        
        testScheduler.start()
    }

    func testAppendPlaylist() {
        testScheduler.scheduleAt(50) {
            var playlist = Playlist()
            playlist.id = "plist"
            _ = self.mpdPlayer?.control.addPlaylist(playlist, addMode: .addAtEnd, shuffle: false, startWithSong: 112)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_clear", expectedCallCount: 0)
            self.mpdWrapper.assertCall("run_load", expectedParameters: ["name": "plist"])
            self.mpdWrapper.assertCall("run_shuffle", expectedCallCount: 0)
            self.mpdWrapper.assertCall("run_play_pos", expectedParameters: ["song_pos": "112"])
        }
        
        testScheduler.start()
    }
}
