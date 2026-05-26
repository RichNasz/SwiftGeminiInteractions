---
status: alpha
---

# what-toolsession.md — Public Types in ToolSession.swift

## ToolCallLogEntry
`public struct ToolCallLogEntry: Sendable`. Records one completed tool invocation. Fields: `name: String` (tool name), `arguments: String` (raw JSON arguments string passed to the handler), `result: String` (raw string output returned by the handler, or an error string if the handler threw), `duration: Duration` (wall-clock time for the handler call measured with `ContinuousClock`). Public memberwise init: `init(name:arguments:result:duration:)`.

## ToolSessionResult
`public struct ToolSessionResult: Sendable`. Returned by `ToolSession.run()` when the loop completes. Fields: `interaction: Interaction` (the final `Interaction` from the last API call), `iterations: Int` (total number of LLM calls made), `log: [ToolCallLogEntry]` (ordered list of all tool calls across all iterations), `iterationUsages: [Usage]` (one `Usage` per iteration, collected from `interaction.usage` when present). Computed property `totalUsage: Usage?` — returns `nil` when `iterationUsages` is empty, otherwise sums all token counts across iterations; note that `inputTokensByModality` is taken from the final iteration rather than summed, because per-iteration modality data is not additive across turns.

## ToolSessionEvent
`public enum ToolSessionEvent: Sendable`. Emitted by `ToolSession.stream()`. Cases:
- `iterationStarted(Int)` — fired at the start of each loop iteration with the 1-based iteration number.
- `llm(InteractionStreamEvent)` — forwards a raw SSE event from the underlying `client.stream()` call.
- `toolCallStarted(callId: String, name: String, arguments: String)` — fired immediately before a handler is invoked.
- `toolCallCompleted(callId: String, name: String, output: String, duration: Duration)` — fired after a handler returns (whether success or error string).
- `usageUpdate(Usage, iteration: Int)` — fired after an `interactionCompleted` event if the interaction carries usage data.

## ToolSession
`public struct ToolSession: Sendable`. Manages the agentic tool-calling loop against the Interactions API. Type alias: `public typealias ToolHandler = @Sendable (String) async throws -> String` (receives raw JSON arguments, returns a result string). Init parameters: `client: InteractionsClient`, `tools: [InteractionTool]`, `handlers: [String: ToolHandler]` (keyed by function name), `maxIterations: Int = 10`.

### run(model:input:configParams:)
`public func run(model: String, input: [Step], configParams: [any InteractionConfigParameter]) async throws -> ToolSessionResult`. Executes the synchronous tool loop. Builds a request via the private `buildRequest` helper, which applies all `configParams` and then unconditionally sets `store: true` (so no config parameter can disable storage). On the first call `previousInteractionId` is nil; subsequent iterations set it to the previous interaction's ID. When the interaction status is not `.requiresAction`, the loop terminates and returns. If status is `.requiresAction`, all `functionCall` steps are executed concurrently with `withThrowingTaskGroup`; results are re-ordered to match the original step order before building the next input. Throws `GeminiInteractionsError.maxIterationsExceeded(maxIterations)` when the iteration count reaches `maxIterations` before completing.

### stream(model:input:configParams:)
`public func stream(model: String, input: [Step], configParams: [any InteractionConfigParameter]) -> AsyncThrowingStream<ToolSessionEvent, Error>`. Streaming variant of the tool loop. Uses `client.stream()` internally. Extracts function calls from the `interactionCompleted` event's `interaction.steps` rather than from a polling response. Emits `ToolSessionEvent` values for each lifecycle point. Yields `iterationStarted` at the top of each iteration, forwards all `llm(_:)` events, runs tool handlers concurrently, and emits `toolCallStarted`/`toolCallCompleted` around each handler invocation. Results are sorted by original step index before building the next input. Throws `GeminiInteractionsError.maxIterationsExceeded(maxIterations)` if the max is reached.
