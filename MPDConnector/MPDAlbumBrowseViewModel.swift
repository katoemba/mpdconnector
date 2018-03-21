//
//  MPDAlbumBrowseViewModel.swift
//  MPDConnector_iOS
//
//  Created by Berrie Kremers on 20-02-18.
//  Copyright © 2018 Katoemba Software. All rights reserved.
//

import Foundation
import RxSwift
import RxCocoa
import ConnectorProtocol

public class MPDAlbumBrowseViewModel: AlbumBrowseViewModel {
    private var _albumsSubject = PublishSubject<[Album]>()
    private var numberOfItems = BehaviorRelay<Int>(value: 0)
    public var albumsObservable: Driver<[Album]> {
        get {
            return _albumsSubject.asDriver(onErrorJustReturn: [])
        }
    }
    private var _filters = [BrowseFilter]([])
    public var filters: [BrowseFilter] {
        get {
            return _filters
        }
    }
    private var _sort = SortType.artist
    public var sort: SortType {
        get {
            return _sort
        }
    }
    public var availableSortOptions: [SortType] {
        get {
            if _albums.count > 0 {
                return []
            }
            else if filters.count > 0, case .artist(_) = filters[0] {
                return []
            }
            else if filters.count > 0, case .genre(_) = filters[0] {
                return []
            }
            else {
                return [.artist, .year, .yearReverse]
            }
        }
    }

    private let extendTriggerSubject = PublishSubject<Int>()
    private var bag = DisposeBag()
    private var extendSize = 30
    private let _browse: MPDBrowse
    private let _albums: [Album]
    
    deinit {
        print("Cleanup MPDAlbumBrowseViewModel")
    }
    
    init(browse: MPDBrowse, albums: [Album] = [], filters: [BrowseFilter] = []) {
        _browse = browse
        _albums = albums
        _filters = filters
    }
    
    public func load(sort: SortType) {
        _sort = sort
        load()
    }
    
    public func load(filters: [BrowseFilter]) {
        _filters = filters
        load()
    }
    
    private func load() {
        if _albums.count > 0 {
            bag = DisposeBag()
            _albumsSubject.onNext(_albums)
        }
        else if filters.count > 0 {
            switch filters[0] {
            case let .genre(genre):
                reload(genre: genre, sort: sort)
            case let .artist(artist):
                reload(artist: artist, sort: sort)
            case let .recent(duration):
                reload(recent: duration, sort: sort)
            default:
                fatalError("MPDAlbumBrowseViewModel: unsupported filter type")
            }
        }
        else {
            reload(sort: sort)
        }
    }
    
    private func reload(genre: String? = nil, artist: Artist? = nil, recent: Int? = nil, sort: SortType) {
        // Get rid of old disposables
        bag = DisposeBag()
        
        // Clear the contents
        _albumsSubject.onNext([])
        
        // Load new contents
        let browse = _browse
        let albumsSubject = self._albumsSubject
        var albumsObservable : Observable<[Album]>
        
        if let artist = artist {
            self.extendSize = 30
            albumsObservable = browse.albumsByArtist(artist)
        }
        else if let recent = recent {
            self.extendSize = 200
            albumsObservable = browse.fetchRecentAlbums(numberOfDays: recent)
        }
        else {
            self.extendSize = 30
            albumsObservable = browse.fetchAlbums(genre: genre, sort: sort)
        }
        
        let extendSize = self.extendSize
        let extendTriggerObservable = extendTriggerSubject.asObservable()
            .scan(-extendSize) { seed, next in
                seed + next
            }
            .map({ (start) -> (Int, Int) in
                (start, extendSize)
            })
        
        Observable.combineLatest(albumsObservable, extendTriggerObservable)
            .filter({ (albums, arg) -> Bool in
                let (start, count) = arg
                return start < min(start+count, albums.count)
            })
            .flatMap({ (albums, arg) -> Observable<[Album]> in
                let (start, count) = arg
                
                return browse.completeAlbums(Array(albums[start..<min(start+count, albums.count)]))
            })
            .scan([]) { inputAlbums, newAlbums in
                inputAlbums + newAlbums
            }
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { (albums) in
                albumsSubject.onNext(albums)
            })
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

    public func extend(to: Int) {
        if to > numberOfItems.value {
            extendTriggerSubject.onNext(extendSize)
        }
    }
}
