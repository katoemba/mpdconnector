//
//  NetServiceBrowser+Rx.swift
//  MPDConnector_iOS
//
//  Created by Berrie Kremers on 24-09-17.
//  Copyright © 2017 Katoemba Software. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa

extension NetServiceBrowser: HasDelegate {
    public typealias Delegate = NetServiceBrowserDelegate
}

public class RxNetServiceBrowserDelegateProxy
    : DelegateProxy<NetServiceBrowser, NetServiceBrowserDelegate>
    , DelegateProxyType
    , NetServiceBrowserDelegate {
    
    /// Typed parent object.
    public weak private(set) var netServiceBrowser: NetServiceBrowser?
    
    /// - parameter pickerView: Parent object for delegate proxy.
    public init(netServiceBrowser: ParentObject) {
        self.netServiceBrowser = netServiceBrowser
        super.init(parentObject: netServiceBrowser, delegateProxy: RxNetServiceBrowserDelegateProxy.self)
    }
    
    // Register known implementationss
    public static func registerKnownImplementations() {
        self.register { RxNetServiceBrowserDelegateProxy(netServiceBrowser: $0) }
    }
}

extension Reactive where Base: NetServiceBrowser {
    public var delegate: DelegateProxy<NetServiceBrowser, NetServiceBrowserDelegate> {
        return RxNetServiceBrowserDelegateProxy.proxy(for: base)
    }
    
    /// Installs delegate as forwarding delegate on `delegate`.
    /// Delegate won't be retained.
    ///
    /// It enables using normal delegate mechanism with reactive delegate mechanism.
    ///
    /// - parameter delegate: Delegate object.
    /// - returns: Disposable object that can be used to unbind the delegate.
    public func setDelegate(_ delegate: NetServiceBrowserDelegate)
        -> Disposable {
            return RxNetServiceBrowserDelegateProxy.installForwardDelegate(delegate, retainDelegate: false, onProxyForObject: self.base)
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
