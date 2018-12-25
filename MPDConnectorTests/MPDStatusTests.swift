//
//  MPDStatusTests.swift
//  MPDConnectorTests
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

class MPDStatusTests: XCTestCase {
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
    
    func testStartAndStopConnection() {
        // Given a mpd player
        let connectionProperties = [ConnectionProperties.Name.rawValue: "player",
                                    ConnectionProperties.Host.rawValue: "host",
                                    ConnectionProperties.Port.rawValue: 1000,
                                    ConnectionProperties.Password.rawValue: ""] as [String: Any]
        
        // When creating a new MPDStatus object and starting it
        let status = MPDStatus.init(mpd: mpdWrapper, connectionProperties: connectionProperties)
        status.start()
        
        // And then stop, start and stop again
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            status.stop()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            status.start()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            status.stop()
        }

        // Then the statuses .online, .offline, .online, .offline are reported
        let connectionResults = status.connectionStatusObservable
            .distinctUntilChanged()
            .toBlocking(timeout: 1.0)
            .materialize()

        switch connectionResults {
        case .failed(let connectionStatusArray, _):
            XCTAssert(connectionStatusArray == [.online, .offline, .online, .offline], "Expected reported statuses [.online, .offline, .online, .offline], got \(connectionStatusArray)")
        default:
            print("Default")
        }
    }

    func testStartAndStop() {
        // Given a mpd player
        let connectionProperties = [ConnectionProperties.Name.rawValue: "player",
                                    ConnectionProperties.Host.rawValue: "host",
                                    ConnectionProperties.Port.rawValue: 1000,
                                    ConnectionProperties.Password.rawValue: ""] as [String: Any]
        self.mpdWrapper.songIndex = 2
        
        // When creating a new MPDStatus object and starting it
        let status = MPDStatus.init(mpd: mpdWrapper, connectionProperties: connectionProperties)
        status.start()
        
        // And changing the songIndex, stopping and changing the songIndex again
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.mpdWrapper.songIndex = 3
            status.forceStatusRefresh()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            status.stop()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.mpdWrapper.songIndex = 4
            status.forceStatusRefresh()
        }
        
        // Then only the songIndex values before the 'stop' are reported.
        let playerStatusResults = status.playerStatusObservable
            .toBlocking(timeout: 1.0)
            .materialize()
        
        switch playerStatusResults {
        case .failed(let playerStatusArray, _):
            let songIndexArray = playerStatusArray.map({ (status) -> Int in
                status.playqueue.songIndex
            })
            XCTAssert(songIndexArray == [0, 2, 3], "Expected reported song indexes [0, 2, 3], got \(songIndexArray)")
        default:
            print("Default")
        }
    }
    
    func testMultipleStarts() {
        // Given a mpd player
        let connectionProperties = [ConnectionProperties.Name.rawValue: "player",
                                    ConnectionProperties.Host.rawValue: "host",
                                    ConnectionProperties.Port.rawValue: 1000,
                                    ConnectionProperties.Password.rawValue: ""] as [String: Any]
        
        // When creating a new MPDStatus object and starting it twice
        let status = MPDStatus.init(mpd: mpdWrapper, connectionProperties: connectionProperties)
        status.start()
        status.start()

        // Then the statuses .online is reported once
        let connectionResults = status.connectionStatusObservable
            .toBlocking(timeout: 0.4)
            .materialize()
        
        switch connectionResults {
        case .failed(let connectionStatusArray, _):
            let count = connectionStatusArray.filter({ (status) -> Bool in
                status == .online
            }).count
            
            XCTAssert(count == 1, "Expected reported 1 online status, got \(count)")
        default:
            print("Default")
        }
    }

    func testPlayerStatus() {
        // Given a mpd player
        let connectionProperties = [ConnectionProperties.Name.rawValue: "player",
                                    ConnectionProperties.Host.rawValue: "host",
                                    ConnectionProperties.Port.rawValue: 1000,
                                    ConnectionProperties.Password.rawValue: ""] as [String: Any]
        
        // When creating a new MPDStatus object and starting it twice
        let status = MPDStatus.init(mpd: mpdWrapper, connectionProperties: connectionProperties)
        status.start()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.mpdWrapper.songIndex = 3
            self.mpdWrapper.album = "Everything Now"
            self.mpdWrapper.artist = "Arcade Fire"
            self.mpdWrapper.songTitle = "Creature Comfort"
            self.mpdWrapper.queueVersion = 10
            self.mpdWrapper.queueLength = 15
            self.mpdWrapper.volume = 75
            self.mpdWrapper.random = true
            self.mpdWrapper.singleValue = true
            self.mpdWrapper.repeatValue = true
            self.mpdWrapper.songDuration = 330
            self.mpdWrapper.songIndex = 5
            self.mpdWrapper.state = MPD_STATE_PLAY
            self.mpdWrapper.samplerate = 192000
            self.mpdWrapper.encoding = 24
            self.mpdWrapper.channels = 1
            self.mpdWrapper.outputs = [(1, "out1", true), (2, "out2", false)]
            
            self.mpdWrapper.statusChanged()
        }

        // Then the statuses .online is reported once
        let playerStatuses = status.playerStatusObservable
            .toBlocking(timeout: 0.4)
            .materialize()
        
        switch playerStatuses {
        case .failed(let playerStatusArray, _):
            let playerStatus = playerStatusArray.last!
            
            XCTAssert(playerStatus.playing.playPauseMode == .Playing, "Expected .Playing, got \(playerStatus.playing.playPauseMode)")
            XCTAssert(playerStatus.playing.randomMode == .On, "Expected .On, got \(playerStatus.playing.randomMode)")
            XCTAssert(playerStatus.playing.repeatMode == .Single, "Expected .Single, got \(playerStatus.playing.repeatMode)")
            XCTAssert(playerStatus.volume == 0.75, "Expected volume 0.75, got \(playerStatus.volume)")
            XCTAssert(playerStatus.volumeEnabled == true, "Expected volumeEnabled true, got \(playerStatus.volumeEnabled)")
            XCTAssert(playerStatus.playqueue.version == 10, "Expected version 10, got \(playerStatus.playqueue.version)")
            XCTAssert(playerStatus.playqueue.length == 15, "Expected length 15, got \(playerStatus.playqueue.length)")
            XCTAssert(playerStatus.playqueue.songIndex == 5, "Expected songIndex 5, got \(playerStatus.playqueue.songIndex)")
            XCTAssert(playerStatus.currentSong.title == "Creature Comfort", "Expected Creature Comfort, got \(playerStatus.currentSong.title)")
            XCTAssert(playerStatus.currentSong.artist == "Arcade Fire", "Expected Arcade Fire, got \(playerStatus.currentSong.artist)")
            XCTAssert(playerStatus.currentSong.album == "Everything Now", "Expected Everything Now, got \(playerStatus.currentSong.album)")
            XCTAssert(playerStatus.quality.samplerate == "192kHz", "Expected bitrate 192kHz, got \(playerStatus.quality.samplerate)")
            XCTAssert(playerStatus.quality.encoding == "24bit", "Expected encoding 24bit, got \(playerStatus.quality.encoding)")
            XCTAssert(playerStatus.quality.channels == "Mono", "Expected channels Mono, got \(playerStatus.quality.channels)")
            XCTAssert(playerStatus.outputs.count == 2, "Expected 2 outputs, got \(playerStatus.outputs.count)")
            if playerStatus.outputs.count == 2 {
                XCTAssert(playerStatus.outputs[0].id == "1", "Expected output id 1, got \(playerStatus.outputs[0].id)")
                XCTAssert(playerStatus.outputs[0].name == "out1", "Expected output name out1, got \(playerStatus.outputs[0].name)")
                XCTAssert(playerStatus.outputs[0].enabled == true, "Expected output enabled true, got \(playerStatus.outputs[0].enabled)")

                XCTAssert(playerStatus.outputs[1].id == "2", "Expected output id 2, got \(playerStatus.outputs[1].id)")
                XCTAssert(playerStatus.outputs[1].name == "out2", "Expected output name out2, got \(playerStatus.outputs[1].name)")
                XCTAssert(playerStatus.outputs[1].enabled == false, "Expected output enabled false, got \(playerStatus.outputs[1].enabled)")
            }

            // Check that all song data is freed
            let songCount = self.mpdWrapper.callCount("run_current_song") +
                            self.mpdWrapper.callCount("get_song")
            let songFreeCount = self.mpdWrapper.callCount("song_free")
            XCTAssert(songCount == songFreeCount, "Expected \(songCount) for songFreeCount, got \(songFreeCount)")

            // Check that all status data is freed
            let statusCount = self.mpdWrapper.callCount("run_status")
            let statusFreeCount = self.mpdWrapper.callCount("status_free")
            XCTAssert(statusCount == statusFreeCount, "Expected \(statusCount) for statusFreeCount, got \(statusFreeCount)")

            // Check that all output data is freed
            let outputCount = self.mpdWrapper.callCount("recv_output")
            let outputFreeCount = self.mpdWrapper.callCount("output_free")
            let fetchCount = self.mpdWrapper.callCount("send_outputs")
            XCTAssert(outputCount - fetchCount == outputFreeCount, "Expected \(outputCount - fetchCount) for statusFreeCount, got \(outputFreeCount)")
        default:
            print("Default")
        }
        
    }
    
    func testPlayerStatusQualityDSD() {
        // Given a mpd player
        let connectionProperties = [ConnectionProperties.Name.rawValue: "player",
                                    ConnectionProperties.Host.rawValue: "host",
                                    ConnectionProperties.Port.rawValue: 1000,
                                    ConnectionProperties.Password.rawValue: ""] as [String: Any]
        
        // When creating a new MPDStatus object and starting it twice
        let status = MPDStatus.init(mpd: mpdWrapper, connectionProperties: connectionProperties)
        status.start()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.mpdWrapper.songIndex = 3
            self.mpdWrapper.album = "Everything Now"
            self.mpdWrapper.artist = "Arcade Fire"
            self.mpdWrapper.songTitle = "Creature Comfort"
            self.mpdWrapper.queueVersion = 10
            self.mpdWrapper.queueLength = 15
            self.mpdWrapper.volume = -1
            self.mpdWrapper.random = true
            self.mpdWrapper.singleValue = true
            self.mpdWrapper.repeatValue = true
            self.mpdWrapper.songDuration = 330
            self.mpdWrapper.songIndex = 5
            self.mpdWrapper.state = MPD_STATE_PLAY
            self.mpdWrapper.samplerate = 192000
            self.mpdWrapper.encoding = UInt8(MPD_SAMPLE_FORMAT_DSD)
            self.mpdWrapper.channels = 2
            
            self.mpdWrapper.statusChanged()
        }
        
        // Then the statuses .online is reported once
        let playerStatuses = status.playerStatusObservable
            .toBlocking(timeout: 0.4)
            .materialize()
        
        switch playerStatuses {
        case .failed(let playerStatusArray, _):
            let playerStatus = playerStatusArray.last!
            
            XCTAssert(playerStatus.volume == 0.5, "Expected volume 0.5, got \(playerStatus.volume)")
            XCTAssert(playerStatus.volumeEnabled == false, "Expected volumeEnabled false, got \(playerStatus.volumeEnabled)")
            XCTAssert(playerStatus.quality.encoding == "DSD", "Expected encoding DSD, got \(playerStatus.quality.encoding)")
            XCTAssert(playerStatus.quality.channels == "Stereo", "Expected channels Stereo, got \(playerStatus.quality.channels)")
            
        default:
            print("Default")
        }
    }

    func testPlayerStatusQualityFloat() {
        // Given a mpd player
        let connectionProperties = [ConnectionProperties.Name.rawValue: "player",
                                    ConnectionProperties.Host.rawValue: "host",
                                    ConnectionProperties.Port.rawValue: 1000,
                                    ConnectionProperties.Password.rawValue: ""] as [String: Any]
        
        // When creating a new MPDStatus object and starting it twice
        let status = MPDStatus.init(mpd: mpdWrapper, connectionProperties: connectionProperties)
        status.start()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.mpdWrapper.songIndex = 3
            self.mpdWrapper.album = "Everything Now"
            self.mpdWrapper.artist = "Arcade Fire"
            self.mpdWrapper.songTitle = "Creature Comfort"
            self.mpdWrapper.queueVersion = 10
            self.mpdWrapper.queueLength = 15
            self.mpdWrapper.volume = 75
            self.mpdWrapper.random = true
            self.mpdWrapper.singleValue = true
            self.mpdWrapper.repeatValue = true
            self.mpdWrapper.songDuration = 330
            self.mpdWrapper.songIndex = 5
            self.mpdWrapper.state = MPD_STATE_PLAY
            self.mpdWrapper.samplerate = 192000
            self.mpdWrapper.encoding = UInt8(MPD_SAMPLE_FORMAT_FLOAT)
            self.mpdWrapper.channels = 2
            
            self.mpdWrapper.statusChanged()
        }
        
        // Then the statuses .online is reported once
        let playerStatuses = status.playerStatusObservable
            .toBlocking(timeout: 0.4)
            .materialize()
        
        switch playerStatuses {
        case .failed(let playerStatusArray, _):
            let playerStatus = playerStatusArray.last!
            
            XCTAssert(playerStatus.quality.encoding == "FLOAT", "Expected encoding FLOAT, got \(playerStatus.quality.encoding)")
            
        default:
            print("Default")
        }
    }
    
    func testPlayqueuSongs() {
        // Given a mpd player
        let connectionProperties = [ConnectionProperties.Name.rawValue: "player",
                                    ConnectionProperties.Host.rawValue: "host",
                                    ConnectionProperties.Port.rawValue: 1000,
                                    ConnectionProperties.Password.rawValue: ""] as [String: Any]
        
        mpdWrapper.songs = [["title": "t1", "album": "alb1", "artist": "art1"],
                            ["title": "t2", "album": "alb2", "artist": "art2"],
                            ["title": "t3", "album": "alb3", "artist": "art3"]]

        // When creating a new MPDStatus object and starting it twice
        let status = MPDStatus.init(mpd: mpdWrapper, connectionProperties: connectionProperties)
        
        // Get a range of 3 songs
        let songs = status.playqueueSongs(start: 2, end: 5)
        
        XCTAssert(songs.count == 3, "Expected 3 songs, got \(songs.count)")

        let songCount = self.mpdWrapper.callCount("run_current_song") +
            self.mpdWrapper.callCount("recv_song") - 1
        let songFreeCount = self.mpdWrapper.callCount("song_free")
        XCTAssert(songCount == songFreeCount, "Expected \(songCount) for songFreeCount, got \(songFreeCount)")
        mpdWrapper.assertCall("send_list_queue_range_meta", expectedParameters: ["start": "\(2)", "end": "\(5)"])
        XCTAssert(songCount == songFreeCount, "Expected \(songCount) for songFreeCount, got \(songFreeCount)")
    }
    
    func testEmptyRangePlayqueuSongs() {
        // Given a mpd player
        let connectionProperties = [ConnectionProperties.Name.rawValue: "player",
                                    ConnectionProperties.Host.rawValue: "host",
                                    ConnectionProperties.Port.rawValue: 1000,
                                    ConnectionProperties.Password.rawValue: ""] as [String: Any]
        
        let status = MPDStatus.init(mpd: mpdWrapper, connectionProperties: connectionProperties)
        
        // Get an empty list of songs
        let songs = status.playqueueSongs(start: 3, end: 3)
        
        XCTAssert(songs.count == 0, "Expected \(0) songs, got \(songs.count)")
    }

    func testInvalidRangePlayqueuSongs() {
        // Given a mpd player
        let connectionProperties = [ConnectionProperties.Name.rawValue: "player",
                                    ConnectionProperties.Host.rawValue: "host",
                                    ConnectionProperties.Port.rawValue: 1000,
                                    ConnectionProperties.Password.rawValue: ""] as [String: Any]
        
        // Get an invalid range of songs
        let status = MPDStatus.init(mpd: mpdWrapper, connectionProperties: connectionProperties)
        
        let songs = status.playqueueSongs(start: 5, end: 3)
        
        XCTAssert(songs.count == 0, "Expected \(0) songs, got \(songs.count)")
    }
}

