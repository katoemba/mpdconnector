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
import RxRelay
import ConnectorProtocol

public class MPDArtistBrowseViewModel: ArtistBrowseViewModel {
    private var loadProgress = BehaviorRelay<LoadProgress>(value: .notStarted)
    public var loadProgressObservable: Observable<LoadProgress> {
        get {
            return loadProgress.asObservable()
        }
    }
    
    private var _filters: [BrowseFilter]
    public var filters: [BrowseFilter] {
        get {
            return _filters
        }
    }
    
    private var bag = DisposeBag()
    private let _browse: MPDBrowse
    
    private var artistSectionsSubject = ReplaySubject<ArtistSections>.create(bufferSize: 1)
    public var artistSectionsObservable: Observable<ArtistSections> {
        return artistSectionsSubject.asObservable()
    }
    private var _artists: [Artist]? = nil
    
    public var artistType: ArtistType {
        get {
            var type = ArtistType.artist
            if let artists = _artists, artists.count > 0 {
                return artists[0].type
            }

            if let typeIndex = filters.firstIndex(where: { (filter) -> Bool in
                if case .type(_) = filter {
                    return true
                }
                return false
            }) {
                if case let .type(artistType) = filters[typeIndex] {
                    type = artistType
                }
            }
            return type
        }
    }
    
    init(browse: MPDBrowse, filters: [BrowseFilter] = [], artists: [Artist]? = nil) {
        _browse = browse
        _filters = filters
        _artists = artists
    }
    
    public func load(filters: [BrowseFilter]) {
        _filters = filters
        load()
    }
    
    public func load() {
        reload(type: artistType)
    }
    
    private func reload(type: ArtistType) {
        // Get rid of old disposables
        bag = DisposeBag()
        
        // Clear the contents
        loadProgress.accept(.loading)
        
        // Load new contents
        let browse = _browse
        var artistObservable: Observable<[Artist]>
        var multiSection: Bool
        
        if let artists = _artists {
            multiSection = false
            artistObservable = Observable.just(artists)
        }
        else {
            multiSection = true
            artistObservable = browse.fetchArtists(genre: nil, type: type)
                .observeOn(MainScheduler.instance)
                .share(replay: 1)
        }
        
        artistObservable
            .filter({ (artists) -> Bool in
                artists.count > 0
            })
            .map({ (artists) -> [(String, [Artist])] in
                guard multiSection == true else {
                    return [("", artists)]
                }
                
                let dict = Dictionary(grouping: artists, by: { artist -> String in
                    var firstLetter: String
                    
                    firstLetter = String(artist.sortName.prefix(1)).uppercased()
                    if "ABCDEFGHIJKLMNOPQRSTUVWXYZ".contains(firstLetter) == false {
                        firstLetter = "•"
                    }
                    return firstLetter
                })
                
                // Create an ordered array of LibraryItemsSections from the dictionary
                return dict.keys
                    .sorted()
                    .map({ (key) -> (String, [Artist]) in
                        return (key, dict[key]!.sorted(by: { (lhs, rhs) -> Bool in
                            return lhs.sortName.caseInsensitiveCompare(rhs.sortName) == .orderedAscending
                        }))
                    })
            })
            .map({ (sectionDictionary) -> ArtistSections in
                ObjectSections<Artist>(sectionDictionary, completeObjects: { (artists) -> Observable<[Artist]> in
                    if type == .artist || type == .albumArtist {
                        return browse.completeArtists(artists)
                    }
                    return Observable.just(artists)
                })
            })
            .subscribe(onNext: { [weak self] (objectSections) in
                self?.artistSectionsSubject.onNext(objectSections)
            })
            .disposed(by: bag)
        
        artistObservable
            .filter { (artists) -> Bool in
                artists.count == 0
            }
            .map { (_) -> LoadProgress in
                .noDataFound
            }
            .bind(to: loadProgress)
            .disposed(by: bag)
        
        artistObservable
            .filter({ (artists) -> Bool in
                artists.count > 0
            })
            .map { (_) -> LoadProgress in
                .allDataLoaded
            }
            .bind(to: loadProgress)
            .disposed(by: bag)
    }
}
