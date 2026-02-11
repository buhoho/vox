// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "vox",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "vox", targets: ["Vox"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMajor(from: "1.2.0")),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", .upToNextMinor(from: "0.9.0"))
    ],
    targets: [
        .target(
            name: "VoxLib",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "WhisperKit", package: "WhisperKit")
            ],
            path: "Sources/VoxLib"
        ),
        .executableTarget(
            name: "Vox",
            dependencies: ["VoxLib"],
            path: "Sources/Vox",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "VoxLibTests",
            dependencies: ["VoxLib"],
            path: "Tests/VoxLibTests"
        )
    ]
)
