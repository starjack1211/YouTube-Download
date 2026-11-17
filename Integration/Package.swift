// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "YouTubeIntegration",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../Vendor/YouTubeKit")],
    targets: [.testTarget(name: "YouTubeIntegrationTests", dependencies: [.product(name: "YouTubeKit", package: "YouTubeKit")], path: "Tests")]
)
