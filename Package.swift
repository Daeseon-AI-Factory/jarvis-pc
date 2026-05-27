// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ScreenBridge",
    platforms: [
        // macOS 14 (Sonoma) — ScreenCaptureKit (12.3+), SwiftUI App, async/await
        // 모두 안정. AXUIElement / Vision / NSWindow는 더 오래된 macOS에서도
        // 가능하지만 v0.1엔 단순화.
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "ScreenBridge",
            path: "Sources/ScreenBridge"
        ),
        .testTarget(
            name: "ScreenBridgeTests",
            dependencies: ["ScreenBridge"],
            path: "Tests/ScreenBridgeTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
