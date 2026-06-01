// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ScreenBridge",
    platforms: [
        // macOS 14 (Sonoma) — ScreenCaptureKit (12.3+), SwiftUI App, async/await
        // mlx-swift-examples는 macOS 14+. 안전.
        .macOS(.v14)
    ],
    dependencies: [
        // Phase 9.0 — Local vision LLM (Qwen2.5-VL-3B 4-bit via MLXVLM).
        // mlx-swift-examples: MLXLLM, MLXVLM, MLXLMCommon (VLM library + chat session).
        // mlx-swift: MLX core (Memory.cacheLimit), MLXNN, MLXRandom — Apple-official ML framework.
        // 둘 다 명시 dep — mlx-swift-examples가 mlx-swift를 *transitive*만 박음 (product re-export X).
        .package(url: "https://github.com/ml-explore/mlx-swift-examples", from: "2.21.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.29.0"),
    ],
    targets: [
        .executableTarget(
            name: "ScreenBridge",
            dependencies: [
                // Phase 9.0 — Qwen2.5-VL-3B local inference.
                // MLXVLM: vision-language models (Qwen2.5-VL, SmolVLM, Idefics3).
                // MLXLMCommon: shared types (Tokenizer, Generation, GenerateParameters).
                // MLX: core (Memory.cacheLimit — 20MB cap to prevent cache OOM on long streams).
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXVLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
            ],
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
