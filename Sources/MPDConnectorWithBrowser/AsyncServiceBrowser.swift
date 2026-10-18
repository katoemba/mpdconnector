//
//  AsyncServiceBrowser.swift
//  MPDConnector
//
//  Created by Berrie Kremers on 31/07/2025.
//

import Foundation

/// `@unchecked Sendable`: the `NetService` is only ever used on the main thread, where the browser creates it,
/// and the other members are immutable values.
struct DiscoveredService: @unchecked Sendable {
    enum ChangeType: Sendable {
        case found(DiscoveredService)
        case removed(DiscoveredService)
    }
    
    let name: String
    let type: String
    let domain: String
    let service: NetService
    let ipAddresses: [String]?

    /// First resolved IPv4 address. IPv6 link-local addresses lack a scope id, so they are not usable for connecting.
    var ipv4Address: String? {
        ipAddresses?.first(where: { !$0.contains(":") })
    }
}

/// NetService calls its delegates on the run loop it is scheduled on, which is the main one: the browser is
/// started from the main actor.
@MainActor
final class AsyncServiceBrowser: NSObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    private var browser = NetServiceBrowser()
    private var continuation: AsyncStream<DiscoveredService.ChangeType>.Continuation?
    private var resolvingServices = [NetService]()
    private var discoveredServices = Set<NetService>()
    private var resolveAttempts = [NetService: Int]()
    private var isStopped = false
    private let resolveTimeout: TimeInterval = 5.0
    private let maxRetryDelay: TimeInterval = 30.0
    private var serviceType = ""
    private var serviceDomain = ""
    private var restartAttempts = 0
    private var isRestartPending = false

    func discover(type: String, in domain: String = "") -> AsyncStream<DiscoveredService.ChangeType> {
        return AsyncStream { continuation in
            self.continuation = continuation
            self.serviceType = type
            self.serviceDomain = domain
            self.browser.delegate = self
            self.browser.searchForServices(ofType: type, inDomain: domain)
        }
    }
    
    func stopListening() {
        isStopped = true
        browser.stop()
        for service in resolvingServices {
            service.stop()
        }
        resolvingServices.removeAll()
        resolveAttempts.removeAll()
        continuation?.finish()
    }
    
    deinit {
        print("deinit AsyncServiceBrowser")
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        restartAttempts = 0
        if !discoveredServices.contains(service) {
            discoveredServices.insert(service)
            service.delegate = self
            resolve(service)
        }
    }

    private func resolve(_ service: NetService) {
        resolvingServices.append(service)
        service.resolve(withTimeout: resolveTimeout)
    }

    /// A service that could not be resolved has no usable host or port, so it is not reported. Instead the
    /// resolve is retried with a growing delay for as long as the service remains visible.
    private func retryResolve(_ service: NetService) {
        guard !isStopped else { return }
        let attempt = (resolveAttempts[service] ?? 0) + 1
        resolveAttempts[service] = attempt
        let delay = min(Double(attempt) * 5.0, maxRetryDelay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.isStopped, self.discoveredServices.contains(service),
                  !self.resolvingServices.contains(service) else { return }
            self.resolve(service)
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        if discoveredServices.contains(service) {
            discoveredServices.remove(service)
            resolveAttempts.removeValue(forKey: service)
            if let index = resolvingServices.firstIndex(of: service) {
                resolvingServices.remove(at: index)
                service.stop()
            }
            let result = DiscoveredService(
                name: service.name,
                type: service.type,
                domain: service.domain,
                service: service,
                ipAddresses: nil
            )
            continuation?.yield(.removed(result))
        }
    }

    func netServiceDidResolveAddress(_ service: NetService) {
        if let index = resolvingServices.firstIndex(of: service) {
            resolvingServices.remove(at: index)
            resolveAttempts.removeValue(forKey: service)
            
            let ipAddresses = service.addresses?.compactMap { addressData -> String? in
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                addressData.withUnsafeBytes { pointer in
                    let sockaddr = pointer.baseAddress?.assumingMemoryBound(to: sockaddr.self)
                    getnameinfo(sockaddr, socklen_t(addressData.count), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                }
                return String(decoding: hostname.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
            
            let result = DiscoveredService(
                name: service.name,
                type: service.type,
                domain: service.domain,
                service: service,
                ipAddresses: ipAddresses
            )
            continuation?.yield(.found(result))
        }
    }
    
    func netService(_ service: NetService, didNotResolve errorDict: [String: NSNumber]) {
        if let index = resolvingServices.firstIndex(of: service) {
            resolvingServices.remove(at: index)
            retryResolve(service)
        }
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        searchEnded(browser)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        searchEnded(browser)
    }

    /// A search can end without being asked to, for example when mDNSResponder restarts or the network goes away.
    /// Nothing would be found for the rest of the session, so search again, with a growing delay while it keeps
    /// failing. What was found before is reported as removed: it is reported again when the new search finds it.
    private func searchEnded(_ endedBrowser: NetServiceBrowser) {
        guard !isStopped else {
            continuation?.finish()
            return
        }
        guard endedBrowser === browser, !isRestartPending else { return }

        for service in resolvingServices {
            service.stop()
        }
        resolvingServices.removeAll()
        resolveAttempts.removeAll()
        for service in discoveredServices {
            continuation?.yield(.removed(DiscoveredService(name: service.name,
                                                           type: service.type,
                                                           domain: service.domain,
                                                           service: service,
                                                           ipAddresses: nil)))
        }
        discoveredServices.removeAll()

        restartAttempts += 1
        isRestartPending = true
        let delay = min(Double(restartAttempts) * 5.0, maxRetryDelay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.isRestartPending = false
            guard !self.isStopped else { return }
            let browser = NetServiceBrowser()
            browser.delegate = self
            self.browser = browser
            browser.searchForServices(ofType: self.serviceType, inDomain: self.serviceDomain)
        }
    }
}
