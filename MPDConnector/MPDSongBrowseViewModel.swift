//
//  MPDSongBrowseViewModel.swift
//  MPDConnector_iOS
//
//  Created by Berrie Kremers on 04-03-18.
//  Copyright © 2018 Kaotemba Software. All rights reserved.
//

import Foundation
import RxSwift
import RxCocoa
import ConnectorProtocol

public class MPDSongBrowseViewModel: SongBrowseViewModel {
    private var _songsSubject = PublishSubject<[Song]>()
    public var songsObservable: Driver<[Song]> {
        get {
            return _songsSubject.asDriver(onErrorJustReturn: [])
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
        case let .album(album):
            songsObservable = browse.songsOnAlbum(album)
        default:
            fatalError("MPDSongBrowseViewModel: load without filters not allowed")
        }
        
        songsObservable
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { (songs) in
                songsSubject.onNext(songs)
            })
            .disposed(by: bag)
    }
    
    public func extend() {
    }
}
