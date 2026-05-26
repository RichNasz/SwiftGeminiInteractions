---
status: alpha
---

# what-agent.md — Public Types in Agent.swift

## AgentTool
`public struct AgentTool: Sendable`. Pairs an `InteractionTool` definition with a local handler closure. Fields: `tool: InteractionTool`, `handler: ToolSession.ToolHandler`.

**Init 1 — explicit**: `public init(tool: InteractionTool, handler: @escaping ToolSession.ToolHandler)`. Takes any `InteractionTool` value and any compatible async throwing closure directly.

**Init 2 — LLMTool convenience**: `public init<T: LLMTool>(_ instance: T)`. Creates the tool from `T.toolDefinition` (macro-generated `ToolDefinition`) and wraps `instance.call(arguments:)` in a handler that decodes the raw JSON arguments string into `T.Arguments`, calls `instance.call(arguments:)`, and returns `output.content`. Throws `GeminiInteractionsError.invalidInput` if the arguments string cannot be encoded as UTF-8.

## AgentToolBuilder
`@resultBuilder public struct AgentToolBuilder`. Produces `[AgentTool]`. Supports: `buildBlock`, `buildExpression`, `buildOptional`, `buildEither(first:)`, `buildEither(second:)`, `buildArray`.

## TranscriptEntry
`public enum TranscriptEntry: Sendable`. Records one turn of conversation or tool activity in `Agent.transcript`. Cases:
- `userMessage(String)` — the user's text input to `send` or `stream`.
- `assistantMessage(String)` — the model's final text output.
- `thought(String)` — reserved for thought content (currently populated by stream).
- `toolCall(name: String, arguments: String)` — logged when a tool handler is invoked (both sync and stream paths).
- `toolResult(name: String, result: String, duration: Duration)` — logged after a handler returns.
- `builtInToolCall(type: String)` — reserved for server-side built-in tool invocations.
- `error(String)` — logged (via `localizedDescription`) when `stream` catches a thrown error.

## Agent
`public actor Agent`. High-level conversational agent that manages multi-turn state, tool calling, and transcript accumulation on top of `ToolSession` and `InteractionsClient`.

**Init 1 — model-based**: `public init(client: InteractionsClient, model: String, instructions: String? = nil, maxToolIterations: Int = 10, @AgentToolBuilder tools: () -> [AgentTool] = { [] }, @InteractionConfigBuilder config: () -> [any InteractionConfigParameter] = { [] }) throws`. Uses a Gemini model string; sets `modelIdentifier` to `.model(model)`. Throws `GeminiInteractionsError.invalidInput` if duplicate tool names are detected.

**Init 2 — named-agent**: `public init(client: InteractionsClient, agent: String, instructions: String? = nil, maxToolIterations: Int = 10, @AgentToolBuilder tools: () -> [AgentTool] = { [] }, @InteractionConfigBuilder config: () -> [any InteractionConfigParameter] = { [] }) throws`. Uses a named Gemini agent identifier; sets `modelIdentifier` to `.agent(agent)`. Throws on duplicate tool names. When used with `ToolSession`, a private `AgentIdentifierParam` is appended to `configParams` after `buildRequest` sets `model`, overriding it with `agent` in the JSON body.

### send(_ message: String) async throws -> String
Appends `userMessage` to transcript, sends via `sendDirect` (no tools) or `sendWithTools` (has tools), updates `lastInteractionId`, `lastUsage`, appends `assistantMessage`, and returns the output text string. When tools are present delegates to `ToolSession.run()` and logs all tool calls from `result.log`.

### stream(_ message: String) -> AsyncThrowingStream<ToolSessionEvent, Error>
Appends `userMessage` to transcript, then either streams directly via `client.stream()` (no tools) or delegates to `ToolSession.stream()` (has tools). Forwards all `ToolSessionEvent` values. Updates `lastInteractionId`, `lastUsage`, and `transcript` from streaming events. On error, appends `TranscriptEntry.error` and finishes with the throwing error.

### reset()
Resets all mutable agent state: clears `_lastInteractionId`, `_lastUsage`, and `_transcript`. After reset the agent behaves as if freshly initialized.

### Public properties
- `lastInteractionId: String?` — the `id` of the most recent completed interaction; `nil` before first send.
- `lastUsage: Usage?` — token usage from the most recent completed interaction (or total usage from `ToolSessionResult` when tools are active).
- `transcript: [TranscriptEntry]` — accumulated transcript across all `send`/`stream` calls since last `reset`.
