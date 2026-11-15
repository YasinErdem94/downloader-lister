// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DownloaderLister",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DownloaderLister", targets: ["DownloaderLister"])],
    targets: [.executableTarget(name: "DownloaderLister")]
)
