# Agent

Agent is an actor wrapping ToolSession with automatic chaining, transcript tracking, and usage aggregation. It requires the Agent trait (enabled by default), which automatically enables ToolSession.

## Creating an Agent

The simplest agent takes a client and model:

```swift
let client = InteractionsClient(apiKey: "YOUR_API_KEY")
let agent = try Agent(client: client, model: "gemini-2.5-flash-preview-05-20")

let reply = try await agent.send("What is the capital of France?")
print(reply)
```

### With tools

Define tools using the `@LLMTool` macro and pass them via the `@AgentToolBuilder`:

```swift
@LLMTool(description: "Get current weather for a city")
struct GetWeather {
    struct Arguments: Codable {
        let city: String
        let units: String?
    }
    
    func call(arguments: Arguments) async throws -> ToolOutput {
        // Fetch weather data
        let temp = 72
        let conditions = "sunny"
        return ToolOutput(content: "\(temp)°F and \(conditions) in \(arguments.city)")
    }
}

let agent = try Agent(client: client, model: "gemini-2.5-flash-preview-05-20") {
    AgentTool(GetWeather())
}

let reply = try await agent.send("What's the weather in Paris?")
print(reply)
```

### With configuration and instructions

Use `@InteractionConfigBuilder` for config parameters and provide system instructions:

```swift
let agent = try Agent(
    client: client,
    model: "gemini-2.5-flash-preview-05-20",
    instructions: "You are a helpful weather assistant.",
    maxToolIterations: 5
) {
    AgentTool(GetWeather())
} config: {
    Temperature(0.7)
    MaxOutputTokens(512)
}
```

## Multi-turn Conversations

`agent.send()` automatically chains interactions via `previousInteractionId` and sets `store: true`. Each call builds on the previous conversation:

```swift
let agent = try Agent(client: client, model: "gemini-2.5-flash-preview-05-20")

let reply1 = try await agent.send("My name is Alice.")
print(reply1)  // "Nice to meet you, Alice!"

let reply2 = try await agent.send("What's my name?")
print(reply2)  // "Your name is Alice."
```

### Resetting the conversation

Call `agent.reset()` to clear the chain and start fresh:

```swift
await agent.reset()
let newReply = try await agent.send("What's my name?")
print(newReply)  // "I don't know your name."
```

## AgentTool

AgentTool pairs an `InteractionTool` definition with a handler closure. There are two ways to create one:

### From an @LLMTool type (recommended)

The `@LLMTool` macro generates a `ToolDefinition` and the agent automatically wires up the handler:

```swift
@LLMTool(description: "Calculate the sum of two numbers")
struct Add {
    struct Arguments: Codable {
        let a: Int
        let b: Int
    }
    
    func call(arguments: Arguments) async throws -> ToolOutput {
        let sum = arguments.a + arguments.b
        return ToolOutput(content: "\(sum)")
    }
}

let agent = try Agent(client: client, model: "gemini-2.5-flash-preview-05-20") {
    AgentTool(Add())
}
```

### Manual init

For custom tools not using the macro, provide the tool definition and handler directly:

```swift
let schema = JSONSchemaValue.object(
    properties: [("query", .string(description: "SQL query to execute"))],
    required: ["query"]
)

let agent = try Agent(client: client, model: "gemini-2.5-flash-preview-05-20") {
    AgentTool(
        tool: .function(name: "run_sql", description: "Executes a SQL query", parameters: schema),
        handler: { args in
            // Parse args and execute query
            return "Query executed successfully"
        }
    )
}
```

**Note:** If duplicate tool names are detected, the agent's initializer throws `GeminiInteractionsError.invalidInput`.

## Streaming

`agent.stream()` returns an `AsyncThrowingStream<ToolSessionEvent, Error>`. It yields events as the model generates its response and executes tools:

```swift
for try await event in agent.stream("What's the weather in Paris?") {
    switch event {
    case .iterationStarted(let n):
        print("Iteration \(n) started")
    case .llm(let llmEvent):
        if case .delta(let delta) = llmEvent {
            print(delta.text ?? "", terminator: "")
        }
    case .toolCallStarted(let callId, let name, let arguments):
        print("Tool call: \(name)(\(arguments))")
    case .toolCallCompleted(let callId, let name, let output, let duration):
        print("Result: \(output) in \(duration)")
    case .usageUpdate(let usage, let iteration):
        print("Iteration \(iteration) used \(usage.totalTokens) tokens")
    }
}
```

**Note:** If no tools are registered, `stream()` falls through to `client.stream()` directly and yields only `.llm` events.

## Transcript

`agent.transcript` returns an array of `TranscriptEntry` values recording the entire conversation history:

```swift
let agent = try Agent(client: client, model: "gemini-2.5-flash-preview-05-20") {
    AgentTool(GetWeather())
}

_ = try await agent.send("What's the weather in London?")

let transcript = await agent.transcript
for entry in transcript {
    switch entry {
    case .userMessage(let msg):
        print("User: \(msg)")
    case .assistantMessage(let msg):
        print("Assistant: \(msg)")
    case .toolCall(let name, let arguments):
        print("Tool call: \(name)(\(arguments))")
    case .toolResult(let name, let result, let duration):
        print("Tool result: \(name) -> \(result) [\(duration)]")
    case .thought(let content):
        print("Thought: \(content)")
    case .builtInToolCall(let type):
        print("Built-in tool: \(type)")
    case .error(let msg):
        print("Error: \(msg)")
    }
}
```

`agent.reset()` clears the transcript along with the conversation chain.

## Named Agents

Instead of a model string, you can target a named Gemini agent:

```swift
let agent = try Agent(
    client: client,
    agent: "deep-research-pro-preview-04-2026",
    instructions: "Conduct thorough research on the topic."
)

let reply = try await agent.send("What are the latest developments in quantum computing?")
print(reply)
```

When using the `agent:` initializer, the request sends an `agent` field instead of `model`. If tools are present, a private `AgentIdentifierParam` overrides the model field that `ToolSession.buildRequest` sets, replacing it with the `agent` field.

## Usage Tracking

`agent.lastUsage` holds the token usage from the most recent completed interaction:

```swift
let agent = try Agent(client: client, model: "gemini-2.5-flash-preview-05-20")
_ = try await agent.send("Hello!")

if let usage = await agent.lastUsage {
    print("Tokens: \(usage.totalTokens)")
    print("Input: \(usage.totalInputTokens)")
    print("Output: \(usage.totalOutputTokens)")
}
```

When tools are active, `lastUsage` reflects the **total usage** across all tool iterations (from `ToolSessionResult.totalUsage`). For per-iteration usage, use `stream()` and watch for `.usageUpdate` events.

## What's Next

- [Configuration](configuration.md) — all 17 config parameters, structured output, response formats
- [Error Handling](error-handling.md) — error cases, recovery patterns
