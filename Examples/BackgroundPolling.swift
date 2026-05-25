import Foundation
import SwiftGeminiInteractions

@main struct BackgroundPolling {
    static func main() async throws {
        let client = InteractionsClient(apiKey: ProcessInfo.processInfo.environment["GEMINI_API_KEY"]!)

        // background: true lets the API process the request asynchronously.
        // store: true is required so the interaction can be retrieved later.
        var request = InteractionRequest(input: .text("Write a comprehensive essay on climate change."))
        request.model = "gemini-3-flash-preview"
        request.background = true
        request.store = true

        let initial = try await client.send(request)
        print("Started: \(initial.id), status: \(initial.status.rawValue)")

        // poll() retries get() until the interaction reaches a terminal status.
        let completed = try await client.poll(id: initial.id, timeout: .seconds(120), interval: .seconds(3))
        let preview = String((completed.outputText ?? "(no output)").prefix(200))
        print("Completed: \(preview)")
    }
}
