# Package Traits Design

## Context

SwiftGeminiInteractions is part of a broader SwiftLLM ecosystem (SwiftSynapseHarness, SwiftSynapseContainers) where Swift Package Traits are used extensively to let consumers activate only the subsystems they need. The goal here is consistency with that ecosystem and genuine modularity improvements — not just adding traits for their own sake.

The package currently has three source files: a monolithic `SwiftGeminiInteractions.swift` (1,631 lines containing all types, the client, streaming infrastructure, and background polling), `ToolSession.swift` (332 lines), and `Agent.swift` (320 lines).

---

## Design Decision: File Split vs. Trait Gating

This design separates two concerns that are often conflated:

**1. File split** — splitting `SwiftGeminiInteractions.swift` into focused files. This is an unconditional improvement: smaller files are easier to navigate, review, and understand. It applies regardless of whether traits are enabled.

**2. Trait gating** — conditionally excluding subsystems from compilation. This is only worth the complexity when the excluded code is large enough to meaningfully affect build time or binary size, and when consumers have a realistic reason to exclude it.

### Why Streaming and BackgroundPolling are NOT trait-gated

The streaming subsystem (`stream()`, `resumeStream()`, the SSE parser, and event types) is ~250 lines. Background polling (`poll()`) is a single function. Every consumer who builds an interactive application will use streaming; consumers not using background jobs simply won't call `poll()` — but not calling a function costs nothing at runtime and the compile cost of a single function is negligible.

Gating these behind traits would add `#if` noise to the source, require consumers to think about whether they "need" streaming (they do), and provide no meaningful savings. The file split already delivers the readability benefit.

### Why ToolSession and Agent ARE trait-gated

`ToolSession` and `Agent` together are ~650 lines of non-trivial orchestration logic. More importantly, they pull in the full `LLMTool` / `ToolDefinition` protocol surface from `SwiftLLMToolMacros`. A consumer that only needs direct API access — sending a request, reading a response, streaming tokens — never instantiates a `ToolSession` or `Agent`. Excluding them from compilation removes that code from the binary and saves compilation work for those consumers.

This is the same pattern the sibling packages use: gate the large, optional orchestration layers; leave the small infrastructure always-on.

---

## File Structure

```
Sources/SwiftGeminiInteractions/
  Core.swift              — always compiled
  Streaming.swift         — always compiled
  BackgroundPolling.swift — always compiled
  ToolSession.swift       — #if ToolSession … #endif
  Agent.swift             — #if Agent … #endif
```

### Core.swift (split from SwiftGeminiInteractions.swift)

Contains everything that is always needed:

- `GeminiInteractionsError`, `InteractionStatus`, `ServiceTier`, `ResponseModality`
- `ThinkingLevel`, `ThinkingSummaries`, `ToolChoiceMode`, `ToolChoiceConfig`
- `Annotation`, `Content`, `ModalityTokens`
- `GoogleSearchResult`, `FileSearchResult`
- `Step` (all 17 cases + `.unknown`)
- `JSONSchemaValueWrapper` (private decoding helper)
- `InteractionTool` (all tool types including `.function`)
- `InteractionInput`, `GenerationConfig`, `ResponseFormat`, `ResponseDelivery`, `AudioOutputMimeType`
- `NetworkAllowlistEntry`, `EnvironmentNetwork`, `EnvironmentSource`, `EnvironmentConfig`, `WebhookConfig`
- `InteractionRequest`, `Usage`, `Interaction`
- `User()`, `FunctionOutput()` convenience constructors
- All `InteractionConfigParameter` conformances (17 params)
- `InteractionConfigBuilder`, `StepsBuilder`, `ToolsBuilder` result builders
- `InteractionsClient` actor: `init`, `send()`, `get()`, `delete()`, `cancel()`, private helpers
- `@_exported import SwiftLLMToolMacros`

### Streaming.swift (extracted from SwiftGeminiInteractions.swift)

Always compiled. Extension on `InteractionsClient`:

- `InteractionStreamDelta` enum
- `InteractionStreamEvent` enum
- `stream(_ request:) -> AsyncThrowingStream<InteractionStreamEvent, Error>`
- `resumeStream(id:, lastEventId:) -> AsyncThrowingStream<InteractionStreamEvent, Error>`
- `private nonisolated func lineStream(from:)` helper
- `private func parseSSE(_:) -> InteractionStreamEvent?` helper

### BackgroundPolling.swift (extracted from SwiftGeminiInteractions.swift)

Always compiled. Extension on `InteractionsClient`:

- `poll(id:, timeout:, interval:) -> Interaction`

### ToolSession.swift

Unchanged content, wrapped:

```swift
#if ToolSession
// existing contents
#endif
```

### Agent.swift

Unchanged content, wrapped:

```swift
#if Agent
// existing contents
#endif
```

---

## Package.swift Trait Declarations

```swift
traits: [
    .trait(
        "ToolSession",
        description: "Multi-turn tool-calling loop with parallel function execution and usage tracking"
    ),
    .trait(
        "Agent",
        description: "Conversational agent wrapper with automatic tool execution and transcript",
        enabledTraits: ["ToolSession"]
    ),
    .trait(
        "Full",
        description: "ToolSession + Agent — all orchestration layers enabled",
        enabledTraits: ["ToolSession", "Agent"],
        isDefault: true
    ),
],
```

`Full` is the default. Zero-config consumers get everything. Consumers who want a minimal footprint declare `traits: ["ToolSession"]` (tools, no Agent) or omit traits on the dependency to get all features.

---

## Consumer Usage

```swift
// Package.swift — default (Full): all features, zero config
.package(url: "...", from: "1.0.0")

// ToolSession only — tool loop, no Agent wrapper
.package(url: "...", from: "1.0.0", traits: ["ToolSession"])

// Core only — direct API access, no tool orchestration
// Note: traits: [] explicitly disables all traits including the Full default.
// Omitting traits: entirely enables the Full default.
.package(url: "...", from: "1.0.0", traits: [])
```

---

## Documentation Updates

Three documents updated as part of this change:

**`docs/traits.md`** — dedicated user-facing explanation:
- What each trait enables
- Why Streaming and BackgroundPolling are always-on (and why that's the right call)
- When to choose a minimal trait set (embedded apps, CLI tools, cost-sensitive contexts)
- Migration note for consumers upgrading from a version without traits (Full is the default so no breaking change)

**`README.md`** — trait selection table added to the Installation section, consistent with sibling package style

**`CLAUDE.md`** — Trait Design section added covering the file map, the gating rationale, and the Package.swift structure

---

## Testing

No test changes required. The test target does not declare traits — it compiles all source files unconditionally via `testTarget` which inherits the full source set. Existing tests continue to cover all code paths.

Manual verification: build with `traits: []`, `traits: ["ToolSession"]`, and default (no traits). Confirm symbol availability matches expectations in each configuration using a scratch `Package.swift` that depends on a local path.
