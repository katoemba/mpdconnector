//
//  MPDGenreBrowseViewModel.swift
//  MPDConnector_iOS
//
//  Created by Berrie Kremers on 20-03-18.
//  Copyright © 2018 Kaotemba Software. All rights reserved.
//

import Foundation
import RxSwift
import RxCocoa
import ConnectorProtocol

public class MPDGenreBrowseViewModel: GenreBrowseViewModel {
    private var _genresSubject = PublishSubject<[String]>()
    public var genresObservable: Driver<[String]> {
        get {
            return _genresSubject.asDriver(onErrorJustReturn: [])
        }
    }
    
    private var bag = DisposeBag()
    private let _browse: MPDBrowse
    private let _genres: [String]
    
    deinit {
        print("Cleanup MPDGenreBrowseViewModel")
    }
    
    public required init(browse: MPDBrowse, genres: [String] = []) {
        _browse = browse
        _genres = genres
    }
    
    public func load() {
        if _genres.count > 0 {
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
        
        // Load new contents
        let browse = _browse
        let genresSubject = self._genresSubject
        
        browse.fetchGenres()
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { (genres) in
                genresSubject.onNext(genres)
            })
            .disposed(by: bag)
    }
    
    public func extend() {
    }
}
