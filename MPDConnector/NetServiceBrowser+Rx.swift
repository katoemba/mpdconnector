//
//  NetServiceBrowser+Rx.swift
//  MPDConnector_iOS
//
//  Created by Berrie Kremers on 24-09-17.
//  Copyright © 2017 Kaotemba Software. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa

public class RxNetServiceBrowserDelegateProxy
    : DelegateProxy
    , NetServiceBrowserDelegate
    , DelegateProxyType {
    
    /// For more information take a look at `DelegateProxyType`.
    public static func currentDelegateFor(_ object: AnyObject) -> AnyObject? {
        let netServiceBrowser: NetServiceBrowser = object as! NetServiceBrowser
        return netServiceBrowser.delegate
    }
    
    /// For more information take a look at `DelegateProxyType`.
    public static func setCurrentDelegate(_ delegate: AnyObject?, toObject object: AnyObject) {
        let netServiceBrowser: NetServiceBrowser = object as! NetServiceBrowser
        netServiceBrowser.delegate = delegate as? NetServiceBrowserDelegate
    }
    
    /// For more information take a look at `DelegateProxyType`.
    public override class func createProxyForObject(_ object: AnyObject) -> AnyObject {
        let netServiceBrowser: NetServiceBrowser = object as! NetServiceBrowser
        return netServiceBrowser.createRxDelegateProxy()
    }

}

extension NetServiceBrowser {
    /// Factory method that enables subclasses to implement their own `delegate`.
    ///
    /// - returns: Instance of delegate proxy that wraps `delegate`.
    public func createRxDelegateProxy() -> RxNetServiceBrowserDelegateProxy {
        return RxNetServiceBrowserDelegateProxy(parentObject: self)
    }
}

extension Reactive where Base: NetServiceBrowser {
    public var delegate: DelegateProxy {
        return RxNetServiceBrowserDelegateProxy.proxyForObject(base)
    }
    
    public var serviceAdded: Observable<NetService> {
        return delegate
            .methodInvoked(#selector(NetServiceBrowserDelegate.netServiceBrowser(_:didFind:moreComing:)))
            .flatMap { (params) -> Observable<NetService> in
                let netService = params[1] as! NetService                
                return netService.rx.resolve(withTimeout: 5)
            }
    }
    
    public var serviceRemoved: Observable<NetService> {
        return delegate
            .methodInvoked(#selector(NetServiceBrowserDelegate.netServiceBrowser(_:didRemove:moreComing:)))
            .map { params in
                return params[1] as! NetService
            }
    }
}
