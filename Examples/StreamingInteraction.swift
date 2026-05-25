import Foundation
import SwiftGeminiInteractions

@main struct StreamingInteraction {
    static func main() async throws {
        let client = InteractionsClient(apiKey: ProcessInfo.processInfo.environment["GEMINI_API_KEY"]!)
        var request = InteractionRequest(input: .text("Tell me a short story about a robot."))
        request.model = "gemini-3-flash-preview"
        for try await event in client.stream(request) {
            switch event {
            case .stepDelta(let delta, _):
                if case .text(let text) = delta { print(text, terminator: "") }
            case .interactionCompleted(let interaction):
                print("\n\nTokens: \(interaction.usage?.totalTokens ?? 0)")
            default: break
            }
        }
    }
}
