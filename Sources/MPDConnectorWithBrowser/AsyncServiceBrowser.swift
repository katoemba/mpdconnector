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
}

class AsyncServiceBrowser: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private var continuation: AsyncStream<DiscoveredService.ChangeType>.Continuation?
    private var resolvingServices = [NetService]()
    private var discoveredServices = Set<NetService>()

    func discover(type: String, in domain: String = "") -> AsyncStream<DiscoveredService.ChangeType> {
        return AsyncStream { continuation in
            self.continuation = continuation
            self.browser.delegate = self
            self.browser.searchForServices(ofType: type, inDomain: domain)
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        if !discoveredServices.contains(service) {
            discoveredServices.insert(service)
            service.delegate = self
            resolvingServices.append(service)
            service.resolve(withTimeout: 5.0)
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        if discoveredServices.contains(service) {
            discoveredServices.remove(service)
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
            
            let result = DiscoveredService(
                name: service.name,
                type: service.type,
                domain: service.domain,
                service: service,
                ipAddresses: nil
            )
            continuation?.yield(.found(result))
        }
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        continuation?.finish()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        continuation?.finish()
    }
}
