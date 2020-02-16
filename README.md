[![bitrise CI](https://img.shields.io/bitrise/66c8203166d77498?token=qVGWLOC7Ry4dZMeGVNlLCw)](https://bitrise.io)
![platforms](https://img.shields.io/badge/platforms-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS-lightgrey)
[![Swift Package Manager compatible](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg)](https://github.com/apple/swift-package-manager)

# README #

## What is this repository for? ##

* MPDConnector is an implementation of the generic ConnectorProtocol interface specification to control a network based music player.
The implementation uses libmpdclient to control mpd-based players of version 0.19 and up.
* These two frameworks are the foundation of the Rigelian MPD client, for more info see https://www.rigelian.net

## What are the building blocks of this Library? ##

* The implementation relies heavily on reactive constructs, using RxSwift.
* ConnectorProtocol consist of five sub-protocols, all of which are implemented in this framework:
	  * PlayerProtocol defines a basic player, access status, control and browse implementation, plus functions to maintain player-specific settings.
	  * PlayerBrowserProtocol is a generic protocol to detect players on the network.
	  * StatusProtocol is a protocol through which the connection status of a player, as well as the music-playing status can be monitored.
	  * ControlProtocol is a protocol through which commands can be sent to a player, like play, pause, add a song etc.
	  * BrowseProtocol is a protocol through which you can browse through the music on a player. It defines various ViewModels for artists, albums, genres etc.
* The protocol is meant to be independent of the target platform (iOS, MacOS, tvOS). However testing is only done on iOS.

## Installation

MPDConnector depends on libmpdclient-swift and ConnectorProtocol.

Build and usage via swift package manager is supported:

### [Swift Package Manager](https://github.com/apple/swift-package-manager)

The easiest way to add the library is directly from within XCode (11). Alternatively you can create a `Package.swift` file. 

```swift
// swift-tools-version:5.0

import PackageDescription

let package = Package(
  name: "MyProject",
  dependencies: [
  .package(url: "https://github.com/katoemba/mpdconnector.git", from: "1.7.0")
  ],
  targets: [
    .target(name: "MyProject", dependencies: ["mpdconnector"])
  ]
)
```
## Testing ##

* A set of unit tests is included, with limited coverage.

## Who do I talk to? ##

* In case of questions you can contact berrie at rigelian dot net
