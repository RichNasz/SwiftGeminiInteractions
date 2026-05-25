# Built-in Tools

Built-in tools are executed server-side by Gemini. You declare them in your request and the model invokes them automatically — no handler is needed on your side. Results appear as steps in the returned `Interaction`.

## Available built-in tools

### `.googleSearch` — web search

Lets the model search the web and ground its response in current results.

```swift
var request = InteractionRequest(input: .text("What happened in the Swift 6 release?"))
request.model = "gemini-3-flash-preview"
request.tools = [.googleSearch]
let interaction = try await client.send(request)
```

### `.codeExecution` — runs code

The model writes and executes code in a sandboxed environment and includes the output in its response.

```swift
var request = InteractionRequest(input: .text("Compute the first 20 Fibonacci numbers."))
request.model = "gemini-3-flash-preview"
request.tools = [.codeExecution]
let interaction = try await client.send(request)
```

### `.urlContext` — reads URLs

The model fetches and reads the content of URLs mentioned in the conversation.

```swift
var request = InteractionRequest(input: .text("Summarise https://swift.org/blog/swift-6-is-here/"))
request.model = "gemini-3-flash-preview"
request.tools = [.urlContext]
let interaction = try await client.send(request)
```

### `.fileSearch(storeNames:topK:metadataFilter:)` — searches uploaded files

Searches documents you have uploaded to a Gemini file store.

```swift
var request = InteractionRequest(input: .text("What does our privacy policy say about data retention?"))
request.model = "gemini-3-flash-preview"
request.tools = [.fileSearch(storeNames: ["legal-docs"], topK: 5, metadataFilter: nil)]
let interaction = try await client.send(request)
```

### `.googleMaps(latitude:longitude:enableWidget:)` — maps and places

Lets the model query Google Maps for local places, directions, or geographic data.

```swift
var request = InteractionRequest(input: .text("Find coffee shops near me."))
request.model = "gemini-3-flash-preview"
request.tools = [.googleMaps(latitude: 37.7749, longitude: -122.4194, enableWidget: true)]
let interaction = try await client.send(request)
```

### `.mcpServer` — MCP server integration

Routes tool calls to a Model Context Protocol server configured in your Gemini project. The server URL and credentials are configured server-side; no URL or headers are passed from the client.

```swift
var request = InteractionRequest(input: .text("List open GitHub issues for my repo."))
request.model = "gemini-3-flash-preview"
request.tools = [.mcpServer]
let interaction = try await client.send(request)
```

## Combining built-in tools with function tools

You can mix built-in tools with custom function tools in the same request. The model chooses which tool to call based on the conversation.

```swift
let schema = JSONSchemaValue.object(
    properties: [("query", .string(description: "SQL query to run"))],
    required: ["query"]
)

var request = InteractionRequest(input: .text("Search the web for context, then query our database."))
request.model = "gemini-3-flash-preview"
request.tools = [
    .googleSearch,
    .function(name: "run_sql", description: "Executes a SQL query", parameters: schema)
]
```

When using function tools alongside built-in tools, provide handlers only for your function tools (e.g. via `ToolSession`). Built-in tool calls are handled entirely by the server.
