import Foundation
import SwiftGeminiInteractions

@main struct AgentConversation {
    static func main() async throws {
        let client = InteractionsClient(apiKey: ProcessInfo.processInfo.environment["GEMINI_API_KEY"]!)

        // Agent initializer accepts a trailing @InteractionConfigBuilder closure for config params.
        let agent = try Agent(client: client, model: "gemini-3-flash-preview") {
            Temperature(0.7)
            SystemInstruction("You are a helpful Swift programming tutor.")
        }

        let r1 = try await agent.send("What is a Swift actor?")
        print("Agent: \(r1)\n")

        let r2 = try await agent.send("Can you show me an example?")
        print("Agent: \(r2)\n")

        let transcriptCount = await agent.transcript.count
        print("Transcript entries: \(transcriptCount)")
    }
}
