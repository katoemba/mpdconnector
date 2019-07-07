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
        mpdPlayer = MPDPlayer.init(mpd: mpdWrapper, name: "player", host: "localhost", port: 6600, scheduler: testScheduler, userDefaults: UserDefaults.standard)
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
            self.mpdPlayer?.control.setVolume(0.6)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_set_volume", expectedParameters: ["volume": "\(60)"])
        }
        
        testScheduler.start()
    }

    func testSetInvalidVolumeNotSentToMPD() {
        testScheduler.scheduleAt(50) {
            self.mpdPlayer?.control.setVolume(-10.0)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_set_volume", expectedCallCount: 0)
        }
        
        testScheduler.scheduleAt(150) {
            self.mpdWrapper.clearAllCalls()
            self.mpdPlayer?.control.setVolume(1.1)
        }
        testScheduler.scheduleAt(200) {
            self.mpdWrapper.assertCall("run_set_volume", expectedCallCount: 0)
        }
        
        testScheduler.start()
    }
    
    func testSetSeek() {
        mpdWrapper.elapsedTime = 5
        mpdWrapper.trackTime = 100
        mpdWrapper.songDuration = 100
        mpdWrapper.songIndex = 5

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
        mpdWrapper.elapsedTime = 5
        mpdWrapper.trackTime = 100
        mpdWrapper.songDuration = 100
        mpdWrapper.songIndex = 6
        
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
        self.mpdPlayer?.control.play()
            .subscribe(onNext: { (_) in
                self.mpdWrapper.assertCall("run_play")
            })
            .disposed(by: self.bag)
        
        testScheduler.start()
    }
    
    func testPlayWithIndexSentToMPD() {
        self.mpdPlayer?.control.play(index: 3)
            .subscribe(onNext: { (_) in
                self.mpdWrapper.assertCall("run_play_pos", expectedCallCount: 1, expectedParameters: ["song_pos": "3"])
            })
            .disposed(by: self.bag)
        
        testScheduler.start()
    }
    
    func testPlayWithInvalidIndexNotSentToMPD() {
        self.mpdPlayer?.control.play(index: -1)
            .subscribe(onNext: { (_) in
                self.mpdWrapper.assertCall("run_play_pos", expectedCallCount: 0)
            })
            .disposed(by: self.bag)
        
        testScheduler.start()
    }
    
    func testPauseSentToMPD() {
        self.mpdPlayer?.control.pause()
            .subscribe(onNext: { (_) in
                self.mpdWrapper.assertCall("run_pause", expectedParameters: ["mode": "\(true)"])
            })
            .disposed(by: self.bag)
        
        testScheduler.start()
    }

    func testTogglePauseSentToMPD() {
        self.mpdPlayer?.control.togglePlayPause()
            .subscribe(onNext: { (_) in
                self.mpdWrapper.assertCall("run_toggle_pause")
            })
            .disposed(by: self.bag)
        
        testScheduler.start()
    }
    
    func testSkipSentToMPD() {
        self.mpdPlayer?.control.skip()
            .subscribe(onNext: { (_) in
                self.mpdWrapper.assertCall("run_next")
            })
            .disposed(by: self.bag)
        
        testScheduler.start()
    }
    
    func testBackSentToMPD() {
        self.mpdPlayer?.control.back()
            .subscribe(onNext: { (_) in
                self.mpdWrapper.assertCall("run_previous")
            })
            .disposed(by: self.bag)
        
        testScheduler.start()
    }

    func testShuffleSentToMPD() {
        self.mpdPlayer?.control.shufflePlayqueue()
            .subscribe(onNext: { (_) in
                self.mpdWrapper.assertCall("run_shuffle", expectedParameters: [:])
            })
            .disposed(by: self.bag)
        
        testScheduler.start()
    }
    
    func testRepeatOffSentToMPD() {
        self.mpdPlayer?.control.setRepeat(.Off)
            .subscribe(onNext: { (_) in
                self.mpdWrapper.assertCall("run_repeat", expectedParameters: ["mode": "\(false)"])
                self.mpdWrapper.assertCall("run_single", expectedParameters: ["mode": "\(false)"])
            })
            .disposed(by: self.bag)
        
        testScheduler.start()
    }
    
    func testRepeatSingleSentToMPD() {
        self.mpdPlayer?.control.setRepeat(.Single)
            .subscribe(onNext: { (_) in
                self.mpdWrapper.assertCall("run_repeat", expectedParameters: ["mode": "\(true)"])
                self.mpdWrapper.assertCall("run_single", expectedParameters: ["mode": "\(true)"])
            })
            .disposed(by: self.bag)
        
        testScheduler.start()
    }
    
    func testRepeatAllSentToMPD() {
        self.mpdPlayer?.control.setRepeat(.All)
            .subscribe(onNext: { (_) in
                self.mpdWrapper.assertCall("run_repeat", expectedParameters: ["mode": "\(true)"])
                self.mpdWrapper.assertCall("run_single", expectedParameters: ["mode": "\(false)"])
            })
            .disposed(by: self.bag)
        
        testScheduler.start()
    }
    
    func testRepeatAlbumSentToMPD() {
        self.mpdPlayer?.control.setRepeat(.Album)
            .subscribe(onNext: { (_) in
                self.mpdWrapper.assertCall("run_repeat", expectedParameters: ["mode": "\(true)"])
                self.mpdWrapper.assertCall("run_single", expectedParameters: ["mode": "\(false)"])
            })
            .disposed(by: self.bag)
        
        testScheduler.start()
    }
    
    func testRepeatToggleSentToMPD() {
        let mpdStatus = self.mpdPlayer?.status as! MPDStatus
        var playerStatus = PlayerStatus()

        playerStatus.playing.repeatMode = .Off
        mpdStatus.testSetPlayerStatus(playerStatus: playerStatus)

        if let player = self.mpdPlayer {
            player.control.toggleRepeat()
                .flatMap({ (_) -> Observable<PlayerStatus> in
                    self.mpdWrapper.assertCall("run_repeat", expectedParameters: ["mode": "\(true)"])
                    self.mpdWrapper.assertCall("run_single", expectedParameters: ["mode": "\(false)"])

                    playerStatus.playing.repeatMode = .All
                    mpdStatus.testSetPlayerStatus(playerStatus: playerStatus)

                    self.mpdWrapper.clearAllCalls()
                    return player.control.toggleRepeat()
                })
                .flatMap({ (_) -> Observable<PlayerStatus> in
                    self.mpdWrapper.assertCall("run_repeat", expectedParameters: ["mode": "\(true)"])
                    self.mpdWrapper.assertCall("run_single", expectedParameters: ["mode": "\(true)"])

                    playerStatus.playing.repeatMode = .Single
                    mpdStatus.testSetPlayerStatus(playerStatus: playerStatus)

                    self.mpdWrapper.clearAllCalls()
                    return player.control.toggleRepeat()
                })
                .subscribe(onNext: { (_) in
                    self.mpdWrapper.assertCall("run_repeat", expectedParameters: ["mode": "\(false)"])
                    self.mpdWrapper.assertCall("run_single", expectedParameters: ["mode": "\(false)"])
                })
                .disposed(by: bag)
        }
        else {
            XCTAssert(false, "Player nil at start of test")
        }
        
        testScheduler.start()
    }
    
    func testRandomOnOffSentToMPD() {
        if let player = self.mpdPlayer {
            player.control.setRandom(.On)
                .flatMapFirst({ (_) -> Observable<PlayerStatus> in
                    self.mpdWrapper.assertCall("run_random", expectedParameters: ["mode": "\(true)"])

                    self.mpdWrapper.clearAllCalls()
                    return player.control.setRandom(.Off)
                })
                .subscribe(onNext: { (_) in
                    self.mpdWrapper.assertCall("run_random", expectedParameters: ["mode": "\(false)"])
                })
                .disposed(by: bag)
        }
        else {
            XCTAssert(false, "Player nil at start of test")
        }

        testScheduler.start()
    }
 
    func testToggleRandomSentToMPD() {
        let mpdStatus = self.mpdPlayer?.status as! MPDStatus
        var playerStatus = PlayerStatus()
        
        playerStatus.playing.randomMode = .Off
        mpdStatus.testSetPlayerStatus(playerStatus: playerStatus)

        if let player = self.mpdPlayer {
            player.control.toggleRandom()
                .flatMapFirst({ (_) -> Observable<PlayerStatus> in
                    self.mpdWrapper.assertCall("run_random", expectedParameters: ["mode": "\(true)"])

                    playerStatus.playing.randomMode = .On
                    mpdStatus.testSetPlayerStatus(playerStatus: playerStatus)

                    self.mpdWrapper.clearAllCalls()
                    return player.control.toggleRandom()
                })
                .subscribe(onNext: { (_) in
                    self.mpdWrapper.assertCall("run_random", expectedParameters: ["mode": "\(false)"])
                })
                .disposed(by: bag)
        }
        else {
            XCTAssert(false, "Player nil at start of test")
        }

        testScheduler.start()
    }
    
    func testConsumeOnOffSentToMPD() {
        testScheduler.scheduleAt(50) {
            self.mpdPlayer?.control.setConsume(.On)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_consume", expectedParameters: ["mode": "\(true)"])
        }
        testScheduler.scheduleAt(150) {
            self.mpdWrapper.clearAllCalls()
            self.mpdPlayer?.control.setConsume(.Off)
        }
        testScheduler.scheduleAt(200) {
            self.mpdWrapper.assertCall("run_consume", expectedParameters: ["mode": "\(false)"])
        }
        
        testScheduler.start()
    }
    
    func testToggleConsumeSentToMPD() {
        let mpdStatus = self.mpdPlayer?.status as! MPDStatus
        var playerStatus = PlayerStatus()
        
        testScheduler.scheduleAt(10) {
            playerStatus.playing.consumeMode = .Off
            mpdStatus.testSetPlayerStatus(playerStatus: playerStatus)
        }
        testScheduler.scheduleAt(50) {
            self.mpdPlayer?.control.toggleConsume()
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_consume", expectedParameters: ["mode": "\(true)"])
        }
        testScheduler.scheduleAt(110) {
            playerStatus.playing.consumeMode = .On
            mpdStatus.testSetPlayerStatus(playerStatus: playerStatus)
        }
        testScheduler.scheduleAt(150) {
            self.mpdWrapper.clearAllCalls()
            self.mpdPlayer?.control.toggleConsume()
        }
        testScheduler.scheduleAt(200) {
            self.mpdWrapper.assertCall("run_consume", expectedParameters: ["mode": "\(false)"])
        }
        
        testScheduler.start()
    }
    
    func testAddOneSongReplace() {
        var song = Song()
        song.title = "Title"
        song.id = "1"
        self.mpdPlayer?.control.add(song, addDetails: AddDetails(.replace))
            .subscribe(onNext: { (_) in
                self.mpdWrapper.assertCall("run_clear")
                self.mpdWrapper.assertCall("run_add_id_to", expectedParameters: ["uri": "1", "to": "0"])
                self.mpdWrapper.assertCall("run_play_pos", expectedParameters: ["song_pos": "0"])
            })
            .disposed(by: bag)
        
        testScheduler.start()
    }

    func testAddFiftySongsReplace() {
        var songs = [Song]()
        for i in 1...50 {
            var song = Song()
            song.title = "Title"
            song.id = "\(i)"
            songs.append(song)
        }
        self.mpdPlayer?.control.add(songs, addDetails: AddDetails(.replace))
            .subscribe(onNext: { (_) in
                self.mpdWrapper.assertCall("run_clear")
                self.mpdWrapper.assertCall("command_list_begin", expectedCallCount: 2, expectedParameters: ["discrete_ok": "false"])
                self.mpdWrapper.assertCall("send_add_id_to", expectedCallCount: 50)
                self.mpdWrapper.assertCall("command_list_end", expectedCallCount: 2)
                self.mpdWrapper.assertCall("run_play_pos", expectedParameters: ["song_pos": "0"])
            })
            .disposed(by: bag)
        
        testScheduler.start()
    }
    
    func testAddOneSongNext() {
        self.mpdWrapper.queueLength = 10
        self.mpdWrapper.songIndex = 4

        var song = Song()
        song.title = "Title"
        song.id = "1"
        self.mpdPlayer?.control.add(song, addDetails: AddDetails(.addNext))
            .subscribe(onNext: { (_) in
                self.mpdWrapper.assertCall("run_clear", expectedCallCount: 0)
                self.mpdWrapper.assertCall("run_add_id_to", expectedParameters: ["uri": "1", "to": "5"])
                self.mpdWrapper.assertCall("run_play_pos", expectedCallCount: 0)
            })
            .disposed(by: bag)
        
        testScheduler.start()
    }

    func testAddOneSongAtEnd() {
        self.mpdWrapper.queueLength = 10
        self.mpdWrapper.songIndex = 4

        var song = Song()
        song.title = "Title"
        song.id = "1"
        self.mpdPlayer?.control.add(song, addDetails: AddDetails(.addAtEnd))
            .subscribe(onNext: { (_) in
                self.mpdWrapper.assertCall("run_clear", expectedCallCount: 0)
                self.mpdWrapper.assertCall("run_add_id_to", expectedParameters: ["uri": "1", "to": "10"])
                self.mpdWrapper.assertCall("run_play_pos", expectedCallCount: 0)
            })
            .disposed(by: bag)
        
        testScheduler.start()
    }
    
    func testAddOneSongNextAndPlay() {
        self.mpdWrapper.queueLength = 10
        self.mpdWrapper.songIndex = 4

        var song = Song()
        song.title = "Title"
        song.id = "1"
        self.mpdPlayer?.control.add(song, addDetails: AddDetails(.addNextAndPlay))
            .subscribe(onNext: { (_) in
                self.mpdWrapper.assertCall("run_clear", expectedCallCount: 0)
                self.mpdWrapper.assertCall("run_add_id_to", expectedParameters: ["uri": "1", "to": "5"])
                self.mpdWrapper.assertCall("run_play_pos", expectedParameters: ["song_pos": "5"])
            })
            .disposed(by: bag)
        
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
    
    func testMoveSongPlaylist() {
        testScheduler.scheduleAt(50) {
            var playlist = Playlist()
            playlist.id = "mplist"
            _ = self.mpdPlayer?.control.moveSong(playlist: playlist, from: 3, to: 7)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_playlist_move", expectedParameters: ["name": "mplist", "from": "3", "to": "7"])
        }
        
        testScheduler.start()
    }
    
    func testDeleteSongPlaylist() {
        testScheduler.scheduleAt(50) {
            var playlist = Playlist()
            playlist.id = "dplist"
            _ = self.mpdPlayer?.control.deleteSong(playlist: playlist, at: 5)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_playlist_delete", expectedParameters: ["name": "dplist", "pos": "5"])
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
        var playlist = Playlist()
        playlist.id = "plist"
        _ = self.mpdPlayer?.control.add(playlist, addDetails: AddDetails(.replace, startWithSong: 3))
            .subscribe(onNext: { (_, _) in
                self.mpdWrapper.assertCall("run_clear", expectedCallCount: 1)
                self.mpdWrapper.assertCall("run_load", expectedParameters: ["name": "plist"])
                self.mpdWrapper.assertCall("run_shuffle", expectedCallCount: 0)
                self.mpdWrapper.assertCall("run_play_pos", expectedParameters: ["song_pos": "3"])
            })
            .disposed(by: bag)
        
        testScheduler.start()
    }

    func testAddShufflePlaylist() {
        var playlist = Playlist()
        playlist.id = "plist"
        _ = self.mpdPlayer?.control.add(playlist, addDetails: AddDetails(.replace, shuffle: true))
            .subscribe(onNext: { (_, _) in
                self.mpdWrapper.assertCall("run_clear", expectedCallCount: 1)
                self.mpdWrapper.assertCall("run_load", expectedParameters: ["name": "plist"])
                self.mpdWrapper.assertCall("run_shuffle", expectedCallCount: 1)
                self.mpdWrapper.assertCall("run_play_pos", expectedParameters: ["song_pos": "0"])
            })
            .disposed(by: bag)
        
        testScheduler.start()
    }

    func testAppendPlaylist() {
        var playlist = Playlist()
        playlist.id = "plist"
        _ = self.mpdPlayer?.control.add(playlist, addDetails: AddDetails(.replace, startWithSong: 112))
            .subscribe(onNext: { (_, _) in
                self.mpdWrapper.assertCall("run_clear", expectedCallCount: 1)
                self.mpdWrapper.assertCall("run_load", expectedParameters: ["name": "plist"])
                self.mpdWrapper.assertCall("run_shuffle", expectedCallCount: 0)
                self.mpdWrapper.assertCall("run_play_pos", expectedParameters: ["song_pos": "112"])
            })
            .disposed(by: bag)
        
        testScheduler.start()
    }
    
    func testEnableOutputSentToMPD() {
        var output = Output()
        output.id = "1"
        
        testScheduler.scheduleAt(50) {
            self.mpdPlayer?.control.setOutput(output, enabled: true)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_enable_output", expectedParameters: ["output_id": "1"])
            self.mpdWrapper.assertCall("output_free", expectedCallCount: 0)
        }

        testScheduler.start()
    }

    func testDisableOutputSentToMPD() {
        var output = Output()
        output.id = "2"
        
        testScheduler.scheduleAt(50) {
            self.mpdPlayer?.control.setOutput(output, enabled: false)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_disable_output", expectedParameters: ["output_id": "2"])
            self.mpdWrapper.assertCall("output_free", expectedCallCount: 0)
        }
        
        testScheduler.start()
    }

    func testToggleOutputSentToMPD() {
        var output = Output()
        output.id = "3"
        
        testScheduler.scheduleAt(50) {
            self.mpdPlayer?.control.toggleOutput(output)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_toggle_output", expectedParameters: ["output_id": "3"])
            self.mpdWrapper.assertCall("output_free", expectedCallCount: 0)
        }
        
        testScheduler.start()
    }
}
