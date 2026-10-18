//
//  MPDPlayerTests.swift
//  MPDConnector
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

import XCTest
import ConnectorProtocol
@testable import MPDConnector

class MPDPlayerTests: XCTestCase {
    private func decode(_ json: String) throws -> MPDPlayer.PlayerAttributes {
        try JSONDecoder().decode(MPDPlayer.PlayerAttributes.self, from: Data(json.utf8))
    }

    func testAttributesFromOlderVersionStillDecode() throws {
        // Only the essential fields: everything added later must fall back to defaults.
        let attributes = try decode(#"{"host":"nas.local","port":6600}"#)
        XCTAssertEqual(attributes.host, "nas.local")
        XCTAssertEqual(attributes.port, 6600)
        XCTAssertEqual(attributes.name, "nas.local")
        XCTAssertEqual(attributes.type, .classic)
        XCTAssertEqual(attributes.albumGrouping, "albumartist")
        XCTAssertEqual(attributes.outputHost, "nas.local")
        XCTAssertFalse(attributes.manual)
        XCTAssertNil(attributes.password)
    }

    func testAttributesWithUnknownTypeFallBackToClassic() throws {
        let attributes = try decode(#"{"host":"nas","port":6600,"type":99,"manual":true,"password":"secret"}"#)
        XCTAssertEqual(attributes.type, .classic)
        XCTAssertTrue(attributes.manual)
        XCTAssertEqual(attributes.password, "secret")
    }

    func testAttributesRoundTrip() throws {
        let original = MPDPlayer.PlayerAttributes(uuid: UUID(), name: "Living room", type: .volumio, version: "0.23.0",
                                                  host: "volumio.local", port: 6601, password: "pw", useHttpCoverArt: true,
                                                  manual: true, albumGrouping: "album", coverFilename: "cover", outputHost: "out", outputPort: 8000)
        let decoded = try JSONDecoder().decode(MPDPlayer.PlayerAttributes.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.uuid, original.uuid)
        XCTAssertEqual(decoded.name, "Living room")
        XCTAssertEqual(decoded.type, .volumio)
        XCTAssertEqual(decoded.password, "pw")
        XCTAssertTrue(decoded.manual)
        XCTAssertEqual(decoded.outputPort, 8000)
    }

    func testManualPlayerDefinitionIsManual() throws {
        let attributes = try decode(#"{"host":"nas","port":6600,"manual":true}"#)
        let player = MPDPlayer(attributes, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        XCTAssertTrue(try player.playerDefinition().isManual)
    }

    func testStorePasswordWritesTheKeyTheConnectorReads() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        MPDPlayer.storePassword("secret", host: "nas", port: 6600, userDefaults: defaults)
        XCTAssertEqual(defaults.string(forKey: MPDDefaultKey.password.stringValue(host: "nas", port: 6600)), "secret")

        // The settings screen and the player use the per-player variant of the same key.
        let attributes = try! decode(#"{"host":"nas","port":6600}"#)
        let player = MPDPlayer(attributes, userDefaults: defaults)
        XCTAssertEqual(defaults.string(forKey: MPDDefaultKey.password.stringValue(player)), "secret")
    }

    func testStoreEmptyPasswordKeepsExistingPassword() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let key = MPDDefaultKey.password.stringValue(host: "nas", port: 6600)
        defaults.set("fromSettings", forKey: key)

        MPDPlayer.storePassword(nil, host: "nas", port: 6600, userDefaults: defaults)
        MPDPlayer.storePassword("", host: "nas", port: 6600, userDefaults: defaults)

        XCTAssertEqual(defaults.string(forKey: key), "fromSettings")
    }

    private func attributes(name: String, instanceID: String?) -> MPDPlayer.PlayerAttributes {
        MPDPlayer.PlayerAttributes(uuid: UUID(), name: name, type: .classic, version: "0.0.0", host: "nas", port: 6600,
                                   password: nil, useHttpCoverArt: false, manual: instanceID != nil, albumGrouping: "albumartist",
                                   coverFilename: "", outputHost: "nas", outputPort: 0, instanceID: instanceID)
    }

    func testManualCopyHasDistinctIDAndKeepsItsName() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let discovered = MPDPlayer(attributes(name: "Discovered", instanceID: nil), userDefaults: defaults)
        let manual = MPDPlayer(attributes(name: "Manual", instanceID: "Manual"), userDefaults: defaults)

        XCTAssertEqual(discovered.uniqueID, "nas:6600")
        XCTAssertNotEqual(manual.uniqueID, discovered.uniqueID)
        XCTAssertEqual(manual.name, "Manual")
        XCTAssertEqual(try manual.playerDefinition().id, manual.uniqueID)
        XCTAssertTrue(try manual.playerDefinition().isManual)
    }

    func testIdentitySurvivesAttributeRebuildAndPersistence() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let manual = MPDPlayer(attributes(name: "Manual", instanceID: "Manual"), userDefaults: defaults)
        let id = manual.uniqueID

        // Rebuilding attributes without the instanceID (as the settings screen does) must not change the identity.
        manual.attributes = attributes(name: "Manual", instanceID: nil)
        XCTAssertEqual(manual.uniqueID, id)

        let restored = try JSONDecoder().decode(MPDPlayer.PlayerAttributes.self, from: manual.encodePlayer())
        XCTAssertEqual(MPDPlayer(restored, userDefaults: defaults).uniqueID, id)
    }

    func testSettingsAreStrictlySeparatePerPlayer() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let discovered = MPDPlayer(attributes(name: "Discovered", instanceID: nil), userDefaults: defaults)
        let manual = MPDPlayer(attributes(name: "Manual", instanceID: "Manual"), userDefaults: defaults)

        for key in [MPDDefaultKey.password, .ipAddress, .connectToIpAddress, .discoveredIpAddress, .customPlayerName, .hidden] {
            XCTAssertNotEqual(key.stringValue(manual), key.stringValue(discovered), "\(key)")
        }
        // A discovered player keeps the key it has always used.
        XCTAssertEqual(MPDDefaultKey.password.stringValue(discovered), MPDDefaultKey.password.stringValue(host: "nas", port: 6600))
    }

    func testManualCopyPasswordIsStoredUnderItsOwnKey() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        MPDPlayer.storePassword("secret", host: "nas", port: 6600, instanceID: "Manual", userDefaults: defaults)

        let manual = MPDPlayer(attributes(name: "Manual", instanceID: "Manual"), userDefaults: defaults)
        let discovered = MPDPlayer(attributes(name: "Discovered", instanceID: nil), userDefaults: defaults)
        XCTAssertEqual(defaults.string(forKey: MPDDefaultKey.password.stringValue(manual)), "secret")
        XCTAssertNil(defaults.string(forKey: MPDDefaultKey.password.stringValue(discovered)))
    }

    // MARK: - Type defaults and type changes

    private func brystonAttributes() -> MPDPlayer.PlayerAttributes {
        MPDPlayer.PlayerAttributes(uuid: UUID(), name: "Bryston", type: .bryston, version: "0.0.0", host: "bdp", port: 6600,
                                   password: nil, useHttpCoverArt: false, manual: true, albumGrouping: "artist",
                                   coverFilename: "", outputHost: "bdp", outputPort: 0, instanceID: "Bryston")
    }

    func testANewPlayerStartsWithTheDefaultsOfItsType() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let player = MPDPlayer(brystonAttributes(), userDefaults: defaults)

        // Right away, not only from the next launch on: the cover art comes from the player over http.
        XCTAssertTrue(player.attributes.useHttpCoverArt)
        XCTAssertEqual(player.attributes.coverFilename, "bdp_front_250.jpg")
        XCTAssertEqual(player.attributes.albumGrouping, "albumartist")
        XCTAssertTrue(player.supportedFunctions.contains(.httpImageRetrieval))
        let saved = try JSONDecoder().decode(MPDPlayer.PlayerAttributes.self, from: player.playerDefinition().typeSpecificData)
        XCTAssertTrue(saved.useHttpCoverArt)
        XCTAssertEqual(saved.coverFilename, "bdp_front_250.jpg")
    }

    func testTheDefaultsOfATypeDoNotOverrideWhatTheUserSet() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(false, forKey: MPDDefaultKey.useHttpCoverArt.stringValue("bdp:6600#Bryston"))
        let player = MPDPlayer(brystonAttributes(), userDefaults: defaults)

        XCTAssertFalse(player.attributes.useHttpCoverArt)
    }

    func testChangingTheTypeEndsUpInTheSavedDefinition() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let player = MPDPlayer(attributes(name: "Manual", instanceID: "Manual"), userDefaults: defaults)

        player.changeType(.bryston)

        XCTAssertEqual(player.type, .bryston)
        XCTAssertEqual(player.attributes.type, .bryston)
        XCTAssertTrue(player.attributes.useHttpCoverArt)
        let saved = try JSONDecoder().decode(MPDPlayer.PlayerAttributes.self, from: player.playerDefinition().typeSpecificData)
        XCTAssertEqual(saved.type, .bryston)
        XCTAssertEqual(saved.instanceID, "Manual")
        // And a restart picks it up.
        XCTAssertEqual(MPDPlayer(saved, userDefaults: defaults).type, .bryston)
    }
}
