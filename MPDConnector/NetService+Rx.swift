//
//  RxNetService.swift
//  MPDConnector_iOS
//
//  Created by Berrie Kremers on 24-09-17.
//  Copyright © 2017 Katoemba Software. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa

extension NetService: HasDelegate {
    public typealias Delegate = NetServiceDelegate
}

public class RxNetServiceDelegateProxy
    : DelegateProxy<NetService, NetServiceDelegate>
    , DelegateProxyType
    , NetServiceDelegate {
    
    /// Typed parent object.
    public weak private(set) var netService: NetService?
    
    /// - parameter pickerView: Parent object for delegate proxy.
    public init(netService: ParentObject) {
        self.netService = netService
        super.init(parentObject: netService, delegateProxy: RxNetServiceDelegateProxy.self)
    }
    
    // Register known implementationss
    public static func registerKnownImplementations() {
        self.register { RxNetServiceDelegateProxy(netService: $0) }
    }
}

extension Reactive where Base: NetService {
    public var delegate: DelegateProxy<NetService, NetServiceDelegate> {
        return RxNetServiceDelegateProxy.proxy(for: base)
    }
    
    /// Installs delegate as forwarding delegate on `delegate`.
    /// Delegate won't be retained.
    ///
    /// It enables using normal delegate mechanism with reactive delegate mechanism.
    ///
    /// - parameter delegate: Delegate object.
    /// - returns: Disposable object that can be used to unbind the delegate.
    public func setDelegate(_ delegate: NetServiceDelegate)
        -> Disposable {
            return RxNetServiceDelegateProxy.installForwardDelegate(delegate, retainDelegate: false, onProxyForObject: self.base)
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
