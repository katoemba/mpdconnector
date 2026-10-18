import XCTest
import Network
import ConnectorProtocol
@testable import MPDConnector
@testable import MPDConnectorWithBrowser

/// The state handler of a listener is called more than once; a continuation may only be resumed once.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed {
            return false
        }
        claimed = true
        return true
    }
}

/// Just enough of an MPD server for a player to see that something is there: it sends the greeting that
/// carries the version, and answers every command with an empty "OK".
private final class FakeMPDServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "FakeMPDServer")
    private var connections: [NWConnection] = []
    /// Like a slow or busy server: it takes a while before it greets a new connection.
    var greetingDelay: TimeInterval = 0

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
    }

    func start() async throws -> Int {
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.connections.append(connection)
            connection.start(queue: self.queue)
            self.queue.asyncAfter(deadline: .now() + self.greetingDelay) {
                connection.send(content: Data("OK MPD 0.23.5\n".utf8), completion: .contentProcessed { _ in })
                self.receive(on: connection)
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            let resumeOnce = ResumeOnce()
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if resumeOnce.claim() {
                        continuation.resume(returning: Int(self?.listener.port?.rawValue ?? 0))
                    }
                case .failed(let error):
                    if resumeOnce.claim() {
                        continuation.resume(throwing: error)
                    }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
        connections.forEach { $0.cancel() }
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                let commands = max(String(decoding: data, as: UTF8.self).split(separator: "\n").count, 1)
                connection.send(content: Data(String(repeating: "OK\n", count: commands).utf8), completion: .contentProcessed { _ in })
            }
            if error == nil && !isComplete {
                self?.receive(on: connection)
            }
        }
    }
}

@MainActor
final class MPDPlayerBrowserTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "MPDPlayerBrowserTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    private func definition(name: String, host: String, port: Int, manual: Bool) throws -> PlayerDefinition {
        let attributes = MPDPlayer.PlayerAttributes(uuid: UUID(), name: name, type: .classic, version: "0.0.0",
                                                    host: host, port: port, password: nil, useHttpCoverArt: false,
                                                    manual: manual, albumGrouping: "albumartist", coverFilename: "",
                                                    outputHost: host, outputPort: 0)
        return PlayerDefinition(id: MPDPlayer.uniqueIDForPlayer(host: host, port: port),
                                name: name,
                                type: MPDPlayer.controllerType,
                                typeSpecificData: try JSONEncoder().encode(attributes),
                                isManual: manual)
    }

    /// Collects the ids of the players a browser announces.
    private func collectAnnouncements(of browser: MPDPlayerBrowser) -> Task<[String], Never> {
        Task {
            var ids: [String] = []
            for await event in browser.playerEventStream {
                if case .added(let player) = event {
                    ids.append(player.uniqueID)
                }
            }
            return ids
        }
    }

    /// Announcements arrive through an async stream, so give them a moment to show up (or not).
    private func announced(by collector: Task<[String], Never>, browser: MPDPlayerBrowser) async -> [String] {
        try? await Task.sleep(nanoseconds: 300_000_000)
        collector.cancel()
        return await collector.value
    }

    func testCachedPlayerThatDoesNotAnswerIsNotAnnounced() async throws {
        let browser = MPDPlayerBrowser(userDefaults: defaults)
        let collector = collectAnnouncements(of: browser)

        // Nothing listens on port 1 of this machine.
        await browser.announce(try definition(name: "Gone", host: "127.0.0.1", port: 1, manual: false))

        let ids = await announced(by: collector, browser: browser)
        XCTAssertEqual(ids, [], "announcing counts as having seen the player, which would stop it from ever expiring")
    }

    func testManualPlayerThatDoesNotAnswerIsStillAnnounced() async throws {
        let browser = MPDPlayerBrowser(userDefaults: defaults)
        let collector = collectAnnouncements(of: browser)

        await browser.announce(try definition(name: "Manual", host: "127.0.0.1", port: 1, manual: true))

        let ids = await announced(by: collector, browser: browser)
        XCTAssertEqual(ids, ["127.0.0.1:1"])
    }

    func testCachedPlayerThatAnswersIsAnnounced() async throws {
        let server = try FakeMPDServer()
        let port = try await server.start()
        defer { server.stop() }
        let browser = MPDPlayerBrowser(userDefaults: defaults)
        let collector = collectAnnouncements(of: browser)

        await browser.announce(try definition(name: "Here", host: "127.0.0.1", port: port, manual: false))

        let ids = await announced(by: collector, browser: browser)
        XCTAssertEqual(ids, ["127.0.0.1:\(port)"])
    }

    func testIsManualPlayerLooksAtTheDefinitionOnly() throws {
        let browser = MPDPlayerBrowser(userDefaults: defaults)

        XCTAssertTrue(browser.isManualPlayer(try definition(name: "Manual", host: "nas", port: 6600, manual: true)))
        XCTAssertFalse(browser.isManualPlayer(try definition(name: "Found", host: "nas", port: 6600, manual: false)))

        // A definition written before the isManual flag existed: only the attributes say that it is manual.
        var oldDefinition = try definition(name: "Manual", host: "nas", port: 6600, manual: true)
        oldDefinition.isManual = false
        XCTAssertTrue(browser.isManualPlayer(oldDefinition))

        // Not an MPD definition, or not readable at all.
        var other = try definition(name: "Manual", host: "nas", port: 6600, manual: true)
        other.type = "OpenHome"
        XCTAssertFalse(browser.isManualPlayer(other))
        XCTAssertFalse(browser.isManualPlayer(PlayerDefinition(id: "x", name: "x", type: MPDPlayer.controllerType, typeSpecificData: Data("garbage".utf8))))
    }

    func testRemovedServiceIsReportedUnderThePlayersID() async throws {
        let browser = MPDPlayerBrowser(userDefaults: defaults)
        let collector = Task { () -> [String] in
            var removed: [String] = []
            for await event in browser.playerEventStream {
                if case .removed(let id) = event {
                    removed.append(id)
                }
            }
            return removed
        }

        // A moOde or Volumio service: the player's host and port come from the service's web page, not its name.
        let attributes = try JSONDecoder().decode(MPDPlayer.PlayerAttributes.self,
                                                  from: definition(name: "moode", host: "127.0.0.1", port: 1, manual: false).typeSpecificData)
        browser.handleFound(taskKey: "http:moOde audio player") {
            (MPDPlayer(attributes, userDefaults: self.defaults), nil)
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        browser.serviceRemoved(taskKey: "http:moOde audio player")
        browser.serviceRemoved(taskKey: "http:never found")
        try await Task.sleep(nanoseconds: 100_000_000)
        collector.cancel()

        let removed = await collector.value
        XCTAssertEqual(removed, ["127.0.0.1:1"])
    }

    func testDeletingAManualPlayerForgetsItsSettings() throws {
        let browser = MPDPlayerBrowser(userDefaults: defaults)
        let manual = try definition(name: "Manual", host: "nas", port: 6600, manual: true)
        var copy = manual
        copy.id = "nas:6600#Manual"
        for id in [copy.id, "nas:6600"] {
            defaults.set("secret", forKey: MPDDefaultKey.password.stringValue(id))
            defaults.set("Living room", forKey: MPDDefaultKey.customPlayerName.stringValue(id))
            defaults.set(true, forKey: MPDDefaultKey.hidden.stringValue(id))
        }

        browser.playerRemoved(copy)

        XCTAssertNil(defaults.string(forKey: MPDDefaultKey.password.stringValue(copy.id)))
        XCTAssertNil(defaults.string(forKey: MPDDefaultKey.customPlayerName.stringValue(copy.id)))
        XCTAssertNil(defaults.object(forKey: MPDDefaultKey.hidden.stringValue(copy.id)))
        // Another player on the same server keeps its settings.
        XCTAssertEqual(defaults.string(forKey: MPDDefaultKey.password.stringValue("nas:6600")), "secret")

        // Only manual players are deleted by the user; a discovered one never loses its settings this way.
        browser.playerRemoved(try definition(name: "Found", host: "nas", port: 6600, manual: false))
        XCTAssertEqual(defaults.string(forKey: MPDDefaultKey.password.stringValue("nas:6600")), "secret")
    }

    func testDeletedPlayerIsNotAnnouncedAfterwards() async throws {
        let server = try FakeMPDServer()
        server.greetingDelay = 0.5
        let port = try await server.start()
        defer { server.stop() }
        let browser = MPDPlayerBrowser(userDefaults: defaults)
        let collector = collectAnnouncements(of: browser)
        let manual = try definition(name: "Manual", host: "127.0.0.1", port: port, manual: true)

        // Activating announces every cached player; this one is still being contacted when the user deletes it.
        await browser.startListening(predefinedPlayers: [manual])
        try await Task.sleep(nanoseconds: 100_000_000)
        browser.playerRemoved(manual)
        try await Task.sleep(nanoseconds: 1_200_000_000)
        await browser.stopListening()

        // Starting to listen also starts Bonjour discovery, which may find real players on this network.
        let ids = await announced(by: collector, browser: browser)
        XCTAssertFalse(ids.contains(manual.id), "announcing it would bring the deleted player back")
    }

    func testForgettingSettingsAlsoRemovesTheDefaultsOfItsType() throws {
        // A Bryston player stores cover art defaults when it is created, as a player under test would.
        let attributes = MPDPlayer.PlayerAttributes(uuid: UUID(), name: "Test", type: .bryston, version: "0.0.0",
                                                    host: "nas", port: 6600, password: "pw", useHttpCoverArt: false,
                                                    manual: true, albumGrouping: "albumartist", coverFilename: "",
                                                    outputHost: "nas", outputPort: 0, instanceID: "test-1")
        MPDPlayer.storePassword("pw", host: "nas", port: 6600, instanceID: "test-1", userDefaults: defaults)
        let player = MPDPlayer(attributes, userDefaults: defaults)
        XCTAssertNotNil(defaults.object(forKey: MPDDefaultKey.useHttpCoverArt.stringValue(player)))

        MPDPlayer.forgetSettings(uniqueID: player.uniqueID, userDefaults: defaults)

        for key in MPDDefaultKey.allCases {
            XCTAssertNil(defaults.object(forKey: key.stringValue(player)), "\(key) left behind")
        }
    }
}
