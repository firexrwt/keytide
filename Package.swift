// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Keytide",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Keytide", targets: ["Keytide"])],
    targets: [
        .target(name: "KeytideCore", resources: [.copy("Resources")]),
        .executableTarget(name: "Keytide", dependencies: ["KeytideCore"]),
        .testTarget(name: "KeytideCoreTests", dependencies: ["KeytideCore"])
    ]
)
