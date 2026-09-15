// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Kanpeki",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "KanpekiCamera", targets: ["KanpekiCamera"])
    ],
    targets: [
        .target(name: "KanpekiCamera", resources: [.process("Resources")]),
        .testTarget(name: "KanpekiCameraTests", dependencies: ["KanpekiCamera"], path: "CameraTests/KanpekiCameraTests")
    ]
)
