// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MPDConnector",
    platforms: [.iOS(.v10)],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(name: "MPDConnector", targets: ["MPDConnector"])
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(path: "../ConnectorProtocol"),
        .package(url: "https://github.com/katoemba/libmpdclient-swift.git", .upToNextMajor(from: "0.21.17")),
        .package(url: "https://github.com/katoemba/rxnetservice.git", .upToNextMajor(from: "0.2.1")),
        .package(url: "https://github.com/ReactiveX/RxSwift.git", .upToNextMajor(from: "5.0.1")),
        .package(url: "https://github.com/RxSwiftCommunity/RxSwiftExt.git", .upToNextMajor(from: "5.2.0")),
        .package(url: "https://github.com/drmohundro/SWXMLHash.git", .upToNextMajor(from: "5.0.1"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "MPDConnector",
            dependencies: ["ConnectorProtocol", "libmpdclient", "RxNetService", "RxSwift", "RxCocoa", "RxSwiftExt", "SWXMLHash"]),
        .testTarget(
            name: "MPDConnectorTests",
            dependencies: ["MPDConnector", "RxBlocking", "RxTest"])
    ]
)
