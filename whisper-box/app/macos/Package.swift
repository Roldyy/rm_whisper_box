// swift-tools-version: 5.9
import PackageDescription

// WhisperBox — native macOS app (Phase 1 skeleton).
// Isolated from the Python/React app: separate build, separate .app/.dmg.
//
// Engine: WhisperKit (chosen). It is NOT yet listed as a dependency so this
// skeleton builds offline against a MockEngine. To activate the real engine:
//   1. Uncomment the WhisperKit dependency + product below.
//   2. `WhisperKitEngine.swift` is gated on `#if canImport(WhisperKit)` and
//      lights up automatically once the package resolves.
// (Easiest in Xcode: File ▸ Add Package Dependencies ▸ argmaxinc/WhisperKit.)

let package = Package(
    name: "WhisperBox",
    platforms: [.macOS(.v14)],          // SwiftData + ScreenCaptureKit audio (14.2+)
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "WhisperBox",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            // The asset catalog is consumed by the Xcode app target (xcodegen),
            // not the SwiftPM build — exclude it to avoid an unhandled-resource warning.
            exclude: ["Assets.xcassets"]
        ),
    ]
)
