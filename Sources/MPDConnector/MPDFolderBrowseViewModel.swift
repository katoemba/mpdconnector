//
// MPDConnector
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

public class MPDFolderBrowseViewModel: FolderBrowseViewModel {
    private var _folderContentsSubject = PublishSubject<[FolderContent]>()
    public var folderContentsObservable: Observable<[FolderContent]> {
        get {
            return _folderContentsSubject.asObservable()
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
    private let _folderContents: [FolderContent]
    private let _parentFolder: Folder?
    public var parentFolder: Folder? {
        get {
            return _parentFolder
        }
    }
    
    public required init(browse: MPDBrowse, folderContents: [FolderContent] = [], parentFolder: Folder? = nil) {
        _browse = browse
        _folderContents = folderContents
        _parentFolder = parentFolder
    }
    
    public func load() {
        if _folderContents.count > 0 {
            loadProgress.accept(.allDataLoaded)
            bag = DisposeBag()
            _folderContentsSubject.onNext(_folderContents)
        }
        else {
            reload(parentFolder: _parentFolder)
        }
    }
    
    private func reload(parentFolder: Folder? = nil) {
        // Get rid of old disposables
        bag = DisposeBag()
        
        // Clear the contents
        _folderContentsSubject.onNext([])
        loadProgress.accept(.loading)
        
        // Load new contents
        let browse = _browse
        let folderContentsSubject = self._folderContentsSubject
        
        let folderContentsObservable = browse.fetchFolderContents(parentFolder: parentFolder)
            .observe(on: MainScheduler.instance)
            .share(replay: 1)
        
        folderContentsObservable
            .subscribe(onNext: { (folderContents) in
                folderContentsSubject.onNext(folderContents)
            })
            .disposed(by: bag)
        
        folderContentsObservable
            .filter({ (itemsFound) -> Bool in
                itemsFound.count > 0
            })
            .map { (_) -> LoadProgress in
                .allDataLoaded
            }
            .bind(to: loadProgress)
            .disposed(by: bag)
        
        folderContentsObservable
            .filter({ (itemsFound) -> Bool in
                itemsFound.count == 0
            })
            .map { (_) -> LoadProgress in
                .noDataFound
            }
            .bind(to: loadProgress)
            .disposed(by: bag)
    }
}
