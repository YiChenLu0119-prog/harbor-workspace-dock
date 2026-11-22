// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HarborWorkspaceDock",
    platforms: [.macOS(.v13)],
    products: [.library(name: "HarborCore", targets: ["HarborCore"]), .executable(name: "Harbor", targets: ["HarborApp"])],
    targets: [
        .target(name: "HarborCore"),
        .executableTarget(name: "HarborApp", dependencies: ["HarborCore"], linkerSettings: [.linkedFramework("Carbon")]),
        .testTarget(name: "HarborCoreTests", dependencies: ["HarborCore"])
    ],
    swiftLanguageVersions: [.v5]
)
