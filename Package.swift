// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "vox",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "vox", targets: ["Vox"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMinor(from: "1.2.0"))
    ],
    targets: [
        .target(
            name: "VoxLib",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
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
