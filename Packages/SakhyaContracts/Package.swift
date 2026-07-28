// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SakhyaContracts",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "SakhyaContracts", targets: ["SakhyaContracts"])
    ],
    targets: [
        .target(name: "SakhyaContracts")
    ]
)
