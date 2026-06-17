// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Portcall",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Portcall",
            path: "Sources/Portcall"
        )
    ],
    swiftLanguageModes: [.v5]
)
