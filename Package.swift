// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ControlRoom",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "cr", targets: ["cr"]),
    ],
    targets: [
        // Ticket model, timing rules, store and local server. The app will host this too.
        .target(name: "ControlRoomCore"),
        // Command line: run the server, add and move tickets.
        .executableTarget(name: "cr", dependencies: ["ControlRoomCore"]),
        .testTarget(name: "ControlRoomCoreTests", dependencies: ["ControlRoomCore"]),
    ],
    swiftLanguageModes: [.v5]
)
