import Foundation
import SwiftGeminiInteractions

@main struct BasicInteraction {
    static func main() async throws {
        let client = InteractionsClient(apiKey: ProcessInfo.processInfo.environment["GEMINI_API_KEY"]!)
        var request = InteractionRequest(input: .text("What is the capital of France?"))
        request.model = "gemini-3-flash-preview"
        let interaction = try await client.send(request)
        print(interaction.outputText ?? "(no output)")
        print("Tokens used: \(interaction.usage?.totalTokens ?? 0)")
    }
}
