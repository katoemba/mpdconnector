//
//  MPDAlbumSectionBrowseViewModel.swift
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

public class MPDAlbumSectionBrowseViewModel: AlbumSectionBrowseViewModel {
    private var loadProgress = BehaviorRelay<LoadProgress>(value: .notStarted)
    public var loadProgressObservable: Observable<LoadProgress> {
        get {
            return loadProgress.asObservable()
        }
    }
    
    private var _sort = SortType.artist
    public var sort: SortType {
        get {
            return _sort
        }
    }
    public var availableSortOptions: [SortType] {
        return [.artist, .title, .year, .yearReverse]
    }
    
    private var bag = DisposeBag()
    private let _browse: MPDBrowse
    
    private var albumSectionsSubject = ReplaySubject<AlbumSections>.create(bufferSize: 1)
    public var albumSectionsObservable: Observable<AlbumSections> {
        return albumSectionsSubject.asObservable()
    }
    
    init(browse: MPDBrowse) {
        _browse = browse
    }
    
    public func load(sort: SortType) {
        _sort = sort
        reload(sort: sort)
    }
    
    private func reload(sort: SortType) {
        // Get rid of old disposables
        bag = DisposeBag()
        
        // Clear the contents
        loadProgress.accept(.loading)
        
        // Load new contents
        let browse = _browse
        let albumsObservable = browse.fetchAlbums(genre: nil, sort: sort)
            .observeOn(MainScheduler.instance)
            .share(replay: 1)
        
        albumsObservable
            .filter({ (albums) -> Bool in
                albums.count > 0
            })
            .map({ (albums) -> [(String, [Album])] in
                let dict = Dictionary(grouping: albums, by: { album -> String in
                    var firstLetter: String
                    
                    if sort == .year || sort == .yearReverse {
                        return "\(album.year)"
                    }
                    if sort == .artist {
                        firstLetter = String(album.sortArtist.prefix(1)).uppercased()
                    }
                    else {
                        firstLetter = String(album.title.prefix(1)).uppercased()
                    }
                    if "ABCDEFGHIJKLMNOPQRSTUVWXYZ".contains(firstLetter) == false {
                        firstLetter = "•"
                    }
                    return firstLetter
                })
                
                // Create an ordered array of LibraryItemsSections from the dictionary
                var sortedKeys = dict.keys.sorted()
                if sort == .yearReverse {
                    sortedKeys = sortedKeys.reversed()
                }
                return sortedKeys.map({ (key) -> (String, [Album]) in
                    (key, dict[key]!)
                })
            })
            .map({ (sectionDictionary) -> AlbumSections in
                AlbumSections(sectionDictionary, completeObjects: { (albums) -> Observable<[Album]> in
                    browse.completeAlbums(albums)
                })
            })
            .subscribe(onNext: { [weak self] (objectSections) in
                self?.albumSectionsSubject.onNext(objectSections)
            })
            .disposed(by: bag)
        
        albumsObservable
            .filter { (albums) -> Bool in
                albums.count == 0
            }
            .map { (_) -> LoadProgress in
                .noDataFound
            }
            .bind(to: loadProgress)
            .disposed(by: bag)
        
        albumsObservable
            .filter({ (albums) -> Bool in
                albums.count > 0
            })
            .map { (_) -> LoadProgress in
                .allDataLoaded
            }
            .bind(to: loadProgress)
            .disposed(by: bag)
    }
}

