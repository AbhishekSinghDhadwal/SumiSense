// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SumiSenseCore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "SumiSenseCore", targets: ["SumiSenseCore"])
    ],
    targets: [
        .target(
            name: "SumiSenseCore",
            path: "LogicCore/Sources/SumiSenseCore"
        ),
        .testTarget(
            name: "SumiSenseCoreTests",
            dependencies: ["SumiSenseCore"],
            path: "LogicCore/Tests/SumiSenseCoreTests"
        )
    ]
)
