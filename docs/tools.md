# Tools

Tools extend the Gemini model's capabilities by letting it call functions, search the web, execute code, and more. SwiftGeminiInteractions supports two kinds of tools: **built-in tools** that execute server-side, and **function tools** that run locally with your own handlers.

## Concepts

All tools are represented by the `InteractionTool` enum, which has seven cases:

- **Function tools** — `.function(name:description:parameters:)` defines a custom tool you implement. The model generates function calls, your code handles them, and you return results. Function tools require the **ToolSession trait** to execute the tool-calling loop automatically.

- **Built-in tools** — `.googleSearch`, `.codeExecution`, `.urlContext`, `.fileSearch(...)`, `.googleMaps(...)`, and `.mcpServer` execute entirely on the server. No local handler is needed. The model invokes them and the results appear as step pairs in the returned `Interaction`.

Both kinds can be mixed freely in a single request's `tools` array.

## Built-in Tools

Built-in tools are added to your request and invoked automatically by the model. Results appear as pairs of steps: a call step (e.g. `google_search_call`) followed by a result step (e.g. `google_search_result`).

### Adding a built-in tool

```swift
var request = InteractionRequest(input: .text("What happened in the Swift 6 release?"))
request.model = "gemini-2.5-flash-preview-05-20"
request.tools = [.googleSearch]

let interaction = try await client.send(request)
```

The model may choose to invoke the tool based on the conversation. When it does, the `interaction.steps` array will contain the search call and its results.

### Available built-in tools

| Tool | Description |
|------|-------------|
| `.googleSearch` | Lets the model search the web and ground its response in current results |
| `.codeExecution` | The model writes and executes code in a sandboxed environment |
| `.urlContext` | The model fetches and reads the content of URLs mentioned in the conversation |
| `.fileSearch(storeNames:topK:metadataFilter:)` | Searches documents uploaded to Gemini file stores |
| `.googleMaps(latitude:longitude:enableWidget:)` | Queries Google Maps for local places, directions, or geographic data |
| `.mcpServer` | Routes tool calls to a Model Context Protocol server configured in your Gemini project |

#### Example: Code execution

```swift
var request = InteractionRequest(input: .text("Compute the first 20 Fibonacci numbers."))
request.model = "gemini-2.5-flash-preview-05-20"
request.tools = [.codeExecution]

let interaction = try await client.send(request)
```

The model generates code, runs it server-side, and includes the output in its response steps.

#### Example: File search

```swift
var request = InteractionRequest(input: .text("What does our privacy policy say about data retention?"))
request.model = "gemini-2.5-flash-preview-05-20"
request.tools = [.fileSearch(storeNames: ["legal-docs"], topK: 5, metadataFilter: nil)]

let interaction = try await client.send(request)
```

This searches the `legal-docs` file store and returns the top 5 matching snippets.

#### Example: Google Maps

```swift
var request = InteractionRequest(input: .text("Find coffee shops near me."))
request.model = "gemini-2.5-flash-preview-05-20"
request.tools = [.googleMaps(latitude: 37.7749, longitude: -122.4194, enableWidget: true)]

let interaction = try await client.send(request)
```

The model uses the provided coordinates to query Google Maps and returns relevant places.

## ToolSession

To use function tools, you must enable the **ToolSession trait** (enabled by default via the `Full` trait). `ToolSession` manages the agentic loop: it sends your request, checks if function calls are required, executes the handlers concurrently, and chains subsequent requests via `previousInteractionId` until the model completes.

### Creating a ToolSession

```swift
import SwiftGeminiInteractions

let client = InteractionsClient(apiKey: "YOUR_API_KEY")

let tools: [InteractionTool] = [
    .function(
        name: "get_weather",
        description: "Fetches current weather for a city",
        parameters: .object(
            properties: [("city", .string(description: "City name"))],
            required: ["city"]
        )
    )
]

let handlers: [String: ToolSession.ToolHandler] = [
    "get_weather": { argsJSON in
        // argsJSON is a raw JSON string, e.g. {"city":"London"}
        // Parse it, call your API, return a string result
        return "Sunny, 22°C"
    }
]

let session = ToolSession(
    client: client,
    tools: tools,
    handlers: handlers,
    maxIterations: 10
)
```

### Running the session

```swift
let result = try await session.run(
    model: "gemini-2.5-flash-preview-05-20",
    input: [User("What's the weather in London?")],
    configParams: []
)

print(result.interaction.outputText ?? "(no output)")
print("Iterations: \(result.iterations)")
print("Total tokens: \(result.totalUsage?.totalTokens ?? 0)")
```

`run()` returns a `ToolSessionResult` when the loop completes.

### ToolSessionResult

| Property | Type | Description |
|----------|------|-------------|
| `interaction` | `Interaction` | The final interaction returned by the last API call |
| `iterations` | `Int` | Total number of LLM calls made during the session |
| `log` | `[ToolCallLogEntry]` | Ordered list of all tool calls across all iterations |
| `totalUsage` | `Usage?` | Summed token usage across all iterations; `nil` if no usage data was returned |

Each `ToolCallLogEntry` records:

- `name: String` — the tool's name
- `arguments: String` — the raw JSON arguments passed to the handler
- `result: String` — the handler's output (or an error message if it threw)
- `duration: Duration` — wall-clock time for the handler invocation

### How the loop works

1. `ToolSession` sends the request with `store: true` and the current `previousInteractionId` (nil on first call).
2. The model returns an interaction. If `status` is `.requiresAction`, the response contains `functionCall` steps.
3. All function calls are executed **concurrently** using `TaskGroup`. Handlers receive the raw JSON arguments string and return a string result.
4. Results are re-ordered to match the original step order, then wrapped in `functionResult` steps.
5. The next request is sent with `input: .steps([...])` containing those results, and `previousInteractionId` set to the previous interaction's ID.
6. Repeat until the model returns a terminal status or `maxIterations` is reached.

If a handler throws an error, the error is captured as a string and returned as an error-flagged result to the model — **the loop does not abort**.

If `maxIterations` is reached without completion, `GeminiInteractionsError.maxIterationsExceeded(maxIterations)` is thrown.

## The @LLMTool Macro

The `@LLMTool` macro from SwiftLLMToolMacros lets you define tools with strong typing and automatic JSON schema generation.

### Defining a tool with @LLMTool

```swift
import SwiftGeminiInteractions

@LLMTool("get_weather", "Fetches current weather for a city")
struct GetWeather {
    struct Arguments: Decodable {
        let city: String
    }
    
    func call(arguments: Arguments) async throws -> ToolOutput {
        // Fetch weather data from your API
        let weatherData = "Sunny, 22°C in \(arguments.city)"
        return ToolOutput(content: weatherData)
    }
}
```

The macro generates:

- A static `toolDefinition` property of type `ToolDefinition` containing the name, description, and generated JSON schema for `Arguments`.
- All the boilerplate needed to decode arguments and return `ToolOutput`.

### Using @LLMTool with ToolSession

Create the `InteractionTool` from the macro-generated `toolDefinition`:

```swift
let weatherTool = GetWeather()

let session = ToolSession(
    client: client,
    tools: [InteractionTool(GetWeather.toolDefinition)],
    handlers: [
        "get_weather": { argsJSON in
            let decoder = JSONDecoder()
            let args = try decoder.decode(GetWeather.Arguments.self, from: Data(argsJSON.utf8))
            let output = try await weatherTool.call(arguments: args)
            return output.content
        }
    ],
    maxIterations: 10
)
```

### Using @LLMTool with Agent

`Agent` provides a convenience initializer for `@LLMTool` structs. Pass an instance directly:

```swift
let agent = try Agent(client: client, model: "gemini-2.5-flash-preview-05-20") {
    AgentTool(GetWeather())
}
```

`AgentTool` extracts the tool definition and wraps the handler automatically.

## Mixing Tool Types

You can combine built-in tools and function tools in the same request. Only function tools need handlers.

```swift
let schema = JSONSchemaValue.object(
    properties: [("query", .string(description: "SQL query to run"))],
    required: ["query"]
)

let tools: [InteractionTool] = [
    .googleSearch,
    .function(name: "run_sql", description: "Executes a SQL query", parameters: schema)
]

let handlers: [String: ToolSession.ToolHandler] = [
    "run_sql": { argsJSON in
        // Parse and execute SQL
        return "[{\"id\":1,\"name\":\"Alice\"}]"
    }
]

let session = ToolSession(client: client, tools: tools, handlers: handlers)
```

The model can invoke `.googleSearch` server-side or call `run_sql` locally. Built-in tool results appear in `interaction.steps` as call/result step pairs; function tool results are handled by your handlers.

## Tool Choice

By default the model decides whether to use tools based on the conversation (`mode: .auto`). You can override this with `ToolChoiceConfig`.

### Forcing tool use

```swift
let config = ToolChoiceConfig(mode: .required, allowedTools: nil)

var request = InteractionRequest(input: .text("What's the weather in Paris?"))
request.model = "gemini-2.5-flash-preview-05-20"
request.tools = tools
request.generationConfig = GenerationConfig()
request.generationConfig?.toolChoice = config

let interaction = try await client.send(request)
```

### Tool choice modes

| Mode | Behaviour |
|------|-----------|
| `.auto` | Model decides whether to call tools (default) |
| `.none` | Model never calls tools |
| `.required` | Model must call at least one tool before responding |

### Restricting to specific tools

```swift
let config = ToolChoiceConfig(mode: .auto, allowedTools: ["get_weather", "get_forecast"])
```

The model may only call the tools listed in `allowedTools`. If `allowedTools` is `nil`, all declared tools are available.

## Streaming with Tools

`ToolSession.stream()` returns an `AsyncThrowingStream<ToolSessionEvent, Error>` that emits events as the tool loop progresses.

```swift
for try await event in session.stream(
    model: "gemini-2.5-flash-preview-05-20",
    input: [User("Check the weather and summarize the forecast.")],
    configParams: []
) {
    switch event {
    case .iterationStarted(let iteration):
        print("Iteration \(iteration) started")
        
    case .llm(let streamEvent):
        // Forward raw SSE events from client.stream()
        if case .delta(let delta) = streamEvent {
            print(delta.text ?? "", terminator: "")
        }
        
    case .toolCallStarted(let callId, let name, let arguments):
        print("\nCalling \(name) with \(arguments)")
        
    case .toolCallCompleted(let callId, let name, let output, let duration):
        print("Tool \(name) returned: \(output) in \(duration)")
        
    case .usageUpdate(let usage, let iteration):
        print("Iteration \(iteration) used \(usage.totalTokens) tokens")
    }
}
```

### ToolSessionEvent cases

| Event | When fired |
|-------|------------|
| `.iterationStarted(Int)` | At the start of each loop iteration |
| `.llm(InteractionStreamEvent)` | Forwards raw SSE events from the underlying `client.stream()` call |
| `.toolCallStarted(callId:name:arguments:)` | Immediately before a handler is invoked |
| `.toolCallCompleted(callId:name:output:duration:)` | After a handler returns (success or error) |
| `.usageUpdate(Usage, iteration:)` | After an `interactionCompleted` event if usage data is present |

Streaming mode executes handlers concurrently just like `run()`, but emits granular events so you can provide real-time feedback.

## What's Next

- **[Agent Guide](agent.md)** — High-level conversational agent with automatic tool handling and transcript management
- **[Configuration](configuration.md)** — Deep dive into all config parameters, generation settings, and service tiers
