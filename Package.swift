// swift-tools-version:5.0

let package = Package(
    name: "MPDConnector",
    platforms: [.iOS(.v10)],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "MPDConnector",
            targets: ["MPDConnector"])
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/RxSwiftCommunity/Starscream.git", .upToNextMajor(from: "3.0.0")),
        .package(url: "https://github.com/RxSwiftCommunity/RxSwiftExt", .upToNextMajor(from: "5.0.0")),
        .package(path: "/Users/berrie/Software/swift-mpd/ConnectorProtocol"),
        .package(path: "/Users/berrie/Software/swift-mpd/libmpdclient")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "MPDConnector",
            dependencies: ["RxSwift", "RxSwiftExt", "ConnectorProtocol", "RxNetService", "libmpdclient"]),
        .testTarget(
            name: "MPDConnectorTests",
            dependencies: ["MPDConnector"])
    ]
)
