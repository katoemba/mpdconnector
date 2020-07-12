//
//  MPDSongBrowseViewModel.swift
//  MPDConnector_iOS
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

import Foundation
import RxSwift
import RxRelay
import ConnectorProtocol

public class MPDSongBrowseViewModel: SongBrowseViewModel {
    private var songsSubject = BehaviorSubject<[Song]>(value: [])
    public var songsObservable: Observable<[Song]> {
        return songsSubject
    }
    public var songsWithSubfilterObservable: Observable<[Song]> {
        return songsObservable
            .map({ [weak self] (songs) -> [Song] in
                guard let weakSelf = self else { return songs }
                
                if let subFilter = weakSelf.subFilter, case let .artist(artist) = subFilter {
                    var filteredSongs = [Song]()
                    for song in songs {
                        if artist.type == .artist || artist.type == .albumArtist {
                            if song.albumartist.lowercased().contains(artist.name.lowercased()) || song.artist.lowercased().contains(artist.name.lowercased()) {
                                filteredSongs.append(song)
                            }
                        }
                        else if artist.type == .composer {
                            if song.composer.lowercased().contains(artist.name.lowercased()) {
                                filteredSongs.append(song)
                            }
                        }
                        else if artist.type == .performer {
                            if song.performer.lowercased().contains(artist.name.lowercased()) {
                                filteredSongs.append(song)
                            }
                        }
                    }
                    return filteredSongs
                }
                return songs
            })
    }
    private var loadProgress = BehaviorRelay<LoadProgress>(value: .notStarted)
    public var loadProgressObservable: Observable<LoadProgress> {
        get {
            return loadProgress.asObservable()
        }
    }

    public var filter: BrowseFilter? {
       return _filter
    }
    public var subFilter: BrowseFilter? {
       return _subFilter
    }

    private let bag = DisposeBag()
    private let _browse: MPDBrowse
    private let _songs: [Song]
    private let _filter: BrowseFilter?
    private let _subFilter: BrowseFilter?
    
    public required init(browse: MPDBrowse, songs: [Song] = [], filter: BrowseFilter? = nil, subFilter: BrowseFilter? = nil) {
        _browse = browse
        _songs = songs
        _filter = filter
        _subFilter = subFilter
    }
    
    public func load() {
        if _songs.count > 0 {
            loadProgress.accept(.allDataLoaded)
            songsSubject.onNext(_songs)
        }
        else if filter != nil {
            reload()
        }
        else {
            fatalError("MPDSongBrowseViewModel: load without filters not allowed")
        }
    }
    
    private func reload() {
        // Clear the contents
        songsSubject.onNext([])
        
        // Load new contents
        let browse = _browse
        
        let localSongsSubject = self.songsSubject
        switch filter! {
        case let .playlist(playlist):
            browse.songsInPlaylist(playlist)
                .observeOn(MainScheduler.instance)
                .subscribe(onNext: { (songs) in
                    localSongsSubject.onNext(songs)
                })
                .disposed(by: bag)
        case let .album(album):
            browse.songsOnAlbum(album)
                .map({ (songs) -> [Song] in
                    // If songs have track numbers, sort them by track number. Otherwise pass untouched.
                    if songs.count > 0, songs[0].track > 0 {
                        return songs.sorted(by: { (lsong, rsong) -> Bool in
                            if lsong.disc != rsong.disc {
                                return lsong.disc < rsong.disc
                            }
                            return lsong.track < rsong.track
                        })
                    }
                    return songs
                })
                .subscribe(onNext: { (songs) in
                    localSongsSubject.onNext(songs)
                })
                .disposed(by: bag)
        case let .random(count):
            browse.randomSongs(count: count)
                .subscribe(onNext: { (songs) in
                    localSongsSubject.onNext(songs)
                })
                .disposed(by: bag)
        default:
            fatalError("MPDSongBrowseViewModel: unsupported filter \(filter!)")
        }
        
        songsObservable
            .filter({ (itemsFound) -> Bool in
                itemsFound.count > 0
            })
            .map { (_) -> LoadProgress in
                .allDataLoaded
            }
            .bind(to: loadProgress)
            .disposed(by: bag)
        
        songsObservable
            .filter({ (itemsFound) -> Bool in
                itemsFound.count == 0
            })
            .map { (_) -> LoadProgress in
                .noDataFound
            }
            .bind(to: loadProgress)
            .disposed(by: bag)

    }
    
    public func extend() {
    }
    
    public func removeSong(at: Int) {
        let localSongsSubject = songsSubject
        Observable.just(at)
            .withLatestFrom(songsSubject) { (at, songs) in
                (at, songs)
            }
            .map({ (arg) -> [Song] in
                let (at, songs) = arg
                var newSongs = songs
                newSongs.remove(at: at)
                return newSongs
            })
            .subscribe(onNext: { (songs) in
                localSongsSubject.onNext(songs)
            })
            .disposed(by: bag)
    }
}
