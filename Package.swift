// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Focal",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Focal",
            path: "Sources/Focal"
        )
    ]
)
