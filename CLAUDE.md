# SwiftGeminiInteractions — Architecture Notes

## Key Design Decisions

### Steps-Based Conversation Model
The Interactions API uses a unified `steps` array for both sent and received content. A single `Step` enum with 17 cases handles all roles. Custom `Codable` discriminates on the `"type"` key.

### previous_interaction_id Chaining
`ToolSession` sets `store: true` automatically and threads `previousInteractionId` across iterations. `PreviousInteractionId` config parameter must NOT be set manually when using ToolSession or Agent — both manage chaining automatically.

### Built-in Tools vs Function Tools
`InteractionTool` is a single enum. `.function` cases are backed by local `ToolHandler` closures in `ToolSession`/`AgentTool`. Built-in cases (`.googleSearch`, `.codeExecution`, etc.) execute server-side — no handler registered.

### Agent: Model vs Named Agent
`Agent` has two initializers: `model:` for standard Gemini model strings, `agent:` for named agents. The `ModelIdentifier` private enum carries this distinction. When using `agent:` with tools, a private `AgentIdentifierParam` overrides the `model` field that `ToolSession.buildRequest` sets, replacing it with the `agent` field.

### SSE Parsing
Events separated by `\n\n`. Each `data: <json>` line decoded by `event_type`. Unknown types produce `.unknown` — silently dropped for forward compatibility.

### Error Wrapping
No Foundation errors escape the public API. Every catch site wraps into `GeminiInteractionsError`. Uses `@unchecked Sendable` because `DecodingError`, `EncodingError`, and `any Error` are not natively Sendable.

### API Revision Header
`Api-Revision: 2026-05-20` on every request. Configurable at `InteractionsClient` init time.

### Testing Strategy
`MockURLProtocol` intercepts `URLSession` at the protocol level. `InteractionsClient` has an internal `init` that accepts a `URLSession` configured with `MockURLProtocol`. Integration tests require `RUN_INTEGRATION_TESTS=1` env var.

## File Map

| File | Contents |
|------|----------|
| `Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift` | All core types, config params, result builders, InteractionsClient, SSE parser |
| `Sources/SwiftGeminiInteractions/ToolSession.swift` | ToolSession, ToolSessionResult, ToolCallLogEntry, ToolSessionEvent |
| `Sources/SwiftGeminiInteractions/Agent.swift` | Agent, AgentTool, AgentToolBuilder, TranscriptEntry |

## Spec Files

All spec files in `Spec/` must be consulted during code generation.

| Spec | Purpose |
|------|---------|
| `what-core.md` | Types in SwiftGeminiInteractions.swift |
| `what-toolsession.md` | Types in ToolSession.swift |
| `what-agent.md` | Types in Agent.swift |
| `how-client.md` | HTTP construction, headers, error wrapping |
| `how-encoding.md` | Discriminated union encoding strategy |
| `how-streaming.md` | SSE parsing, event dispatch, stream resumption |
| `how-toolloop.md` | Tool loop algorithm, chaining, parallel execution |
| `how-polling.md` | Background poll algorithm |
| `how-errors.md` | Error wrapping strategy |
