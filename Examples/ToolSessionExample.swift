import Foundation
import SwiftGeminiInteractions

@main struct ToolSessionExample {
    static func main() async throws {
        let client = InteractionsClient(apiKey: ProcessInfo.processInfo.environment["GEMINI_API_KEY"]!)

        // Define the function schema: an object with `expression` string parameter.
        let schema = JSONSchemaValue.object(
            properties: [
                ("expression", .string(description: "The arithmetic expression to evaluate, e.g. \"1234 * 5678\""))
            ],
            required: ["expression"]
        )

        let session = ToolSession(
            client: client,
            tools: [.function(name: "calculator", description: "Performs arithmetic", parameters: schema)],
            handlers: ["calculator": { args in
                // In a real app, parse `args` (JSON) and evaluate the expression.
                // Here we return a hardcoded result for illustration.
                return "{\"result\": 7006652}"
            }],
            maxIterations: 5
        )

        let result = try await session.run(
            model: "gemini-3-flash-preview",
            input: [User("What is 1234 multiplied by 5678?")],
            configParams: []
        )
        print(result.interaction.outputText ?? "")
        print("Tool calls: \(result.log.count)")
    }
}
