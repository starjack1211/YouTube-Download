// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LinkValidation",
    platforms: [.macOS(.v13)],
    products: [.library(name: "LinkValidation", targets: ["LinkValidation"])],
    targets: [
        .target(name: "LinkValidation", path: "Shared", exclude: ["Downloader.swift", "DownloadView.swift", "Notices.swift"], sources: ["YouTubeLink.swift", "TransferStatistics.swift"]),
        .testTarget(name: "LinkValidationTests", dependencies: ["LinkValidation"], path: "Tests")
    ]
)
