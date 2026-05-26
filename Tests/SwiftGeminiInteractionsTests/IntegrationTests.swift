// Tests/SwiftGeminiInteractionsTests/IntegrationTests.swift
import XCTest
@testable import SwiftGeminiInteractions

/// Live API tests. Only run when GEMINI_API_KEY is set in the environment.
final class IntegrationTests: XCTestCase {

    private var apiKey: String?
    private var client: InteractionsClient?

    override func setUp() {
        super.setUp()
        apiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
        if let key = apiKey {
            client = InteractionsClient(apiKey: key)
        }
    }

    private func skipIfNoKey() throws {
        let hasKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] != nil
        let optedIn = ProcessInfo.processInfo.environment["RUN_INTEGRATION_TESTS"] == "1"
        try XCTSkipIf(!hasKey || !optedIn,
            "Set GEMINI_API_KEY and RUN_INTEGRATION_TESTS=1 to run integration tests")
    }

    func testLiveSendRoundTrip() async throws {
        try skipIfNoKey()
        var request = InteractionRequest(input: .text("Reply with exactly the word: PONG"))
        request.model = "gemini-3-flash-preview"
        let interaction = try await client!.send(request)
        XCTAssertEqual(interaction.status, .completed)
        XCTAssertNotNil(interaction.outputText)
    }

    func testLiveStreamAccumulatesText() async throws {
        try skipIfNoKey()
        var request = InteractionRequest(input: .text("Count from 1 to 5, one number per line."))
        request.model = "gemini-3-flash-preview"
        var accumulated = ""
        for try await event in client!.stream(request) {
            if case .stepDelta(let delta, _) = event, case .text(let t) = delta {
                accumulated += t
            }
        }
        XCTAssertFalse(accumulated.isEmpty)
    }

    func testLiveToolCallingLoop() async throws {
        try skipIfNoKey()
        // Use an empty object schema as the safest option
        let schema = JSONSchemaValue.object(properties: [], required: [])
        let session = ToolSession(
            client: client!,
            tools: [.function(name: "getWeather", description: "Returns weather for a city", parameters: schema)],
            handlers: ["getWeather": { _ in
                return "{\"temperature\": 22, \"condition\": \"sunny\"}"
            }],
            maxIterations: 5
        )
        let result = try await session.run(
            model: "gemini-3-flash-preview",
            input: [User("What's the weather in Paris?")],
            configParams: []
        )
        XCTAssertEqual(result.interaction.status, .completed)
        XCTAssertFalse(result.log.isEmpty)
    }

    func testLiveFlexServiceTier() async throws {
        try skipIfNoKey()
        var request = InteractionRequest(input: .text("Reply with exactly the word: PONG"))
        request.model = "gemini-3-flash-preview"
        ServiceTierParam(.flex).apply(to: &request)
        let interaction = try await client!.send(request)
        XCTAssertEqual(interaction.status, .completed)
        XCTAssertNotNil(interaction.outputText)
    }

    func testLiveMultiTurnConversation() async throws {
        try skipIfNoKey()
        let agent = try Agent(client: client!, model: "gemini-3-flash-preview")
        let r1 = try await agent.send("My name is Claude. Remember it.")
        XCTAssertFalse(r1.isEmpty)
        let r2 = try await agent.send("What is my name?")
        XCTAssertTrue(r2.lowercased().contains("claude"),
            "Expected second reply to recall the name; got: \(r2)")
    }

    func testLivePollBackgroundInteraction() async throws {
        try skipIfNoKey()
        var request = InteractionRequest(input: .text("Summarize the concept of recursion in two sentences."))
        request.model = "gemini-3.5-flash"
        request.background = true
        request.store = true
        let initial = try await client!.send(request)
        let final = try await client!.poll(
            id: initial.id,
            timeout: .seconds(60),
            interval: .seconds(2)
        )
        XCTAssertTrue(final.isComplete)
    }
}
