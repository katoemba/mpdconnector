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
    public var albumsObservable: Driver<[Album]> {
        get {
            return _albumsSubject.asDriver(onErrorJustReturn: [])
        }
    }
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
    private let _filters: [BrowseFilter]
    
    deinit {
        print("Cleanup MPDAlbumBrowseViewModel")
    }
    
    public required init(browse: MPDBrowse, albums: [Album] = [], filters: [BrowseFilter] = []) {
        _browse = browse
        _albums = albums
        _filters = filters
    }
    
    public func load(sort: SortType) {
        _sort = sort
        
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
            }
        }
        else {
            reload(sort: sort)
        }
    }
    
    private func reload(genre: String? = nil, artist: Artist? = nil, sort: SortType) {
        // Get rid of old disposables
        bag = DisposeBag()
        
        // Clear the contents
        _albumsSubject.onNext([])
        
        // Load new contents
        let browse = _browse
        let extendSize = self.extendSize
        let albumsSubject = self._albumsSubject
        let albumsObservable = artist != nil ? browse.albumsByArtist(artist!) : browse.fetchAlbums(genre: genre, sort: sort)
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
        
        // Trigger a first load
        extend()
    }
    
    public func extend() {
        extendTriggerSubject.onNext(extendSize)
    }
}
