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
    private var _playlists = Variable<[Playlist]>([])
    public var playlistsObservable: Driver<[Playlist]> {
        get {
            return _playlists.asDriver()
        }
    }
    
    private var bag = DisposeBag()
    private let _browse: MPDBrowse
    private let _providedPlaylists: [Playlist]
    
    deinit {
        print("Cleanup MPDPlaylistBrowseViewModel")
    }
    
    public required init(browse: MPDBrowse, playlists: [Playlist] = []) {
        _browse = browse
        _providedPlaylists = playlists
    }
    
    public func load() {
        if _providedPlaylists.count > 0 {
            bag = DisposeBag()
            _playlists.value = _providedPlaylists
        }
        else {
            reload()
        }
    }
    
    private func reload() {
        // Get rid of old disposables
        bag = DisposeBag()
        
        // Clear the contents
        _playlists.value = []
        
        // Load new contents
        let browse = _browse
        let playlists = self._playlists
        let playlistsObservable = browse.fetchPlaylists()
        
        playlistsObservable
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { (foundPlaylists) in
                playlists.value = foundPlaylists
            })
            .disposed(by: bag)
    }
    
    public func extend() {
    }
    
    public func renamePlaylist(_ playlist: Playlist, to: String) -> Playlist {
        var renamedPlaylist = playlist
        renamedPlaylist.id = to
        renamedPlaylist.name = to
        
        if let index = _playlists.value.index(of: playlist), _playlists.value.contains(renamedPlaylist) == false {
            _browse.renamePlaylist(playlist, newName: to)
            
            _playlists.value[index] = renamedPlaylist
            return renamedPlaylist
        }
        
        return playlist
    }
    
    public func deletePlaylist(_ playlist: Playlist) {
        if let index = _playlists.value.index(of: playlist) {
            _browse.deletePlaylist(playlist)
            
            _playlists.value.remove(at: index)
        }
    }
}
