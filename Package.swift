// swift-tools-version: 6.2
// Tools version lowered from 6.4 to 6.2 so the package also opens in older Xcode
// releases; nothing here needs a newer manifest API.

import PackageDescription

// NotesReduxCore is the platform-independent heart of Notes Redux: the note model,
// section outline, Add Entry insertion engine and JSON persistence. It depends only
// on Foundation and Observation so it builds and tests on Windows/Linux as well as
// Apple platforms. The SwiftUI app lives in NotesRedux.swiftpm and depends on this.
let package = Package(
    name: "notes-redux",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "NotesReduxCore",
            targets: ["NotesReduxCore"]
        ),
    ],
    targets: [
        .target(
            name: "NotesReduxCore",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .testTarget(
            name: "NotesReduxCoreTests",
            dependencies: ["NotesReduxCore"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
    ]
)
