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
import MPDConnector

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
}
