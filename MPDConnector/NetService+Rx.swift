//
//  RxNetService.swift
//  MPDConnector_iOS
//
//  Created by Berrie Kremers on 24-09-17.
//  Copyright © 2017 Kaotemba Software. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa

public class RxNetServiceDelegateProxy
    : DelegateProxy
    , NetServiceDelegate
    , DelegateProxyType {
    
    /// For more information take a look at `DelegateProxyType`.
    public class func currentDelegateFor(_ object: AnyObject) -> AnyObject? {
        let netService: NetService = object as! NetService
        return netService.delegate
    }
    
    /// For more information take a look at `DelegateProxyType`.
    public class func setCurrentDelegate(_ delegate: AnyObject?, toObject object: AnyObject) {
        let netService: NetService = object as! NetService
        netService.delegate = delegate as? NetServiceDelegate
    }
    
    /// For more information take a look at `DelegateProxyType`.
    public override class func createProxyForObject(_ object: AnyObject) -> AnyObject {
        let netService: NetService = object as! NetService
        return netService.createRxDelegateProxy()
    }
}

extension NetService {
    /// Factory method that enables subclasses to implement their own `delegate`.
    ///
    /// - returns: Instance of delegate proxy that wraps `delegate`.
    public func createRxDelegateProxy() -> RxNetServiceDelegateProxy {
        return RxNetServiceDelegateProxy(parentObject: self)
    }
    
}

extension Reactive where Base: NetService {
    public var delegate: DelegateProxy {
        return RxNetServiceDelegateProxy.proxyForObject(base)
    }
    
    public var didResolveAddress: Observable<NetService> {
        return delegate
            .methodInvoked(#selector(NetServiceDelegate.netServiceDidResolveAddress(_:)))
            .map { params in
                return params[0] as! NetService                
            }
    }

    public func resolve(withTimeout timeout: TimeInterval) -> Observable<NetService> {
        let netService = self.base as NetService
        netService.resolve(withTimeout: timeout)
        return didResolveAddress.filter {
                $0 == self.base
            }
    }
}
