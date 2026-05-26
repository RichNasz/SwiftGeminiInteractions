---
status: alpha
---

# SwiftGeminiInteractions Documentation Design

**Date:** 2026-05-25
**Status:** Approved
**Audience:** Both newcomers and experienced Swift developers; AI coding tools (AGENTS.md)

## Goal

Replace the current scattered documentation with a progressive-disclosure documentation suite: a lean README, topic-focused guides, an AGENTS.md for AI coding tools, and DocC comments on all public API surface.

## Principles

1. **Progressive disclosure** — README shows only install + one example. Guides introduce one concept at a time, building on previous guides.
2. **Start fresh** — Existing docs (`built-in-tools.md`, `structured-output.md`, `background-interactions.md`) are folded into topic guides and removed. `Spec/` internal reference stays untouched.
3. **Two audiences** — Humans read markdown guides; AI tools read AGENTS.md. Neither duplicates the other — AGENTS.md is structured for machine consumption with patterns and pitfalls.
4. **DocC for API reference** — Doc comments on all public types and methods. No DocC catalog bundle — just inline comments that Xcode and docc can render.

---

## 1. README.md

**Purpose:** Landing page. Gets the reader from zero to first request in under 60 seconds of reading.

**Target length:** ~80 lines.

**Structure:**
- Badge row: Swift version, Platform, License, Version, Built with Claude Code
- One-sentence description
- Swift Package Manager install snippet (Package.swift dependency)
- One minimal code example: create client, send request, print output
- Feature bullet list (links to guides): streaming, tools, agent, config, background
- Link to AGENTS.md for AI coding tools
- License

**What gets removed from current README:** All multi-section feature explanations, inline code for streaming/tools/agent/config. These move into dedicated guides.

---

## 2. docs/getting-started.md

**Purpose:** First guide a new user reads after README. Covers client setup and the mental model.

**Sections:**
1. **Creating an InteractionsClient** — API key from environment, custom base URL, API revision header
2. **Your first request** — `InteractionRequest`, `InteractionInput.text`, `client.send()`, reading `Interaction` response
3. **Understanding Interaction and Step** — The `Interaction` response type, `outputText` convenience, the `Step` enum (17 cases), `Content` types
4. **Multi-turn with previousInteractionId** — Manual chaining with `PreviousInteractionId` config param and `Store(true)`
5. **Where to go next** — Links to streaming, tools, agent guides

---

## 3. docs/streaming.md

**Purpose:** Real-time event streaming.

**Sections:**
1. **Basic streaming** — `client.stream(request)`, iterating `AsyncThrowingStream<InteractionStreamEvent, Error>`
2. **Event types** — `interactionStarted`, `stepStart`, `contentDelta`, `interactionCompleted`, `unknown`
3. **Working with deltas** — `InteractionStreamDelta` text accumulation pattern
4. **Resuming interrupted streams** — `resumeStream(id:)`, when to use it
5. **Error handling in streams** — What errors surface, how to recover

---

## 4. docs/tools.md

**Purpose:** Function calling and built-in tools. This is the most complex guide.

**Sections:**
1. **Concepts** — Function tools (local handlers) vs built-in tools (server-side). `InteractionTool` enum.
2. **ToolSession basics** — Creating a `ToolSession`, registering handlers, `run()` method, `ToolSessionResult`
3. **The @LLMTool macro** — Defining tools with the macro: `Arguments` struct, `call()` method, `toolDefinition`. How the macro generates JSON schema from the struct.
4. **Built-in tools** — `.googleSearch`, `.codeExecution`, `.fileSearch`, `.googleMaps`, `.urlContext`. No handler needed — server executes them.
5. **Mixing tool types** — Combining function tools and built-in tools in one session
6. **Tool choice** — `ToolChoiceMode`, `ToolChoiceConfig`, forcing specific tools
7. **Streaming with tools** — `ToolSessionEvent` enum, `session.stream()`, event lifecycle
8. **Advanced** — `maxIterations`, `ToolCallLogEntry`, parallel tool calls

---

## 5. docs/agent.md

**Purpose:** The `Agent` actor for multi-turn conversations with tools.

**Sections:**
1. **What Agent adds over ToolSession** — Automatic chaining, transcript tracking, usage aggregation, simple send/stream API
2. **Creating an Agent** — `model:` initializer, tools via `@AgentToolBuilder`, config via `@InteractionConfigBuilder`
3. **Multi-turn conversations** — `agent.send()` chains automatically, `reset()` to start over
4. **AgentTool** — Direct init (tool + handler) vs `LLMTool`-conforming init
5. **Streaming** — `agent.stream()`, mapping `ToolSessionEvent` values
6. **Transcript** — `TranscriptEntry` enum, reading the transcript for logging/debugging
7. **Named agents** — `agent:` initializer, how it differs from `model:`, `AgentIdentifierParam` behavior
8. **Usage tracking** — `lastUsage`, `totalUsage` from tool iterations

---

## 6. docs/configuration.md

**Purpose:** All 17 config parameters, result builders, and response format options.

**Sections:**
1. **InteractionConfigParameter protocol** — `apply(to:)` method, how params modify `InteractionRequest`
2. **Using @InteractionConfigBuilder** — Result builder syntax for composing params
3. **Parameter reference table** — All 17 params: name, type, default, what it does. Grouped by target (request-level vs generation config).
4. **GenerationConfig params:** Temperature, TopP, TopK, MaxOutputTokens, Seed, StopSequences, ThinkingLevel, ThinkingSummaries
5. **Request-level params:** Model, SystemInstruction, Store, PreviousInteractionId, ServiceTier, ResponseModalities, MaxToolCalls, RequestTimeout, ResponseFormat
6. **Structured output** — `ResponseFormat.text(mimeType: "application/json", schema:)`, `JSONSchemaValue` builder, extracting typed results
7. **Response modalities** — Text, document, image, audio response formats
8. **Environment config** — `EnvironmentConfig` for code execution sandboxes

---

## 7. docs/error-handling.md

**Purpose:** Every error case, when it fires, and how to recover.

**Sections:**
1. **GeminiInteractionsError enum** — All cases listed with descriptions
2. **HTTP errors** — `httpError(statusCode:body:)` — 400, 401, 403, 429, 500 patterns
3. **Rate limiting** — `rateLimitExceeded`, retry-after, backoff strategies
4. **Tool errors** — `toolExecutionFailed`, `maxIterationsExceeded`
5. **Polling errors** — `pollTimeout`, `interactionFailed`
6. **Decoding errors** — `decodingFailed`, common causes
7. **Recovery patterns** — Retry wrappers, graceful degradation

---

## 8. docs/background-and-polling.md

**Purpose:** Long-running interactions and webhook-based flows.

**Sections:**
1. **When to use background interactions** — Code execution, large file processing, long-running agent tasks
2. **Starting a background interaction** — Setting up the request, getting the interaction ID
3. **Polling** — `client.poll(id:)`, poll interval, timeout configuration
4. **Webhooks** — `WebhookConfig`, notification endpoints, user metadata
5. **Retrieving results** — `client.get(id:)`, `client.cancel(id:)`, `client.delete(id:)`

---

## 9. docs/traits.md

**Purpose:** Explaining the trait system for selective compilation.

**Kept mostly as-is** from the current `docs/traits.md`. Minor updates:
- Link to the new guide structure
- Clarify which guides cover trait-gated features (tools → ToolSession trait, agent → Agent trait)

---

## 10. AGENTS.md

**Purpose:** Machine-readable patterns and pitfalls for AI coding tools (Claude Code, Copilot, Cursor, etc.).

**Structure:** Each section follows a consistent pattern:

```
## Topic

### Pattern
<code example showing the correct way>

### Pitfalls
- <common mistake and why it fails>
```

**Sections:**
1. **Project overview** — What the library does, package structure, trait system
2. **Basic request** — Creating client, sending request, reading response
3. **Streaming** — `client.stream()`, event handling, delta accumulation
4. **Tools** — ToolSession setup, handler registration, @LLMTool macro usage
5. **Agent** — Agent creation, multi-turn, tool registration
6. **Configuration** — Config params, result builder, structured output
7. **Background interactions** — poll(), webhooks, get/cancel/delete
8. **Testing** — MockURLProtocol pattern, test client creation, integration test env vars
9. **Common mistakes** — Cross-cutting pitfalls: manual previousInteractionId with Agent, missing `store: true`, trait gates, error types

**Key pitfalls to document:**
- Setting `PreviousInteractionId` manually when using Agent or ToolSession (they manage chaining)
- Forgetting `Store(true)` for manual multi-turn (required for previousInteractionId)
- Not handling `.unknown` stream events (forward compatibility)
- Registering handlers for built-in tools (server-side, no handler needed)
- Using `#if Agent` without enabling the Agent trait
- Wrapping errors instead of letting `GeminiInteractionsError` propagate

---

## 11. DocC Comments

**Scope:** All public types, methods, properties, and enum cases across:
- `Core.swift`
- `Streaming.swift`
- `BackgroundPolling.swift`
- `ToolSession.swift`
- `Agent.swift`

**Style:**
- One-line summary for simple properties
- Summary + Parameters + Returns for methods
- Summary + discussion for complex types
- No multi-paragraph docstrings — keep concise
- Use `/// - Parameter name:` format
- Cross-reference related types with `` `TypeName` `` backtick syntax

---

## 12. File Changes Summary

**Create:**
- `docs/getting-started.md`
- `docs/streaming.md`
- `docs/tools.md`
- `docs/agent.md`
- `docs/configuration.md`
- `docs/error-handling.md`
- `docs/background-and-polling.md`
- `AGENTS.md`

**Rewrite:**
- `README.md` (lean down to ~80 lines)
- `docs/traits.md` (minor link updates)

**Remove:**
- `docs/built-in-tools.md` (content folded into `docs/tools.md`)
- `docs/structured-output.md` (content folded into `docs/configuration.md`)
- `docs/background-interactions.md` (content folded into `docs/background-and-polling.md`)

**Modify (DocC comments):**
- `Sources/SwiftGeminiInteractions/Core.swift`
- `Sources/SwiftGeminiInteractions/Streaming.swift`
- `Sources/SwiftGeminiInteractions/BackgroundPolling.swift`
- `Sources/SwiftGeminiInteractions/ToolSession.swift`
- `Sources/SwiftGeminiInteractions/Agent.swift`

**Untouched:**
- `Spec/` (internal reference, stays as-is)
- `Examples/` (stays as-is — examples are self-contained and already match current API)
- `CLAUDE.md` (architecture notes for contributors, stays)

---

## Verification

- All code examples in guides must compile (verified by extracting and building)
- All links between guides resolve
- AGENTS.md patterns match current API (verified against source)
- DocC comments render correctly in Xcode Quick Help
- README example runs successfully
