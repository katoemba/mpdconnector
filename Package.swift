// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MPDConnector",
    platforms: [.macOS(.v12), .iOS(.v14), .watchOS(.v10)],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(name: "MPDConnector", targets: ["MPDConnector"]),
        .library(name: "MPDConnectorWithBrowser", targets: ["MPDConnectorWithBrowser"])
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/katoemba/connectorprotocol.git", branch: "master"),
        .package(url: "https://github.com/katoemba/libmpdclient-swift.git", .upToNextMajor(from: "2.19.0")),
        .package(url: "https://github.com/katoemba/rxnetservice.git", .upToNextMajor(from: "0.2.3")),
        .package(url: "https://github.com/ReactiveX/RxSwift.git", .upToNextMajor(from: "6.6.0")),
        .package(url: "https://github.com/RxSwiftCommunity/RxSwiftExt.git", .upToNextMajor(from: "6.0.0")),
        .package(url: "https://github.com/drmohundro/SWXMLHash.git", .upToNextMajor(from: "7.0.0"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "MPDConnector",
            dependencies: [.product(name: "ConnectorProtocol", package: "connectorprotocol"),
                           .product(name: "RxRelay", package: "rxswift"),
                           .product(name: "RxSwift", package: "rxswift"),
                           .product(name: "RxSwiftExt", package: "rxswiftext"),
                           .product(name: "libmpdclient", package: "libmpdclient-swift")]),
        .target(
            name: "MPDConnectorWithBrowser",
            dependencies: ["MPDConnector",
                           .product(name: "RxNetService", package: "rxnetservice"),
                           .product(name: "SWXMLHash", package: "swxmlhash")]),
        .testTarget(
            name: "MPDConnectorTests",
            dependencies: ["MPDConnector",
                           .product(name: "RxTest", package: "rxswift"),
                           .product(name: "RxBlocking", package: "rxswift"),
            ])
    ]
)
