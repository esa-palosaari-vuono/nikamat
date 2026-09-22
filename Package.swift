// swift-tools-version: 6.0
import PackageDescription

// Nikamat is a plain AppKit/SwiftUI executable. SwiftPM only produces the
// binary; the Makefile wraps it into a proper .app bundle, because the
// LSUIElement key in Info.plist is what keeps the app out of the Dock.
let package = Package(
    name: "Nikamat",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Nikamat",
            path: "Sources/Nikamat",
            // Language mode 5: the app is single-threaded and @MainActor by
            // construction, and strict concurrency checking buys nothing here.
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        // Tests import the executable with @testable, which SwiftPM supports on
        // macOS. That keeps the app one module, without a public API surface
        // that exists only to be tested.
        .testTarget(
            name: "NikamatTests",
            dependencies: ["Nikamat"],
            path: "Tests/NikamatTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
