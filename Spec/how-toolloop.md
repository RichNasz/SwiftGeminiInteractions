# how-toolloop.md — Tool Loop Algorithm

## store: true enforcement
`ToolSession.buildRequest(model:input:previousId:configParams:)` (private helper) applies all `configParams` by calling `param.apply(to: &request)` in order, then unconditionally sets `request.store = true` **after** the params loop. This means no config parameter — including `Store(false)` — can disable storage when using `ToolSession`. The last write wins and it always writes `true`.

## previous_interaction_id chaining
On the first iteration, `previousId` is `nil` and `buildRequest` sets `request.previousInteractionId = nil` (left as nil). After each successful LLM call, `previousId` is updated to `interaction.id`. On subsequent iterations, `buildRequest` assigns `request.previousInteractionId = previousId`, linking the new request to the prior interaction on the server. This is how context is maintained without re-sending the full conversation history.

## Concurrent function call execution
All `functionCall` steps in a single iteration's response are executed concurrently using `withThrowingTaskGroup(of: ToolResult.self)`. Each call is dispatched as a separate child task via `group.addTask`. The group `for try await result in group` loop collects results as they complete (in completion order, not submission order).

## Re-sorting by original step index
After the task group completes, results are in arbitrary completion order. To ensure the function_result steps are presented to the next LLM call in the original step order (matching the model's function_call order), results are re-sorted. In `run()`, the reorder is done by iterating `functionCalls` (which preserves the original order) and finding the matching `toolResults` entry by `callId`. In `stream()`, each result carries its original `index` field (the step index from `interaction.steps.enumerated()`) and the collected results are sorted by that index before building the next input.

## Handler error capture
If a handler closure throws an error, the error is caught within the task group child task. The error is converted to a string via `"Error: \(String(describing: error))"` and returned as the tool result output with `isError = true`. The error is **never** rethrown out of the task group or the tool loop — it is captured as a string result. This means tool handler failures are surfaced to the model as error-flagged function results, not as thrown errors to the caller.

## Missing handler error
If a `functionCall` step names a tool for which no entry exists in `handlers`, the output is set to `"Error: No handler registered for tool '\(name)'"` with `isError = true`. Like handler exceptions, this is captured as a string result, not a thrown error.

## maxIterations enforcement
In `run()`, the guard `guard iterations < maxIterations` is checked at the top of the while loop before each LLM call. When `iterations` reaches `maxIterations` without a terminal status, `GeminiInteractionsError.maxIterationsExceeded(maxIterations)` is thrown, carrying the configured limit. In `stream()`, the loop condition is `while iteration < maxIterations`; if the loop exits the while body without returning, the code after the loop throws `GeminiInteractionsError.maxIterationsExceeded(maxIterations)`.

## stream() function call extraction
In `ToolSession.stream()`, function calls are not available from intermediate SSE events. Instead, the code waits for the `interactionCompleted` SSE event, extracts `interaction.steps` from it, and uses `enumerated().compactMap` to collect all `.functionCall` steps with their original step indices. If the completed interaction has no function calls or has a terminal `isComplete` status, the stream finishes normally without throwing.
