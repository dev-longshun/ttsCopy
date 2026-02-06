// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ttsCopy",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ttsCopy", targets: ["ttsCopy"])
    ],
    targets: [
        .executableTarget(
            name: "ttsCopy",
            path: "ttsCopy",
            exclude: ["Info.plist", "ttsCopy.entitlements", "Assets.xcassets"],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
