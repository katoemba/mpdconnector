//
//  MPDAlbumBrowseViewModel.swift
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

public class MPDAlbumBrowseViewModel: AlbumBrowseViewModel {
    private var albumsSubject = BehaviorSubject<[Album]>(value: [])
    private var numberOfItems = BehaviorRelay<Int>(value: 0)
    public var albumsObservable: Observable<[Album]> {
        get {
            return albumsSubject.observe(on: MainScheduler.asyncInstance)
        }
    }
    private var loadProgress = BehaviorRelay<LoadProgress>(value: .notStarted)
    public var loadProgressObservable: Observable<LoadProgress> {
        get {
            return loadProgress.observe(on: MainScheduler.asyncInstance)
        }
    }
    
    public private(set) var filters: [BrowseFilter]
    public private(set) var sort = SortType.artist
    public var availableSortOptions: [SortType] {
        get {
            if albums.count > 0 {
                return []
            }
            else if filters.count > 0, case .artist(_) = filters[0] {
                return [.title, .year, .yearReverse]
            }
            else if filters.count > 0, case .genre(_) = filters[0] {
                return [.artist, .title, .year, .yearReverse]
            }
            else {
                return [.artist, .title, .year, .yearReverse]
            }
        }
    }

    private let extendTriggerSubject = PublishSubject<Int>()
    private var bag = DisposeBag()
    private var extendSize = 60
    private let browse: MPDBrowse
    private let albums: [Album]
    
    init(browse: MPDBrowse, albums: [Album] = [], filters: [BrowseFilter] = []) {
        self.browse = browse
        self.albums = albums
        self.filters = filters
    }
    
    public func load(sort: SortType) {
        self.sort = sort
        load()
    }
    
    public func load(filters: [BrowseFilter]) {
        self.filters = filters
        load()
    }
    
    private func load() {
        if albums.count > 0 {
            loadProgress.accept(.allDataLoaded)
            bag = DisposeBag()
            albumsSubject.onNext(albums)
        }
        else if filters.count > 0 {
            switch filters[0] {
            case let .genre(genre):
                reload(genre: genre, sort: sort)
            case let .artist(artist):
                reload(artist: artist, sort: sort)
            case let .related(album):
                reload(album: album, sort: sort)
            case let .recent(numberOfAlbums):
                reload(recent: numberOfAlbums, sort: sort)
            case let .random(count):
                reload(random: count, sort: sort)
            default:
                fatalError("MPDAlbumBrowseViewModel: unsupported filter type")
            }
        }
        else {
            reload(sort: sort)
        }
    }
    
    private func reload(genre: Genre? = nil, artist: Artist? = nil, album: Album? = nil, recent: Int? = nil, random: Int? = nil, sort: SortType) {
        // Get rid of old disposables
        bag = DisposeBag()
        
        // Clear the contents
        albumsSubject.onNext([])
        loadProgress.accept(.loading)

        // Load new contents
        let browse = self.browse
        let albumsSubject = self.albumsSubject
        var albumsObservable : Observable<[Album]>
        
        if let artist = artist {
            self.extendSize = 60
            albumsObservable = browse.albumsByArtist(artist, sort: sort)
                .share(replay: 1)
        }
        else if let album = album {
            self.extendSize = 60
            albumsObservable = browse.albumsByArtist(Artist(id: album.artist, source: album.source, name: album.artist), sort: sort)
                .map {
                    $0.filter { $0 != album }
                }
                .share(replay: 1)
        }
        else if let recent = recent {
            self.extendSize = 200
            albumsObservable = browse.fetchRecentAlbums(numberOfAlbums: recent)
                .share(replay: 1)
        }
        else if let random = random {
            self.extendSize = random
            albumsObservable = browse.fetchAlbums(genre: nil, sort: sort)
                .flatMap { (albums) -> Observable<[Album]> in
                    var randomAlbums = [Album]()
                    for _ in 1...random {
                        if let album = albums.randomElement() {
                            randomAlbums.append(album)
                        }
                    }
                    return Observable.just(randomAlbums)
                }
                .share(replay: 1)
        }
        else {
            self.extendSize = 60
            albumsObservable = browse.fetchAlbums(genre: genre, sort: sort)
                .share(replay: 1)
        }
        
        let extendSize = self.extendSize
        let extendTriggerObservable = extendTriggerSubject.asObservable()
            .scan(-extendSize) { seed, next in
                seed + next
            }
            .map({ (start) -> (Int, Int) in
                (start, extendSize)
            })
        
        let startLoadObservable = Observable.combineLatest(albumsObservable, extendTriggerObservable)
            .filter({ (albums, arg) -> Bool in
                let (start, count) = arg
                return start < min(start+count, albums.count)
            })
        
        albumsObservable
            .map { (_) -> LoadProgress in
                .loading
            }
            .bind(to: loadProgress)
            .disposed(by: bag)
        
        let dataAvailableObservable = startLoadObservable
            .flatMap({ (albums, arg) -> Observable<[Album]> in
                let (start, count) = arg
                return browse.completeAlbums(Array(albums[start..<min(start+count, albums.count)]))
            })
            .scan([]) { inputAlbums, newAlbums in
                inputAlbums + newAlbums
            }
            .share(replay: 1)
            
        dataAvailableObservable
            .distinctUntilChanged()
            .subscribe(onNext: { (albums) in
                albumsSubject.onNext(albums)
            })
            .disposed(by: bag)
        
        dataAvailableObservable
            .map { (_) -> LoadProgress in
                .dataAvailable
            }
            .bind(to: loadProgress)
            .disposed(by: bag)
        
        let endReachedObservable = startLoadObservable
            .map { (albums, arg) -> Bool in
                let (start, count) = arg
                return start+count >= albums.count
            }
        
        albumsObservable
            .filter { (albums) -> Bool in
                albums.count == 0
            }
            .map { (_) -> LoadProgress in
                .noDataFound
            }
            .bind(to: loadProgress)
            .disposed(by: bag)

        Observable.combineLatest(dataAvailableObservable, endReachedObservable)
            .filter { (_, end) -> Bool in
                end
            }
            .map { (_) -> LoadProgress in
                .allDataLoaded
            }
            .bind(to: loadProgress)
            .disposed(by: bag)

        extendTriggerObservable
            .map { (start, extendSize) -> Int in
                start + extendSize
            }
            .bind(to: numberOfItems)
            .disposed(by: bag)
        
        // Trigger a first load
        extend()
    }
    
    public func extend() {
        extendTriggerSubject.onNext(extendSize)
    }

    public func prefetch(to: Int) {
        if to > numberOfItems.value {
            extendTriggerSubject.onNext(extendSize)
        }
    }
}
