// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vani",
    platforms: [
        .macOS(.v14)   // FluidAudio (Parakeet on the Neural Engine) requires macOS 14+
    ],
    products: [
        .library(name: "FlowCore", targets: ["FlowCore"]),
        .executable(name: "Vani", targets: ["Vani"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4"),
    ],
    targets: [
        // Pure, UI-free, testable core: provider protocols, OpenAI adapters, pipeline.
        .target(
            name: "FlowCore"
        ),
        // The macOS menu-bar app: audio capture, hotkey, text insertion, UI.
        // Swift 5 language mode: AppKit + the CGEventTap C-callback don't play
        // nicely with Swift 6 strict-concurrency checking.
        .executableTarget(
            name: "Vani",
            dependencies: [
                "FlowCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "FlowCoreTests",
            dependencies: ["FlowCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
