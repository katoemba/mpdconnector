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
import RxCocoa
import ConnectorProtocol

public class MPDSongBrowseViewModel: SongBrowseViewModel {
    private var _songsSubject = BehaviorSubject<[Song]>(value: [])
    public var songsObservable: Observable<[Song]> {
        get {
            return _songsSubject.asObservable()
        }
    }
    private var loadProgress = BehaviorRelay<LoadProgress>(value: .notStarted)
    public var loadProgressObservable: Observable<LoadProgress> {
        get {
            return loadProgress.asObservable()
        }
    }

    public var filters: [BrowseFilter] {
        get {
            return _filters
        }
    }
    
    private var bag = DisposeBag()
    private let _browse: MPDBrowse
    private let _songs: [Song]
    private let _filters: [BrowseFilter]
    
    deinit {
        print("Cleanup MPDSongBrowseViewModel")
    }
    
    public required init(browse: MPDBrowse, songs: [Song] = [], filters: [BrowseFilter] = []) {
        _browse = browse
        _songs = songs
        _filters = filters
    }
    
    public func load() {
        if _songs.count > 0 {
            loadProgress.accept(.allDataLoaded)
            bag = DisposeBag()
            _songsSubject.onNext(_songs)
        }
        else if filters.count > 0 {
            reload(filter: filters[0])
        }
        else {
            fatalError("MPDSongBrowseViewModel: load without filters not allowed")
        }
    }
    
    private func reload(filter: BrowseFilter) {
        // Get rid of old disposables
        bag = DisposeBag()
        
        // Clear the contents
        _songsSubject.onNext([])
        
        // Load new contents
        let browse = _browse
        let songsSubject = self._songsSubject
        var songsObservable : Observable<[Song]>
        switch filter {
        case let .playlist(playlist):
            songsObservable = browse.songsInPlaylist(playlist)
                .observeOn(MainScheduler.instance)
                .share(replay: 1)
        case let .album(album):
            songsObservable = browse.songsOnAlbum(album)
                .map({ (songs) -> [Song] in
                    // If songs have track numbers, sort them by track number. Otherwise pass untouched.
                    if songs.count > 0, songs[0].track > 0 {
                        return songs.sorted(by: { (lsong, rsong) -> Bool in
                            lsong.track < rsong.track
                        })
                    }
                    return songs
                })
                .observeOn(MainScheduler.instance)
                .share(replay: 1)
        case let .random(count):
            songsObservable = browse.randomSongs(count: count)
                .observeOn(MainScheduler.instance)
                .share(replay: 1)
        default:
            fatalError("MPDSongBrowseViewModel: load without filters not allowed")
        }
        
        songsObservable
            .subscribe(onNext: { (songs) in
                songsSubject.onNext(songs)
            })
            .disposed(by: bag)
        
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
        Observable.just(at)
            .withLatestFrom(_songsSubject) { (at, songs) in
                (at, songs)
            }
            .map({ (arg) -> [Song] in
                let (at, songs) = arg
                var newSongs = songs
                newSongs.remove(at: at)
                return newSongs
            })
            .subscribe(onNext: { [weak self] (songs) in
                guard let weakSelf = self else { return }
                weakSelf._songsSubject.onNext(songs)
            })
            .disposed(by: bag)
    }
}
