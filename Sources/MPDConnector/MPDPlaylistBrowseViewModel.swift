//
//  MPDPlaylistBrowseViewModel.swift
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

public class MPDPlaylistBrowseViewModel: PlaylistBrowseViewModel {
    private var _playlists = BehaviorRelay<[Playlist]>(value: [])
    public var playlistsObservable: Observable<[Playlist]> {
        get {
            return _playlists.asObservable()
        }
    }
    private var loadProgress = BehaviorRelay<LoadProgress>(value: .notStarted)
    public var loadProgressObservable: Observable<LoadProgress> {
        get {
            return loadProgress.asObservable()
        }
    }

    private var bag = DisposeBag()
    private let _browse: MPDBrowse
    private let _providedPlaylists: [Playlist]
    
    public required init(browse: MPDBrowse, playlists: [Playlist] = []) {
        _browse = browse
        _providedPlaylists = playlists
    }
    
    public func load() {
        if _providedPlaylists.count > 0 {
            loadProgress.accept(.allDataLoaded)
            bag = DisposeBag()
            _playlists.accept(_providedPlaylists)
        }
        else {
            reload()
        }
    }
    
    private func reload() {
        // Get rid of old disposables
        bag = DisposeBag()
        
        // Clear the contents
        _playlists.accept([])
        loadProgress.accept(.loading)

        // Load new contents
        let browse = _browse
        let playlists = self._playlists
        let playlistsObservable = browse.fetchPlaylists()
            .observe(on: MainScheduler.instance)
            .share(replay: 1)
        
        playlistsObservable
            .observe(on: MainScheduler.instance)
            .bind(to: playlists)
            .disposed(by: bag)
        
        playlistsObservable
            .filter({ (itemsFound) -> Bool in
                itemsFound.count > 0
            })
            .map { (_) -> LoadProgress in
                .allDataLoaded
            }
            .bind(to: loadProgress)
            .disposed(by: bag)
        
        playlistsObservable
            .filter({ (itemsFound) -> Bool in
                itemsFound.count == 0
            })
            .map { (_) -> LoadProgress in
                .noDataFound
            }
            .bind(to: loadProgress)
            .disposed(by: bag)
    }
    
    public func renamePlaylist(_ playlist: Playlist, to: String) -> Playlist {
        var renamedPlaylist = playlist
        renamedPlaylist.id = to
        renamedPlaylist.name = to
        
        if let index = _playlists.value.firstIndex(of: playlist), _playlists.value.contains(renamedPlaylist) == false {
            _browse.renamePlaylist(playlist, newName: to)
            
            _playlists.take(1)
                .map { (playlists) -> [Playlist] in
                    var updatedPlaylists = playlists
                    updatedPlaylists[index] = renamedPlaylist
                    return updatedPlaylists
                }
                .bind(to: _playlists)
                .disposed(by: bag)
            return renamedPlaylist
        }
        
        return playlist
    }
    
    public func deletePlaylist(_ playlist: Playlist) {
        if let index = _playlists.value.firstIndex(of: playlist) {
            _browse.deletePlaylist(playlist)
            
            _playlists.take(1)
                .map { (playlists) -> [Playlist] in
                    var updatedPlaylists = playlists
                    updatedPlaylists.remove(at: index)
                    return updatedPlaylists
                }
                .bind(to: _playlists)
                .disposed(by: bag)
        }
    }
}
