//
//  NetServiceBrowser+Rx.swift
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
            .share(replay: 1)
    }
    
    public var serviceRemoved: Observable<NetService> {
        return delegate
            .methodInvoked(#selector(NetServiceBrowserDelegate.netServiceBrowser(_:didRemove:moreComing:)))
            .map { params in
                return params[1] as! NetService
            }
            .share(replay: 1)
    }
}
