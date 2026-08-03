// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AsitraContracts",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "AsitraContracts", targets: ["AsitraContracts"])
    ],
    targets: [
        .target(name: "AsitraContracts"),
        .testTarget(
            name: "AsitraContractsTests",
            dependencies: ["AsitraContracts"]
        )
    ]
)
