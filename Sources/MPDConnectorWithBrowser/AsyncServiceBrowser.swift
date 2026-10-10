//
//  AsyncServiceBrowser.swift
//  MPDConnector
//
//  Created by Berrie Kremers on 31/07/2025.
//

import Foundation

struct DiscoveredService {
    enum ChangeType {
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

class AsyncServiceBrowser: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private var continuation: AsyncStream<DiscoveredService.ChangeType>.Continuation?
    private var resolvingServices = [NetService]()
    private var discoveredServices = Set<NetService>()
    private var resolveAttempts = [NetService: Int]()
    private var isStopped = false
    private let resolveTimeout: TimeInterval = 5.0
    private let maxRetryDelay: TimeInterval = 30.0

    func discover(type: String, in domain: String = "") -> AsyncStream<DiscoveredService.ChangeType> {
        return AsyncStream { continuation in
            self.continuation = continuation
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
                return String(cString: hostname)
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
        continuation?.finish()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        continuation?.finish()
    }
}
