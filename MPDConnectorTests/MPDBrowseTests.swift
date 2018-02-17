//
//  MPDBrowseTests.swift
//  MPDConnectorTests
//
//  Created by Berrie Kremers on 16-02-18.
//  Copyright © 2018 Kaotemba Software. All rights reserved.
//

import XCTest
import ConnectorProtocol
import MPDConnector
import libmpdclient
import RxSwift
import RxTest

class MPDBrowseTests: XCTestCase {
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
        mpdPlayer = MPDPlayer.init(mpd: mpdWrapper, name: "player", host: "localhost", port: 6600, password: "", scheduler: nil)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
        
        if self.mpdPlayer != nil {
            self.mpdPlayer = nil
        }
    }
    
    func testSongsOnAlbum() {
        var album = Album()
        album.title = "Album 1"
        album.artist = "Artist 2"
        
        mpdWrapper.songs = [["title": "t1", "album": "alb1", "artist": "art1"],
                            ["title": "t2", "album": "alb2", "artist": "art2"],
                            ["title": "t3", "album": "alb3", "artist": "art3"],
                            ["title": "t4", "album": "alb4", "artist": "art4"],
                            ["title": "t5", "album": "alb5", "artist": "art5"]]

        let songResults = mpdPlayer?.browse.songsOnAlbum(album)
            .toBlocking(timeout: 0.8)
            .materialize()
        
        switch songResults {
        case .completed(let songOnNext)?:
            let songs = songOnNext[0]
            XCTAssert(songs.count == 5, "Expected 5 songs, got \(songs.count)")
        default:
            XCTAssert(false, "songsOnAlbum failed")
        }
        
        self.mpdWrapper.assertCall("search_db_songs", expectedParameters: ["exact": "\(true)"])
        self.mpdWrapper.assertCall("search_add_tag_constraint", callInstance: 0, expectedParameters: ["tagType": "\(MPD_TAG_ALBUM)", "value": "Album 1"])
        self.mpdWrapper.assertCall("search_add_tag_constraint", callInstance: 1, expectedParameters: ["tagType": "\(MPD_TAG_ARTIST)", "value": "Artist 2"])
        self.mpdWrapper.assertCall("search_commit")
        self.mpdWrapper.assertCall("connection_free")

        let songCount = self.mpdWrapper.callCount("get_song")
        let songFreeCount = self.mpdWrapper.callCount("song_free")
        XCTAssert(songCount - 1 == songFreeCount, "Expected \(songCount - 1) for songFreeCount, got \(songFreeCount)")
    }

    func testSongsByArtist() {
        var artist = Artist()
        artist.name = "An Artist"
        
        mpdWrapper.songs = [["title": "t1", "album": "alb1", "artist": "art1"],
                            ["title": "t2", "album": "alb2", "artist": "art2"],
                            ["title": "t3", "album": "alb3", "artist": "art3"],
                            ["title": "t4", "album": "alb4", "artist": "art4"],
                            ["title": "t5", "album": "alb5", "artist": "art5"],
                            ["title": "t6", "album": "alb6", "artist": "art6"],
                            ["title": "t7", "album": "alb7", "artist": "art7"]]

        let songResults = mpdPlayer?.browse.songsByArtist(artist)
            .toBlocking(timeout: 0.8)
            .materialize()

        switch songResults {
        case .completed(let songOnNext)?:
            let songs = songOnNext[0]
            XCTAssert(songs.count == 7, "Expected 7 songs, got \(songs.count)")
        default:
            XCTAssert(false, "songsByArtist failed")
        }

        self.mpdWrapper.assertCall("search_db_songs", expectedParameters: ["exact": "\(true)"])
        self.mpdWrapper.assertCall("search_add_tag_constraint", callInstance: 0, expectedParameters: ["tagType": "\(MPD_TAG_ARTIST)", "value": "An Artist"])
        self.mpdWrapper.assertCall("search_commit")
        self.mpdWrapper.assertCall("connection_free")
        
        let songCount = self.mpdWrapper.callCount("get_song")
        let songFreeCount = self.mpdWrapper.callCount("song_free")
        XCTAssert(songCount - 1 == songFreeCount, "Expected \(songCount - 1) for songFreeCount, got \(songFreeCount)")
    }

    func testAlbumsByArtist() {
        var artist = Artist()
        artist.name = "art1"
        
        mpdWrapper.songs = [["title": "t1", "album": "alb1", "artist": "art1"],
                            ["title": "t2", "album": "alb2", "artist": "art1"],
                            ["title": "t3", "album": "alb3", "artist": "art1"],
                            ["title": "t4", "album": "alb2", "artist": "art1"],
                            ["title": "t5", "album": "alb1", "artist": "art1"],
                            ["title": "t6", "album": "alb2", "artist": "art1"],
                            ["title": "t7", "album": "alb2", "artist": "art1"]]
        
        let albumResults = mpdPlayer?.browse.albumsByArtist(artist)
            .toBlocking(timeout: 0.8)
            .materialize()
        
        switch albumResults {
        case .completed(let albumOnNext)?:
            let albums = albumOnNext[0]
            XCTAssert(albums.count == 3, "Expected 3 albums, got \(albums.count)")
        default:
            XCTAssert(false, "albumsByArtist failed")
        }
        
        self.mpdWrapper.assertCall("search_db_songs", expectedParameters: ["exact": "\(true)"])
        self.mpdWrapper.assertCall("search_add_tag_constraint", callInstance: 0, expectedParameters: ["tagType": "\(MPD_TAG_ALBUM_ARTIST)", "value": "art1"])
        self.mpdWrapper.assertCall("search_commit")
        self.mpdWrapper.assertCall("connection_free")
        
        let songCount = self.mpdWrapper.callCount("get_song")
        let songFreeCount = self.mpdWrapper.callCount("song_free")
        XCTAssert(songCount - 1 == songFreeCount, "Expected \(songCount - 1) for songFreeCount, got \(songFreeCount)")
    }

    func testAlbumsOnWhichArtistAppears() {
        var artist = Artist()
        artist.name = "art1"
        
        mpdWrapper.songs = [["title": "t1", "album": "alb1", "artist": "art1"],
                            ["title": "t2", "album": "alb2", "artist": "art1"],
                            ["title": "t4", "album": "alb2", "artist": "art1"],
                            ["title": "t5", "album": "alb1", "artist": "art1"],
                            ["title": "t6", "album": "alb2", "artist": "art1"],
                            ["title": "t7", "album": "alb2", "artist": "art1"]]
        
        let albumResults = mpdPlayer?.browse.albumsOnWhichArtistAppears(artist)
            .toBlocking(timeout: 0.8)
            .materialize()
        
        switch albumResults {
        case .completed(let albumOnNext)?:
            let albums = albumOnNext[0]
            XCTAssert(albums.count == 2, "Expected 2 albums, got \(albums.count)")
        default:
            XCTAssert(false, "albumsOnWhichArtistAppears failed")
        }
        
        self.mpdWrapper.assertCall("search_db_songs", expectedParameters: ["exact": "\(true)"])
        self.mpdWrapper.assertCall("search_add_tag_constraint", callInstance: 0, expectedParameters: ["tagType": "\(MPD_TAG_ARTIST)", "value": "art1"])
        self.mpdWrapper.assertCall("search_commit")
        self.mpdWrapper.assertCall("connection_free")
        
        let songCount = self.mpdWrapper.callCount("get_song")
        let songFreeCount = self.mpdWrapper.callCount("song_free")
        XCTAssert(songCount - 1 == songFreeCount, "Expected \(songCount - 1) for songFreeCount, got \(songFreeCount)")
    }
}

