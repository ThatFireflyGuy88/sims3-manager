// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sims3Manager",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Sims3Manager",
            path: "Sources/Sims3Manager"
        )
    ],
    swiftLanguageVersions: [.v5]
)
