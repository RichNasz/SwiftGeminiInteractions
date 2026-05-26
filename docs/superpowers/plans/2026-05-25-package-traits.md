# Package Traits Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the monolithic `SwiftGeminiInteractions.swift` into focused files and gate `ToolSession` and `Agent` behind Swift Package Traits, consistent with the SwiftSynapse ecosystem pattern.

**Architecture:** The 1,631-line `SwiftGeminiInteractions.swift` is split into `Core.swift`, `Streaming.swift`, and `BackgroundPolling.swift` — all always compiled, no `#if` guards. `ToolSession.swift` and `Agent.swift` gain `#if ToolSession` and `#if Agent` guards respectively, enabled by a `Full` default trait so zero-config consumers get everything. The design rationale (why Streaming/BackgroundPolling are not trait-gated) is documented for users.

**Tech Stack:** Swift 6.3, Swift Package Manager traits (`.trait(name:)` / `.default(enabledTraits:)`), `#if TraitName` conditional compilation.

**Spec:** `docs/superpowers/specs/2026-05-25-package-traits-design.md`

---

## File Map

| Action | File | Purpose |
|--------|------|---------|
| Create | `Sources/SwiftGeminiInteractions/Streaming.swift` | SSE parser, stream/resumeStream extensions, stream event types |
| Create | `Sources/SwiftGeminiInteractions/BackgroundPolling.swift` | poll() extension on InteractionsClient |
| Rename | `SwiftGeminiInteractions.swift` → `Core.swift` | Core types, config params, result builders, InteractionsClient (send/get/delete/cancel) |
| Modify | `Sources/SwiftGeminiInteractions/ToolSession.swift` | Add `#if ToolSession` / `#endif` around existing content |
| Modify | `Sources/SwiftGeminiInteractions/Agent.swift` | Add `#if Agent` / `#endif` around existing content |
| Modify | `Package.swift` | Add trait declarations and `.default(enabledTraits: ["Full"])` |
| Create | `docs/traits.md` | User-facing trait documentation with design rationale |
| Modify | `README.md` | Add trait selection table to Installation section |
| Modify | `CLAUDE.md` | Update File Map table; add Trait Design section |

---

### Task 1: Create Streaming.swift and remove streaming code from SwiftGeminiInteractions.swift

The streaming code (methods on `InteractionsClient` plus all streaming types) is extracted into a dedicated file. Both edits happen in this task so the package compiles at every step.

**Files:**
- Create: `Sources/SwiftGeminiInteractions/Streaming.swift`
- Modify: `Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift`

- [ ] **Step 1: Create Streaming.swift**

Create `Sources/SwiftGeminiInteractions/Streaming.swift` with this exact content:

```swift
// Sources/SwiftGeminiInteractions/Streaming.swift
import Foundation

// MARK: - stream / resumeStream

extension InteractionsClient {
    public nonisolated func stream(_ request: InteractionRequest) -> AsyncThrowingStream<InteractionStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var r = request
                    r.store = true
                    let body = try await self.encode(r)
                    var components = URLComponents(url: await self.interactionsURL(), resolvingAgainstBaseURL: false)!
                    components.queryItems = [URLQueryItem(name: "stream", value: "true")]
                    let url = components.url!
                    let urlRequest = await self.makeRequest(url: url, method: "POST", body: body)
                    let session = await self.session
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: GeminiInteractionsError.httpError(statusCode: 0, body: "No HTTP response"))
                        return
                    }
                    guard (200...299).contains(httpResponse.statusCode) else {
                        continuation.finish(throwing: GeminiInteractionsError.httpError(statusCode: httpResponse.statusCode, body: ""))
                        return
                    }
                    let byteStream = AsyncThrowingStream<Data, Error> { bc in
                        Task {
                            do {
                                var lineBuffer = Data()
                                for try await byte in bytes {
                                    lineBuffer.append(byte)
                                    if byte == UInt8(ascii: "\n") {
                                        bc.yield(lineBuffer)
                                        lineBuffer = Data()
                                    }
                                }
                                if !lineBuffer.isEmpty { bc.yield(lineBuffer) }
                                bc.finish()
                            } catch {
                                bc.finish(throwing: error)
                            }
                        }
                    }
                    for try await event in parseSSE(from: byteStream) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public nonisolated func resumeStream(
        id: String,
        lastEventId: String
    ) -> AsyncThrowingStream<InteractionStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var components = URLComponents(url: await self.interactionURL(id: id), resolvingAgainstBaseURL: false)!
                    components.queryItems = [
                        URLQueryItem(name: "stream", value: "true"),
                        URLQueryItem(name: "last_event_id", value: lastEventId)
                    ]
                    let url = components.url!
                    let urlRequest = await self.makeRequest(url: url, method: "GET")
                    let session = await self.session
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode) else {
                        continuation.finish()
                        return
                    }
                    let byteStream = AsyncThrowingStream<Data, Error> { bc in
                        Task {
                            do {
                                var buf = Data()
                                for try await byte in bytes {
                                    buf.append(byte)
                                    if byte == UInt8(ascii: "\n") { bc.yield(buf); buf = Data() }
                                }
                                if !buf.isEmpty { bc.yield(buf) }
                                bc.finish()
                            } catch {
                                bc.finish(throwing: error)
                            }
                        }
                    }
                    for try await event in parseSSE(from: byteStream) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - InteractionStreamDelta

public enum InteractionStreamDelta: Sendable {
    case text(String)
    case image(Data)
    case functionCallArguments(delta: String, callId: String)
    case codeExecutionArguments(delta: String, id: String)
    case googleSearchQuery(String)
    case urlContextUrl(String)
    case thoughtSummary(String)
    case annotation(Annotation)
    case unknown

    private enum CodingKeys: String, CodingKey {
        case type, text, data, delta, id
        case callId = "call_id"
        case query, url, summary
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "image":
            self = .image(try container.decode(Data.self, forKey: .data))
        case "function_call_arguments":
            self = .functionCallArguments(
                delta: try container.decode(String.self, forKey: .delta),
                callId: try container.decode(String.self, forKey: .callId)
            )
        case "code_execution_arguments":
            self = .codeExecutionArguments(
                delta: try container.decode(String.self, forKey: .delta),
                id: try container.decode(String.self, forKey: .id)
            )
        case "google_search_query":
            self = .googleSearchQuery(try container.decode(String.self, forKey: .query))
        case "url_context_url":
            self = .urlContextUrl(try container.decode(String.self, forKey: .url))
        case "thought_summary":
            self = .thoughtSummary(try container.decode(String.self, forKey: .summary))
        case "annotation":
            self = .annotation(try Annotation(from: decoder))
        default:
            self = .unknown
        }
    }
}

// MARK: - InteractionStreamEvent

public enum InteractionStreamEvent: Codable, Sendable {
    case interactionCreated(Interaction)
    case interactionStatusUpdate(InteractionStatus)
    case stepStart(stepType: String, index: Int)
    case stepDelta(InteractionStreamDelta, stepIndex: Int)
    case stepStop(index: Int)
    case interactionCompleted(Interaction)
    case error(String)
    case unknown

    private enum CodingKeys: String, CodingKey {
        case eventType   = "event_type"
        case interaction, status, index, delta, message
        case stepType    = "step_type"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let eventType = try container.decode(String.self, forKey: .eventType)
        switch eventType {
        case "interaction.created":
            self = .interactionCreated(try container.decode(Interaction.self, forKey: .interaction))
        case "interaction.status_update":
            self = .interactionStatusUpdate(try container.decode(InteractionStatus.self, forKey: .status))
        case "step.start":
            self = .stepStart(
                stepType: try container.decode(String.self, forKey: .stepType),
                index: try container.decode(Int.self, forKey: .index)
            )
        case "step.delta":
            let delta = try container.decode(InteractionStreamDeltaWrapper.self, forKey: .delta)
            self = .stepDelta(delta.value, stepIndex: try container.decode(Int.self, forKey: .index))
        case "step.stop":
            self = .stepStop(index: try container.decode(Int.self, forKey: .index))
        case "interaction.completed":
            self = .interactionCompleted(try container.decode(Interaction.self, forKey: .interaction))
        case "error":
            self = .error(try container.decode(String.self, forKey: .message))
        default:
            self = .unknown
        }
    }

    public func encode(to encoder: any Encoder) throws {
        // Events are only received, never sent
    }
}

private struct InteractionStreamDeltaWrapper: Decodable {
    let value: InteractionStreamDelta
    init(from decoder: any Decoder) throws {
        value = try InteractionStreamDelta(from: decoder)
    }
}

// MARK: - SSE Parser

func parseSSE(from byteStream: AsyncThrowingStream<Data, Error>) -> AsyncThrowingStream<InteractionStreamEvent, Error> {
    AsyncThrowingStream { continuation in
        Task {
            do {
                var buffer = Data()
                let decoder = JSONDecoder()

                func processCompleteEvents() throws {
                    while let range = buffer.range(of: Data("\n\n".utf8)) {
                        let eventData = buffer[buffer.startIndex..<range.lowerBound]
                        buffer.removeSubrange(buffer.startIndex...range.upperBound - 1)
                        let lines = String(data: eventData, encoding: .utf8)?.components(separatedBy: "\n") ?? []
                        for line in lines {
                            guard line.hasPrefix("data: ") else { continue }
                            let jsonStr = String(line.dropFirst("data: ".count))
                            guard let jsonData = jsonStr.data(using: .utf8) else { continue }
                            let event = try decoder.decode(InteractionStreamEvent.self, from: jsonData)
                            if case .unknown = event { continue }
                            continuation.yield(event)
                        }
                    }
                }

                for try await chunk in byteStream {
                    buffer.append(chunk)
                    try processCompleteEvents()
                }

                if !buffer.isEmpty {
                    let lines = String(data: buffer, encoding: .utf8)?.components(separatedBy: "\n") ?? []
                    for line in lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst("data: ".count))
                        guard let jsonData = jsonStr.data(using: .utf8) else { continue }
                        let event = try decoder.decode(InteractionStreamEvent.self, from: jsonData)
                        if case .unknown = event { continue }
                        continuation.yield(event)
                    }
                }

                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}
```

- [ ] **Step 2: Remove the streaming sections from SwiftGeminiInteractions.swift**

In `Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift`, find and remove the block that begins with `public nonisolated func stream(` and ends with the final `}` of the file (line 1631). This includes `stream()`, `resumeStream()`, the closing `}` of the `InteractionsClient` actor, and all content from `// MARK: - InteractionStreamDelta` to the end.

Then add a new closing `}` for the `InteractionsClient` actor immediately after the closing `}` of the `poll()` method.

The end of the file should now be:

```swift
    public func poll(
        id: String,
        timeout: Duration = .seconds(300),
        interval: Duration = .seconds(5)
    ) async throws -> Interaction {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            let interaction = try await get(id: id)
            if interaction.isComplete { return interaction }
            let remaining = deadline - clock.now
            if remaining > .zero {
                try await Task.sleep(for: min(interval, remaining))
            }
        }
        throw GeminiInteractionsError.pollTimeout(id: id)
    }
}
```

- [ ] **Step 3: Run tests to verify**

```bash
swift test --package-path /Users/rnaszcyn/Development/SwiftLLMapis/SwiftGeminiInteractions 2>&1 | tail -10
```

Expected: All tests pass. No compile errors.

- [ ] **Step 4: Commit**

```bash
cd /Users/rnaszcyn/Development/SwiftLLMapis/SwiftGeminiInteractions
git add Sources/SwiftGeminiInteractions/Streaming.swift Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift
git commit -m "refactor: extract Streaming.swift from monolithic source file"
```

---

### Task 2: Create BackgroundPolling.swift and remove poll() from SwiftGeminiInteractions.swift

**Files:**
- Create: `Sources/SwiftGeminiInteractions/BackgroundPolling.swift`
- Modify: `Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift`

- [ ] **Step 1: Create BackgroundPolling.swift**

Create `Sources/SwiftGeminiInteractions/BackgroundPolling.swift` with this exact content:

```swift
// Sources/SwiftGeminiInteractions/BackgroundPolling.swift
import Foundation

// MARK: - poll

extension InteractionsClient {
    public func poll(
        id: String,
        timeout: Duration = .seconds(300),
        interval: Duration = .seconds(5)
    ) async throws -> Interaction {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            let interaction = try await get(id: id)
            if interaction.isComplete { return interaction }
            let remaining = deadline - clock.now
            if remaining > .zero {
                try await Task.sleep(for: min(interval, remaining))
            }
        }
        throw GeminiInteractionsError.pollTimeout(id: id)
    }
}
```

- [ ] **Step 2: Remove poll() from SwiftGeminiInteractions.swift**

In `Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift`, find and remove the entire `poll()` method. The end of the file should now be the closing `}` of `cancel()` followed by the `InteractionsClient` closing brace:

```swift
    public func cancel(id: String) async throws {
        let cancelURL = interactionURL(id: id).appendingPathComponent("cancel")
        let urlRequest = makeRequest(url: cancelURL, method: "POST")
        _ = try await execute(urlRequest)
    }
}
```

- [ ] **Step 3: Run tests**

```bash
swift test --package-path /Users/rnaszcyn/Development/SwiftLLMapis/SwiftGeminiInteractions 2>&1 | tail -10
```

Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
cd /Users/rnaszcyn/Development/SwiftLLMapis/SwiftGeminiInteractions
git add Sources/SwiftGeminiInteractions/BackgroundPolling.swift Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift
git commit -m "refactor: extract BackgroundPolling.swift from monolithic source file"
```

---

### Task 3: Rename SwiftGeminiInteractions.swift to Core.swift

Swift Package Manager includes all `.swift` files in `Sources/` automatically. Renaming is a `git mv` plus updating the file header comment.

**Files:**
- Rename: `Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift` → `Sources/SwiftGeminiInteractions/Core.swift`

- [ ] **Step 1: Rename the file**

```bash
cd /Users/rnaszcyn/Development/SwiftLLMapis/SwiftGeminiInteractions
git mv Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift Sources/SwiftGeminiInteractions/Core.swift
```

- [ ] **Step 2: Update the file header comment**

In `Sources/SwiftGeminiInteractions/Core.swift`, change the first line from:

```swift
// Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift
```

to:

```swift
// Sources/SwiftGeminiInteractions/Core.swift
```

- [ ] **Step 3: Run tests**

```bash
swift test --package-path /Users/rnaszcyn/Development/SwiftLLMapis/SwiftGeminiInteractions 2>&1 | tail -10
```

Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
cd /Users/rnaszcyn/Development/SwiftLLMapis/SwiftGeminiInteractions
git add Sources/SwiftGeminiInteractions/Core.swift Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift
git commit -m "refactor: rename SwiftGeminiInteractions.swift to Core.swift"
```

---

### Task 4: Update Package.swift with trait declarations

Traits must be declared in `Package.swift` before any `#if TraitName` guards are added to source files. Adding the `#if` guards first would cause those files to compile to nothing (because the trait is not yet defined as truthy), breaking the build.

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Replace the Package.swift content**

Replace the entire content of `Package.swift` with:

```swift
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "SwiftGeminiInteractions",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "SwiftGeminiInteractions", targets: ["SwiftGeminiInteractions"])
    ],
    traits: [
        // Leaf traits — each enables a specific orchestration subsystem
        .trait(
            name: "ToolSession",
            description: "Multi-turn tool-calling loop with parallel function execution and usage tracking"
        ),
        .trait(
            name: "Agent",
            description: "Conversational agent wrapper with automatic tool execution and transcript",
            enabledTraits: ["ToolSession"]
        ),

        // Composite trait — the recommended bundle
        .trait(
            name: "Full",
            description: "ToolSession + Agent — all orchestration layers enabled",
            enabledTraits: ["ToolSession", "Agent"]
        ),

        // Default — users who don't specify traits get everything
        .default(enabledTraits: ["Full"]),
    ],
    dependencies: [
        .package(url: "https://github.com/RichNasz/SwiftLLMToolMacros", branch: "main")
    ],
    targets: [
        .target(
            name: "SwiftGeminiInteractions",
            dependencies: ["SwiftLLMToolMacros"]
        ),
        .testTarget(
            name: "SwiftGeminiInteractionsTests",
            dependencies: ["SwiftGeminiInteractions"]
        )
    ]
)
```

- [ ] **Step 2: Run tests**

```bash
swift test --package-path /Users/rnaszcyn/Development/SwiftLLMapis/SwiftGeminiInteractions 2>&1 | tail -10
```

Expected: All tests pass. (No guards exist yet so this is a no-op change to the compiler.)

- [ ] **Step 3: Commit**

```bash
cd /Users/rnaszcyn/Development/SwiftLLMapis/SwiftGeminiInteractions
git add Package.swift
git commit -m "feat: add ToolSession, Agent, and Full package traits"
```

---

### Task 5: Add #if ToolSession guard to ToolSession.swift

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/ToolSession.swift`

- [ ] **Step 1: Add the guard**

In `Sources/SwiftGeminiInteractions/ToolSession.swift`, add `#if ToolSession` on the line immediately after `import Foundation`, and `#endif` as the very last line of the file.

The file should start:

```swift
// Sources/SwiftGeminiInteractions/ToolSession.swift
import Foundation

#if ToolSession

// MARK: - ToolCallLogEntry
```

And end:

```swift
// ... last line of existing content ...
}

#endif
```

- [ ] **Step 2: Run tests**

```bash
swift test --package-path /Users/rnaszcyn/Development/SwiftLLMapis/SwiftGeminiInteractions 2>&1 | tail -10
```

Expected: All tests pass. The `Full` default enables `ToolSession`, so the guard is true and all existing code compiles.

- [ ] **Step 3: Commit**

```bash
cd /Users/rnaszcyn/Development/SwiftLLMapis/SwiftGeminiInteractions
git add Sources/SwiftGeminiInteractions/ToolSession.swift
git commit -m "feat: gate ToolSession.swift behind #if ToolSession trait"
```

---

### Task 6: Add #if Agent guard to Agent.swift

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/Agent.swift`

- [ ] **Step 1: Add the guard**

In `Sources/SwiftGeminiInteractions/Agent.swift`, add `#if Agent` on the line immediately after `import Foundation`, and `#endif` as the very last line of the file.

The file should start:

```swift
// Sources/SwiftGeminiInteractions/Agent.swift
import Foundation

#if Agent

// MARK: - AgentTool
```

And end:

```swift
// ... last line of existing content ...
}

#endif
```

- [ ] **Step 2: Run tests**

```bash
swift test --package-path /Users/rnaszcyn/Development/SwiftLLMapis/SwiftGeminiInteractions 2>&1 | tail -10
```

Expected: All tests pass. The `Full` default enables `Agent`, so the guard is true.

- [ ] **Step 3: Commit**

```bash
cd /Users/rnaszcyn/Development/SwiftLLMapis/SwiftGeminiInteractions
git add Sources/SwiftGeminiInteractions/Agent.swift
git commit -m "feat: gate Agent.swift behind #if Agent trait"
```

---

### Task 7: Write docs/traits.md

**Files:**
- Create: `docs/traits.md`

- [ ] **Step 1: Create the file**

Create `docs/traits.md` with this content:

```markdown
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

### Migration

`Full` is the default trait. Existing consumers who upgrade from a version without traits will automatically get `Full` — no `Package.swift` changes required. Behavior is identical to before.
```

- [ ] **Step 2: Commit**

```bash
cd /Users/rnaszcyn/Development/SwiftLLMapis/SwiftGeminiInteractions
git add docs/traits.md
git commit -m "docs: add traits.md with design rationale and usage examples"
```

---

### Task 8: Update README.md with trait selection table

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add a Traits subsection to Installation**

In `README.md`, find the Installation section (after the `swift package add` / `Package.swift` snippet). Insert this block immediately after the existing dependency snippet:

```markdown
### Traits

By default you get all features. To reduce binary size, specify traits:

| Traits | What you get |
|--------|-------------|
| _(none specified)_ | Everything — `ToolSession`, `Agent`, streaming, polling |
| `["ToolSession"]` | Tool-calling loop, no `Agent` wrapper |
| `[]` | Core client only — `send()`, `stream()`, `get()`, `delete()`, `cancel()`, `poll()` |

```swift
// Core only — no tool orchestration
.package(url: "https://github.com/your-org/SwiftGeminiInteractions.git",
         branch: "main",
         traits: [])
```

See [docs/traits.md](docs/traits.md) for full details and design rationale.
```

- [ ] **Step 2: Run tests**

```bash
swift test --package-path /Users/rnaszcyn/Development/SwiftLLMapis/SwiftGeminiInteractions 2>&1 | tail -10
```

Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
cd /Users/rnaszcyn/Development/SwiftLLMapis/SwiftGeminiInteractions
git add README.md
git commit -m "docs: add trait selection table to README installation section"
```

---

### Task 9: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update the File Map table**

In `CLAUDE.md`, replace the existing File Map table:

```markdown
| File | Contents |
|------|----------|
| `Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift` | All core types, config params, result builders, InteractionsClient, SSE parser |
| `Sources/SwiftGeminiInteractions/ToolSession.swift` | ToolSession, ToolSessionResult, ToolCallLogEntry, ToolSessionEvent |
| `Sources/SwiftGeminiInteractions/Agent.swift` | Agent, AgentTool, AgentToolBuilder, TranscriptEntry |
```

with:

```markdown
| File | Trait gate | Contents |
|------|------------|---------|
| `Sources/SwiftGeminiInteractions/Core.swift` | always | All types, config params, result builders, InteractionsClient (send/get/delete/cancel) |
| `Sources/SwiftGeminiInteractions/Streaming.swift` | always | SSE parser, stream(), resumeStream(), InteractionStreamEvent, InteractionStreamDelta |
| `Sources/SwiftGeminiInteractions/BackgroundPolling.swift` | always | poll() |
| `Sources/SwiftGeminiInteractions/ToolSession.swift` | `#if ToolSession` | ToolSession, ToolSessionResult, ToolCallLogEntry, ToolSessionEvent |
| `Sources/SwiftGeminiInteractions/Agent.swift` | `#if Agent` | Agent, AgentTool, AgentToolBuilder, TranscriptEntry |
```

- [ ] **Step 2: Add a Trait Design section**

Add this section after the existing `## Key Design Decisions` block (before `## Spec Files`):

```markdown
## Trait Design

Two traits gate the optional orchestration subsystems:

| Trait | Source file | Auto-enables |
|-------|-------------|--------------|
| `ToolSession` | `ToolSession.swift` | — |
| `Agent` | `Agent.swift` | `ToolSession` |

`Full` (composite, default) enables both. Consumers who declare `traits: []` get only Core + Streaming + BackgroundPolling.

`Streaming.swift` and `BackgroundPolling.swift` are NOT trait-gated. Streaming is small (~250 lines) and universally needed; polling is a single function. The trait-gating cost (source guards, consumer config) is not justified for code that small. See `docs/traits.md` for the full rationale.

The Spec files in `Spec/` should be updated to reflect the new file boundaries if they reference the old `SwiftGeminiInteractions.swift` monolith.
```

- [ ] **Step 3: Commit**

```bash
cd /Users/rnaszcyn/Development/SwiftLLMapis/SwiftGeminiInteractions
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with new file map and trait design section"
```

---

## Verification

After all tasks are complete, verify three build configurations:

```bash
cd /Users/rnaszcyn/Development/SwiftLLMapis/SwiftGeminiInteractions

# 1. Full (default) — all symbols available
swift build 2>&1 | tail -5

# 2. All tests pass with full build
swift test 2>&1 | tail -10

# 3. Confirm trait-gated symbols are absent with traits: []
# Create a temporary scratch package that depends on this one with traits: []
# and verify that ToolSession and Agent types are not visible.
# (Manual check — no automated test for this; use a local package override.)
```

The test suite does not declare traits so it compiles all source files unconditionally — all tests continue to exercise the full API surface.
