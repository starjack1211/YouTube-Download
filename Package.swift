// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LinkValidation",
    platforms: [.macOS(.v13)],
    products: [.library(name: "LinkValidation", targets: ["LinkValidation"])],
    targets: [
        .target(name: "LinkValidation", path: "Shared", sources: ["YouTubeLink.swift"]),
        .testTarget(name: "LinkValidationTests", dependencies: ["LinkValidation"], path: "Tests")
    ]
)
