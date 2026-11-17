// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "YouTubeIntegration",
    platforms: [.macOS(.v13)],
    dependencies: [.package(url: "https://github.com/alexeichhorn/YouTubeKit.git", revision: "7f75a2299dc329c0b7855afb25d47663a02855cb")],
    targets: [.testTarget(name: "YouTubeIntegrationTests", dependencies: [.product(name: "YouTubeKit", package: "YouTubeKit")], path: "Tests")]
)
