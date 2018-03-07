//
//  MPDPlaylistBrowseViewModel.swift
//  MPDConnector_iOS
//
//  Created by Berrie Kremers on 04-03-18.
//  Copyright © 2018 Kaotemba Software. All rights reserved.
//

import Foundation
import RxSwift
import RxCocoa
import ConnectorProtocol

public class MPDPlaylistBrowseViewModel: PlaylistBrowseViewModel {
    private var _playlistsSubject = PublishSubject<[Playlist]>()
    public var playlistsObservable: Driver<[Playlist]> {
        get {
            return _playlistsSubject.asDriver(onErrorJustReturn: [])
        }
    }
    
    private var bag = DisposeBag()
    private let _browse: MPDBrowse
    private let _playlists: [Playlist]
    
    deinit {
        print("Cleanup MPDPlaylistBrowseViewModel")
    }
    
    public required init(browse: MPDBrowse, playlists: [Playlist] = []) {
        _browse = browse
        _playlists = playlists
    }
    
    public func load() {
        if _playlists.count > 0 {
            bag = DisposeBag()
            _playlistsSubject.onNext(_playlists)
        }
        else {
            reload()
        }
    }
    
    private func reload() {
        // Get rid of old disposables
        bag = DisposeBag()
        
        // Clear the contents
        _playlistsSubject.onNext([])
        
        // Load new contents
        let browse = _browse
        let playlistsSubject = self._playlistsSubject
        let playlistsObservable = browse.fetchPlaylists()
        
        playlistsObservable
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { (playlists) in
                playlistsSubject.onNext(playlists)
            })
            .disposed(by: bag)
    }
    
    public func extend() {
    }
}
