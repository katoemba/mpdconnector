//
//  MPDArtistBrowseViewModel.swift
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

public class MPDArtistBrowseViewModel: ArtistBrowseViewModel {
    private var _artistsSubject = PublishSubject<[Artist]>()
    public var artistsObservable: Observable<[Artist]> {
        get {
            return _artistsSubject.asObservable()
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
    private let _artists: [Artist]
    private let _filters: [BrowseFilter]
    
    deinit {
        print("Cleanup MPDArtistBrowseViewModel")
    }
    
    public required init(browse: MPDBrowse, artists: [Artist] = [], filters: [BrowseFilter] = []) {
        _browse = browse
        _artists = artists
        _filters = filters
    }
    
    public func load() {
        if _artists.count > 0 {
            loadProgress.accept(.allDataLoaded)
            bag = DisposeBag()
            _artistsSubject.onNext(_artists)
        }
        else if filters.count > 0 {
            switch filters[0] {
            case let .genre(genre):
                reload(genre: genre)
            default:
                reload()
            }
        }
        else {
            reload()
        }
    }
    
    private func reload(genre: String? = nil) {
        // Get rid of old disposables
        bag = DisposeBag()
        
        // Clear the contents
        _artistsSubject.onNext([])
        loadProgress.accept(.loading)

        // Load new contents
        let browse = _browse
        let artistsSubject = self._artistsSubject
        let artistsObservable = browse.fetchArtists(genre: genre)
            .observeOn(MainScheduler.instance)
            .share(replay: 1)
            
        artistsObservable
            .subscribe(onNext: { (artists) in
                artistsSubject.onNext(artists)
            })
            .disposed(by: bag)
        
        artistsObservable
            .filter({ (itemsFound) -> Bool in
                itemsFound.count > 0
            })
            .map { (_) -> LoadProgress in
                .allDataLoaded
            }
            .bind(to: loadProgress)
            .disposed(by: bag)

        artistsObservable
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
}
