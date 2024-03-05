//
//  MPDBrowseTests.swift
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
        mpdPlayer = MPDPlayer.init(mpd: mpdWrapper, name: "player", host: "localhost", ipAddress: "127.0.0.1", port: 6600, scheduler: nil, userDefaults: UserDefaults.standard)
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
        album.title = "alb1"
        album.artist = "art1"
        
        mpdWrapper.songs = [["title": "t1", "album": "alb1", "artist": "art1", "albumartist": "art1"],
                            ["title": "t2", "album": "alb1", "artist": "art1", "albumartist": "art1"],
                            ["title": "t3", "album": "alb2", "artist": "art2", "albumartist": "various"],
                            ["title": "t4", "album": "alb2", "artist": "art3", "albumartist": "various"],
                            ["title": "t5", "album": "alb2", "artist": "art4", "albumartist": "various"]]

        let songResults = mpdPlayer?.browse.songsOnAlbum(album)
            .toBlocking(timeout: 0.8)
            .materialize()
        
        switch songResults {
        case .completed(let songOnNext)?:
            let songs = songOnNext[0]
            XCTAssert(songs.count > 0, "Expected some songs, got \(songs.count)")
        default:
            XCTAssert(false, "songsOnAlbum failed")
        }
        
        self.mpdWrapper.assertCall("search_db_songs", expectedCallCount: 2, expectedParameters: ["exact": "\(true)"])
        self.mpdWrapper.assertCall("search_add_tag_constraint", expectedCallCount: 0, expectedParameters: ["tagType": "\(MPD_TAG_ALBUM)", "value": "alb1"])
        self.mpdWrapper.assertCall("search_add_tag_constraint", expectedCallCount: 1, expectedParameters: ["tagType": "\(MPD_TAG_ARTIST)", "value": "art1"])
        self.mpdWrapper.assertCall("search_add_tag_constraint", expectedCallCount: 1, expectedParameters: ["tagType": "\(MPD_TAG_ALBUM_ARTIST)", "value": "art1"])
        self.mpdWrapper.assertCall("search_commit", expectedCallCount: 2)
        self.mpdWrapper.assertCall("connection_free")

        let songCount = self.mpdWrapper.callCount("recv_song")
        let songFreeCount = self.mpdWrapper.callCount("song_free")
        let searchCount = self.mpdWrapper.callCount("search_db_songs")
        XCTAssert(songCount - searchCount == songFreeCount, "Expected \(songCount - searchCount) for songFreeCount, got \(songFreeCount)")
    }

    func testSongsByArtist() {
        var artist = Artist()
        artist.name = "art1"
        
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
            XCTAssert(songs.count > 0, "Expected some songs, got \(songs.count)")
        default:
            XCTAssert(false, "songsByArtist failed")
        }

        self.mpdWrapper.assertCall("search_db_songs", expectedCallCount: 3, expectedParameters: ["exact": "\(true)"])
        self.mpdWrapper.assertCall("search_add_tag_constraint", expectedCallCount: 1, expectedParameters: ["tagType": "\(MPD_TAG_ALBUM)", "value": "*"])
        self.mpdWrapper.assertCall("search_add_tag_constraint", expectedCallCount: 1, expectedParameters: ["tagType": "\(MPD_TAG_ARTIST)", "value": "art1"])
        self.mpdWrapper.assertCall("search_add_tag_constraint", expectedCallCount: 1, expectedParameters: ["tagType": "\(MPD_TAG_ALBUM_ARTIST)", "value": "art1"])
        self.mpdWrapper.assertCall("search_commit", expectedCallCount: 3)
        self.mpdWrapper.assertCall("connection_free")

        let songCount = self.mpdWrapper.callCount("recv_song")
        let songFreeCount = self.mpdWrapper.callCount("song_free")
        let searchCount = self.mpdWrapper.callCount("search_db_songs")
        XCTAssert(songCount - searchCount == songFreeCount, "Expected \(songCount - searchCount) for songFreeCount, got \(songFreeCount)")
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
        
        let albumResults = mpdPlayer?.browse.albumsByArtist(artist, sort: .artist)
            .toBlocking(timeout: 0.8)
            .materialize()
        
        switch albumResults {
        case .completed(let albumOnNext)?:
            let albums = albumOnNext[0]
            XCTAssert(albums.count > 0, "Expected some albums, got \(albums.count)")
        default:
            XCTAssert(false, "albumsByArtist failed")
        }
        
        self.mpdWrapper.assertCall("search_db_songs", expectedCallCount: 3, expectedParameters: ["exact": "\(true)"])
        self.mpdWrapper.assertCall("search_add_tag_constraint", expectedCallCount: 1, expectedParameters: ["tagType": "\(MPD_TAG_ALBUM)", "value": "*"])
        self.mpdWrapper.assertCall("search_add_tag_constraint", expectedCallCount: 1, expectedParameters: ["tagType": "\(MPD_TAG_ARTIST)", "value": "art1"])
        self.mpdWrapper.assertCall("search_add_tag_constraint", expectedCallCount: 1, expectedParameters: ["tagType": "\(MPD_TAG_ALBUM_ARTIST)", "value": "art1"])
        self.mpdWrapper.assertCall("search_commit", expectedCallCount: 3)
        self.mpdWrapper.assertCall("connection_free")

        let songCount = self.mpdWrapper.callCount("recv_song")
        let songFreeCount = self.mpdWrapper.callCount("song_free")
        let searchCount = self.mpdWrapper.callCount("search_db_songs")
        XCTAssert(songCount - searchCount == songFreeCount, "Expected \(songCount - searchCount) for songFreeCount, got \(songFreeCount)")
    }
    
    func testDeletePlaylist() {
        mpdPlayer = MPDPlayer.init(mpd: mpdWrapper, name: "player", host: "localhost", ipAddress: "127.0.0.1", port: 6600, scheduler: testScheduler, userDefaults: UserDefaults.standard)

        let playlist = Playlist(id: "Playlist1", source: .Local, name: "PlaylistName", lastModified: Date(timeIntervalSince1970: 10000))
        testScheduler.scheduleAt(50) {
            let browse = self.mpdPlayer?.browse as! MPDBrowse
            let model = browse.playlistBrowseViewModel([playlist])
            model.load()
            model.deletePlaylist(playlist)
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_rm", expectedParameters: ["name": "Playlist1"])

            let connectCount = self.mpdWrapper.callCount("connection_new")
            let freeCount = self.mpdWrapper.callCount("connection_free")
            XCTAssert(connectCount == freeCount, "connectCount: \(connectCount) != freeCount: \(freeCount)")
        }
        
        testScheduler.start()
    }

    func testRenamePlaylist() {
        mpdPlayer = MPDPlayer.init(mpd: mpdWrapper, name: "player", host: "localhost", ipAddress: "127.0.0.1", port: 6600, scheduler: testScheduler, userDefaults: UserDefaults.standard)
        
        let playlist = Playlist(id: "Playlist1", source: .Local, name: "PlaylistName", lastModified: Date(timeIntervalSince1970: 10000))
        testScheduler.scheduleAt(50) {
            let browse = self.mpdPlayer?.browse as! MPDBrowse
            let model = browse.playlistBrowseViewModel([playlist])
            model.load()
            
            let playlist = model.renamePlaylist(playlist, to: "Newbie")
            XCTAssert(playlist.id == "Newbie", "Expected id Newbie, got \(playlist.id)")
            XCTAssert(playlist.name == "Newbie", "Expected name Newbie, got \(playlist.name)")
        }
        testScheduler.scheduleAt(100) {
            self.mpdWrapper.assertCall("run_rename", expectedParameters: ["from": "Playlist1", "to": "Newbie"])

            let connectCount = self.mpdWrapper.callCount("connection_new")
            let freeCount = self.mpdWrapper.callCount("connection_free")
            XCTAssert(connectCount == freeCount, "connectCount: \(connectCount) != freeCount: \(freeCount)")
        }

        testScheduler.start()
    }
    
    func testPlaylists() {
        mpdWrapper.playlists = [["id": "id1", "name": "name1"],
                                ["id": "id2", "name": "name2"],
                                ["id": "id3", "name": "name3"]]

        let browseViewModel = mpdPlayer?.browse.playlistBrowseViewModel()
        browseViewModel!.load()
        let playlistResult = browseViewModel!.playlistsObservable
            .toBlocking(timeout: 0.8)
            .materialize()

        switch playlistResult {
        case .failed(let playlistOnNext, let error):
            if error.localizedDescription == RxError.timeout.localizedDescription {
                let playlists = playlistOnNext.last
                XCTAssert(playlists!.count == 3, "Expected 3 songs, got \(playlists!.count)")
            }
            else {
                XCTAssert(false, "getting playlists failed \(error)")
            }
        default:
            XCTAssert(false, "getting playlists failed")
        }

        self.mpdWrapper.assertCall("send_list_playlists", expectedCallCount: 1)
        let connectCount = self.mpdWrapper.callCount("connection_new")
        let freeCount = self.mpdWrapper.callCount("connection_free")
        XCTAssert(connectCount == freeCount, "connectCount: \(connectCount) != freeCount: \(freeCount)")
        
        let playlistCount = self.mpdWrapper.callCount("recv_playlist")
        let playlistFreeCount = self.mpdWrapper.callCount("playlist_free")
        let fetchCount = self.mpdWrapper.callCount("send_list_playlists")
        XCTAssert(playlistCount - fetchCount == playlistFreeCount, "Expected \(playlistCount - fetchCount) for playlistFreeCount, got \(playlistFreeCount)")
    }

    func testFolder() {
        mpdWrapper.entities = [MPD_ENTITY_TYPE_SONG, MPD_ENTITY_TYPE_PLAYLIST, MPD_ENTITY_TYPE_DIRECTORY, MPD_ENTITY_TYPE_SONG, MPD_ENTITY_TYPE_DIRECTORY, MPD_ENTITY_TYPE_SONG]
        mpdWrapper.songs = [["title": "t1", "album": "alb1", "artist": "art1"],
                            ["title": "t2", "album": "alb2", "artist": "art1"],
                            ["title": "t3", "album": "alb3", "artist": "art1"]]
        mpdWrapper.playlists = [["id": "id1", "name": "name1"]]
        mpdWrapper.directories = [["path": "/abc/def"],
                                  ["path": "/abc/hij"]]
        mpdWrapper.songDuration = 10
        
        let browseViewModel = mpdPlayer?.browse.folderContentsBrowseViewModel(Folder.init(id: "FolderID", source: .Local, path: "FolderPath", name: "FolderName"))
        browseViewModel!.load()
        let folderContentsResult = browseViewModel!.folderContentsObservable
            .toBlocking(timeout: 0.8)
            .materialize()
        
        switch folderContentsResult {
        case .failed(let folderContentsOnNext, let error):
            if error.localizedDescription == RxError.timeout.localizedDescription {
                let folderContents = folderContentsOnNext.last
                XCTAssert(folderContents!.count == 6, "Expected 6 items, got \(folderContents!.count)")

                var songCount = 0
                var playlistCount = 0
                var folderCount = 0
                for folderContent in folderContents! {
                    if case .song(_) = folderContent {
                        songCount = songCount + 1
                    }
                    else if case .playlist(_) = folderContent {
                        playlistCount = playlistCount + 1
                    }
                    else if case .folder(_) = folderContent {
                        folderCount = folderCount + 1
                    }
                }
                
                XCTAssert(songCount == 3, "Expected 3 songs, got \(songCount)")
                XCTAssert(playlistCount == 1, "Expected 1 playlist, got \(playlistCount)")
                XCTAssert(folderCount == 2, "Expected 2 folders, got \(folderCount)")
            }
            else {
                XCTAssert(false, "getting folderContents failed \(error)")
            }
        default:
            XCTAssert(false, "getting folderContents failed")
        }
        
        self.mpdWrapper.assertCall("send_list_meta", expectedCallCount: 1)
        let connectCount = self.mpdWrapper.callCount("connection_new")
        let freeCount = self.mpdWrapper.callCount("connection_free")
        XCTAssert(connectCount == freeCount, "connectCount: \(connectCount) != freeCount: \(freeCount)")
        
        let entityCount = self.mpdWrapper.callCount("recv_entity")
        let entityFreeCount = self.mpdWrapper.callCount("entity_free")
        let fetchCount = self.mpdWrapper.callCount("send_list_meta")
        XCTAssert(entityCount - fetchCount == entityFreeCount, "Expected \(entityCount - fetchCount) for playlistFreeCount, got \(entityFreeCount)")
    }
    
    func testAvailableTagTypes() {
        mpdWrapper.tagTypes = ["AlbumArtist", "Title"]
        
        let tagTypeResult = (mpdPlayer?.browse as! MPDBrowse).availableTagTypes()
            .toBlocking(timeout: 0.8)
            .materialize()
        
        switch tagTypeResult {
        case .completed(let tagTypesOnNext):
            let tagTypes = tagTypesOnNext[0]
            XCTAssert(tagTypes.count == 2, "Expected 2 tagTypes, got \(tagTypes.count)")
            XCTAssert(tagTypes[0] == "AlbumArtist", "Expected first tagType=AlbumArtist, got \(tagTypes[0])")
            XCTAssert(tagTypes[1] == "Title", "Expected second tagType=Title, got \(tagTypes[1])")
        default:
            XCTAssert(false, "getting tagTypes failed")
        }
        
        self.mpdWrapper.assertCall("send_list_tag_types", expectedCallCount: 1)
        self.mpdWrapper.assertCall("recv_tag_type_pair", expectedCallCount: 3)
    }

    func testAvailableCommands() {
        mpdWrapper.pairs = [("command", "albumart"), ("command", "play")]
        
        let commandsResult = (mpdPlayer?.browse as! MPDBrowse).availableCommands()
            .toBlocking(timeout: 0.8)
            .materialize()
        
        switch commandsResult {
        case .completed(let commandsOnNext):
            let commands = commandsOnNext[0]
            XCTAssert(commands.count == 2, "Expected 2 commands, got \(commands.count)")
            XCTAssert(commands[0] == "albumart", "Expected first command=albumart, got \(commands[0])")
            XCTAssert(commands[1] == "play", "Expected second command=play, got \(commands[1])")
        default:
            XCTAssert(false, "getting commands failed")
        }
        
        self.mpdWrapper.assertCall("send_allowed_commands", expectedCallCount: 1)
        self.mpdWrapper.assertCall("recv_pair_named", expectedCallCount: 3)
    }
}

