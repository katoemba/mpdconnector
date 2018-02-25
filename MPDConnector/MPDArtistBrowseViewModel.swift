//
//  MPDArtistBrowseViewModel.swift
//  MPDConnector_iOS
//
//  Created by Berrie Kremers on 25-02-18.
//  Copyright © 2018 Katoemba Software. All rights reserved.
//

import Foundation
import RxSwift
import RxCocoa
import ConnectorProtocol

public class MPDArtistBrowseViewModel: ArtistBrowseViewModel {
    private var _artistsSubject = PublishSubject<[Artist]>()
    public var artistsObservable: Driver<[Artist]> {
        get {
            return _artistsSubject.asDriver(onErrorJustReturn: [])
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
        
        // Load new contents
        let browse = _browse
        let artistsSubject = self._artistsSubject
        let artistsObservable = browse.fetchArtists(genre: genre)

        artistsObservable
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { (artists) in
                artistsSubject.onNext(artists)
            })
            .disposed(by: bag)
    }
    
    public func extend() {
    }
}
