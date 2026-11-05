// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TVGuideCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "TVGuideCore", targets: ["TVGuideCore"])],
    targets: [
        .target(name: "TVGuideCore", resources: [.copy("Resources/markets.csv"), .copy("Resources/zips.csv")]),
        .testTarget(name: "TVGuideCoreTests", dependencies: ["TVGuideCore"], resources: [.copy("Fixtures")]),
    ]
)
