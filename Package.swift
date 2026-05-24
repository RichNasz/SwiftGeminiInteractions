// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "SwiftGeminiInteractions",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "SwiftGeminiInteractions", targets: ["SwiftGeminiInteractions"])
    ],
    dependencies: [
        .package(url: "https://github.com/RichNasz/SwiftLLMToolMacros", branch: "main")
    ],
    targets: [
        .target(
            name: "SwiftGeminiInteractions",
            dependencies: ["SwiftLLMToolMacros"]
        ),
        .testTarget(
            name: "SwiftGeminiInteractionsTests",
            dependencies: ["SwiftGeminiInteractions"]
        )
    ]
)
