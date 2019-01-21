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
import ConnectorProtocol

public class MPDAlbumSections: AlbumSections {
    private class AlbumTuple {
        var loadStatus: LoadStatus
        var albumSubject: BehaviorSubject<Album>
        var album: Album
        
        init(loadStatus: LoadStatus, album: Album) {
            self.loadStatus = loadStatus
            self.albumSubject = BehaviorSubject<Album>(value: album)
            self.album = album
        }
    }
    
    private var albumTuples = [[AlbumTuple]]()
    private var _sectionTitles = [String]()
    public var sectionTitles: [String] {
        return _sectionTitles
    }

    private var bag = DisposeBag()
    private let browse: MPDBrowse?
    
    public var numberOfSections: Int {
        return albumTuples.count
    }
    
    //public var albumTuples
    
    public func rowsInSection(_ section: Int) -> Int {
        guard section < albumTuples.count else { return 0 }
        
        return albumTuples[section].count
    }
    
    deinit {
        print("Cleanup MPDAlbumSections")
    }
    
    init(_ sectionDictionary: [(String, [Album])], browse: MPDBrowse?) {
        self.browse = browse
        for albumSection in sectionDictionary {
            var section = [AlbumTuple]()
            for album in albumSection.1 {
                section.append(AlbumTuple(loadStatus: .initial, album: album))
            }
            albumTuples.append(section)
            _sectionTitles.append(albumSection.0)
        }
    }
    
    private func nextIndexPathDown(_ indexPath: IndexPath) -> IndexPath? {
        if indexPath.row > 0 {
            return IndexPath(row: indexPath.row - 1, section: indexPath.section)
        }
        else if indexPath.section > 0 {
            return IndexPath(row: albumTuples[indexPath.section - 1].count - 1, section: indexPath.section - 1)
        }
        else {
            return nil
        }
    }

    private func nextIndexPathUp(_ indexPath: IndexPath) -> IndexPath? {
        if indexPath.row < albumTuples[indexPath.section].count - 1 {
            return IndexPath(row: indexPath.row + 1, section: indexPath.section)
        }
        else if indexPath.section < albumTuples.count - 1 {
            return IndexPath(row: 0, section: indexPath.section + 1)
        }
        else {
            return nil
        }
    }
    
    public func getAlbumObservable(indexPath: IndexPath) -> Observable<Album> {
        guard let browse = browse,
            indexPath.section < albumTuples.count,
            indexPath.row < albumTuples[indexPath.section].count else { return Observable.empty() }
        
        let tuple = albumTuples[indexPath.section][indexPath.row]
        if tuple.loadStatus != .initial {
            return tuple.albumSubject
        }
        
        var albumIndexes = [String: IndexPath]()
        tuple.loadStatus = .completionInProgress
        
        var albumsToFetch = [tuple.album]
        var indexPathDown: IndexPath? = indexPath
        for _ in 0..<30 {
            indexPathDown = nextIndexPathDown(indexPathDown!)
            if indexPathDown == nil {
                break
            }
            
            let downTuple = albumTuples[indexPathDown!.section][indexPathDown!.row]
            if downTuple.loadStatus == .initial {
                albumsToFetch.append(downTuple.album)
                downTuple.loadStatus = .completionInProgress
            }
        }
        var indexPathUp: IndexPath? = indexPath
        for _ in 0..<30 {
            indexPathUp = nextIndexPathUp(indexPathUp!)
            if indexPathUp == nil {
                break
            }
            
            let upTuple = albumTuples[indexPathUp!.section][indexPathUp!.row]
            if upTuple.loadStatus == .initial {
                albumsToFetch.append(upTuple.album)
                upTuple.loadStatus = .completionInProgress
            }
        }

        browse
            .completeAlbums(albumsToFetch)
            .subscribe(onNext: { [weak self] (albums) in
                guard let weakSelf = self else { return }

                for album in albums {
                    if let indexPath = albumIndexes[album.id],
                        indexPath.section < weakSelf.albumTuples.count,
                        indexPath.row < weakSelf.albumTuples[indexPath.section].count {
                        let tuple = weakSelf.albumTuples[indexPath.section][indexPath.row]
                        tuple.loadStatus = .complete
                        tuple.album = album
                        tuple.albumSubject.onNext(album)
                    }
                }
            })
            .disposed(by: bag)

        return tuple.albumSubject
    }
}
