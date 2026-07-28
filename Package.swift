// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "WeeklyWorkLog",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WeeklyWorkLog", targets: ["WeeklyWorkLog"])
    ],
    targets: [
        .executableTarget(
            name: "WeeklyWorkLog",
            path: "Sources/WeeklyWorkLog"
        ),
        .testTarget(
            name: "WeeklyWorkLogTests",
            dependencies: ["WeeklyWorkLog"],
            path: "Tests/WeeklyWorkLogTests"
        )
    ]
)
