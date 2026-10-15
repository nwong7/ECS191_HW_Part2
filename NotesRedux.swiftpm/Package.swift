// swift-tools-version: 5.9

// Notes Redux iOS app, as an Xcode "App Playground" package: open this
// NotesRedux.swiftpm folder in Xcode and run on a simulator or device.
// AppleProductTypes is only available in Xcode / Swift Playgrounds, so this
// package cannot be built with the command-line or Windows toolchain. The
// platform-independent logic lives in ../Sources/NotesReduxCore and is tested there.
//
// Tools version 5.9 (Swift 5 language mode) is deliberate: the UI code is
// written without a compiler on hand, so strict Swift 6 concurrency checking is
// left off here. The core library itself builds in Swift 6 mode.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "NotesRedux",
    platforms: [
        .iOS("18.0"),
    ],
    products: [
        .iOSApplication(
            name: "Notes Redux",
            targets: ["AppModule"],
            bundleIdentifier: "edu.ucdavis.notesredux",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "1",
            // No appIcon: the placeholder icon names could not be verified
            // without Xcode. Add one in Xcode (App Settings → App Icon) later.
            accentColor: .presetColor(.yellow),
            supportedDeviceFamilies: [
                .pad,
                .phone,
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad])),
            ]
        ),
    ],
    dependencies: [
        // A path dependency is identified by its folder name, which differs
        // between checkouts (e.g. "notes-redux" locally, the repo name on CI).
        // The explicit name lets the product reference below work everywhere.
        .package(name: "notes-redux", path: ".."),
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            dependencies: [
                .product(name: "NotesReduxCore", package: "notes-redux"),
            ],
            path: "."
        ),
    ]
)
