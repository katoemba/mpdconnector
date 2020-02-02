//
//  MPDGenreBrowseViewModel.swift
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

public class MPDGenreBrowseViewModel: GenreBrowseViewModel {
    private var _genresSubject = PublishSubject<[Genre]>()
    public var genresObservable: Observable<[Genre]> {
        get {
            return _genresSubject.asObservable()
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
    private let _genres: [Genre]
    public var parentGenre: Genre?

    public required init(browse: MPDBrowse, genres: [Genre] = [], parentGenre: Genre? = nil) {
        if parentGenre != nil {
            print("Warning: parentGenre not supported on MPD")
        }
        
        _browse = browse
        _genres = genres
    }
    
    public func load() {
        if _genres.count > 0 {
            loadProgress.accept(.allDataLoaded)
            bag = DisposeBag()
            _genresSubject.onNext(_genres)
        }
        else {
            reload()
        }
    }
    
    private func reload() {
        // Get rid of old disposables
        bag = DisposeBag()
        
        // Clear the contents
        _genresSubject.onNext([])
        loadProgress.accept(.loading)

        // Load new contents
        let browse = _browse
        let genresSubject = self._genresSubject
        
        let genresObservable = browse.fetchGenres()
            .observeOn(MainScheduler.instance)
            .share(replay: 1)

        genresObservable
            .subscribe(onNext: { (genres) in
                genresSubject.onNext(genres)
            })
            .disposed(by: bag)
        
        genresObservable
            .filter({ (itemsFound) -> Bool in
                itemsFound.count > 0
            })
            .map { (_) -> LoadProgress in
                .allDataLoaded
            }
            .bind(to: loadProgress)
            .disposed(by: bag)
        
        genresObservable
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
