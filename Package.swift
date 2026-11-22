// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Launch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Launch", targets: ["Launch"])
    ],
    targets: [
        .executableTarget(
            name: "Launch",
            path: "Sources/Launch",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
