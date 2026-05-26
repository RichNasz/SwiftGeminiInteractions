// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "SwiftGeminiInteractions",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "SwiftGeminiInteractions", targets: ["SwiftGeminiInteractions"])
    ],
    traits: [
        // Leaf traits — each enables a specific orchestration subsystem
        .trait(
            name: "ToolSession",
            description: "Multi-turn tool-calling loop with parallel function execution and usage tracking"
        ),
        .trait(
            name: "Agent",
            description: "Conversational agent wrapper with automatic tool execution and transcript",
            enabledTraits: ["ToolSession"]
        ),

        // Composite trait — the recommended bundle
        .trait(
            name: "Full",
            description: "ToolSession + Agent — all orchestration layers enabled",
            enabledTraits: ["Agent"]
        ),

        // Default — users who don't specify traits get everything
        .default(enabledTraits: ["Full"]),
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
