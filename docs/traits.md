# Package Traits

SwiftGeminiInteractions uses Swift Package Traits to let you compile only the subsystems your app needs.

## Available Traits

| Trait | Enables | Auto-enables |
|-------|---------|--------------|
| `ToolSession` | Multi-turn tool-calling loop (`ToolSession`, `ToolSessionResult`, `ToolSessionEvent`) | — |
| `Agent` | Conversational agent wrapper (`Agent`, `AgentTool`, `TranscriptEntry`) | `ToolSession` |
| `Full` | Both orchestration layers | `ToolSession`, `Agent` |

**Default:** `Full` — if you don't specify traits, you get everything.

## Choosing a Configuration

```swift
// Package.swift

// Default — all features, zero config (most apps)
.package(url: "https://github.com/your-org/SwiftGeminiInteractions.git", branch: "main")

// ToolSession only — tool loop without the Agent wrapper
.package(url: "...", branch: "main", traits: ["ToolSession"])

// Core only — direct API client, no tool orchestration
// Note: traits: [] explicitly disables all traits including Full.
// Omitting traits: entirely uses the Full default.
.package(url: "...", branch: "main", traits: [])
```

## Design Rationale

### Why only ToolSession and Agent are trait-gated

Traits add complexity — `#if` guards in source files, a `traits:` declaration in `Package.swift`, and a new concept for consumers to learn. That cost is only worth paying when the excluded code is large enough to meaningfully affect build time or binary size, and when consumers have a realistic reason to exclude it.

**`ToolSession` and `Agent`** together are ~650 lines of orchestration logic that not every consumer needs. A service that calls the Gemini API directly — streaming responses, reading tool calls, building its own state machine — never instantiates a `ToolSession` or `Agent`. Excluding them removes that code from the binary entirely.

**Streaming** (`stream()`, `resumeStream()`, the SSE parser, `InteractionStreamEvent`, `InteractionStreamDelta`) is always compiled. Every consumer building an interactive application uses streaming. Not calling a function costs nothing at runtime, and the compile cost of ~250 lines is negligible compared to the ergonomic friction of requiring consumers to opt into streaming explicitly.

**Background polling** (`poll()`) is a single method. Same reasoning: the code is small, and consumers who don't use background jobs simply never call it.

This matches the pattern used across the SwiftSynapse ecosystem: gate the large, optional orchestration layers; leave the small infrastructure always-on.

### Guide Coverage by Trait

| Feature | Guide | Required Trait |
|---------|-------|----------------|
| Client, send, get, delete, cancel | [Getting Started](getting-started.md) | None (always available) |
| Streaming | [Streaming](streaming.md) | None (always available) |
| Polling | [Background & Polling](background-and-polling.md) | None (always available) |
| ToolSession | [Tools](tools.md) | `ToolSession` |
| Agent | [Agent](agent.md) | `Agent` |

### Migration

`Full` is the default trait. Existing consumers who upgrade from a version without traits will automatically get `Full` — no `Package.swift` changes required. Behavior is identical to before.
