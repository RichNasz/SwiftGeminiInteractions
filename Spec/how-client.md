---
status: alpha
---

# how-client.md — HTTP Construction, Headers, and Error Wrapping

## Base URL
`https://generativelanguage.googleapis.com`. All interaction endpoints are under the path `v1beta/interactions`. The collection URL is `https://generativelanguage.googleapis.com/v1beta/interactions`. A single-interaction URL appends the id: `…/v1beta/interactions/{id}`. The cancel sub-resource appends `/cancel`: `…/v1beta/interactions/{id}/cancel`.

## Required headers on every request
Every outgoing `URLRequest` always carries:
- `x-goog-api-key: <apiKey>` — the API key provided at init time.
- `Api-Revision: <apiRevision>` — defaults to `"2026-05-20"`. Configurable at `InteractionsClient` init time as the `apiRevision` parameter.

## Content-Type header
`Content-Type: application/json` is added **only** when the request has a body (i.e. when `body != nil` in `makeRequest`). GET and DELETE requests carry no body and therefore no `Content-Type` header.

## HTTP status handling
- **2xx (200–299)** — success; the response body `Data` is returned for further decoding.
- **429** — throws `GeminiInteractionsError.rateLimitExceeded` (no body inspected).
- **Any other non-2xx** — throws `GeminiInteractionsError.httpError(statusCode: httpResponse.statusCode, body: <UTF-8 body string or empty string>)`.
- **Non-HTTP response** — throws `GeminiInteractionsError.httpError(statusCode: 0, body: "No HTTP response")`.

## URLError wrapping
The `execute(_:)` method catches `URLError` specifically and rethrows as `GeminiInteractionsError.networkError(urlError)`. All other errors propagate unmodified (they are expected to be `GeminiInteractionsError` already from encoding/decoding helpers).

## URLSession injection for testing
`InteractionsClient` has two initializers:
- `public init(apiKey: String, apiRevision: String = "2026-05-20")` — creates `URLSession.shared` internally. This is the only public init.
- `init(apiKey: String, apiRevision: String = "2026-05-20", session: URLSession)` — internal (no `public` modifier). Accepts a caller-provided `URLSession`, used in unit tests configured with `MockURLProtocol` as a protocol handler.

## Retry with backoff
`InteractionsClient` accepts an optional `RetryPolicy?` at init time (default: `RetryPolicy()`, nil disables retry). The retry logic lives in a private helper method that both `execute(_:)` and `executeReturningResponse(_:)` call.

**Retry loop algorithm:**
1. For each attempt (1 to `maxAttempts`):
   - Set `urlRequest.timeoutInterval` to `min(initialTimeout * pow(timeoutMultiplier, attempt - 1), maxTimeout)`, converted to `TimeInterval`.
   - Call `session.data(for: urlRequest)`.
   - On success (2xx): return result.
   - On `URLError.timedOut` and attempts remain: call `onRetry` callback, sleep for backoff duration, continue.
   - On HTTP status in `retryableStatusCodes` and attempts remain: call `onRetry`, sleep, continue. For 429, if `Retry-After` header is present (integer seconds), use it as backoff instead of calculated backoff.
   - On other errors: throw immediately (not retryable).
2. After all attempts exhausted: throw the last error.
3. Backoff calculation: `initialBackoff * pow(backoffMultiplier, attempt - 1)`.

When `retryPolicy` is `nil`, the client makes a single attempt with no timeout adjustment (matching pre-retry behavior).

The `RequestTimeout` config parameter has been removed. Timeout configuration is now handled by `RetryPolicy.initialTimeout`.

## File search store endpoints
File search store management lives under `v1beta/fileSearchStores` (not `v1beta/interactions`). URL helpers in `FileSearchStores.swift` construct paths against the same `baseURL`. The `name` fields from the API are full resource paths (e.g. `fileSearchStores/my-store-123`), so URL helpers append them directly to `{baseURL}/v1beta/`.

The upload endpoint uses a different path prefix: `{baseURL}/upload/v1beta/{storeName}:uploadToFileSearchStore` (note `/upload/` before `v1beta`).

List endpoints auto-paginate using `pageSize=20` query parameter and `pageToken`/`nextPageToken` fields. Both store and document list methods consume all pages and return a single array.

Delete endpoints accept a `force` boolean query parameter. When `force=true`, cascade-deletes child resources. When `force=false` (default), returns `FAILED_PRECONDITION` if the resource has children.

## Upload protocol
Document upload uses Google's resumable upload protocol (not multipart/related):

**Step 1 — Initiate:** POST to the upload URI with `Content-Type: application/json` body containing metadata fields (`displayName`, `customMetadata`, `mimeType`). Custom headers: `X-Goog-Upload-Protocol: resumable`, `X-Goog-Upload-Command: start`, `X-Goog-Upload-Header-Content-Length: {byteCount}`, `X-Goog-Upload-Header-Content-Type: {mimeType}`. Standard auth headers included. Response contains `x-goog-upload-url` header with the upload URL.

**Step 2 — Upload bytes:** POST raw file bytes to the upload URL from step 1. Headers: `X-Goog-Upload-Offset: 0`, `X-Goog-Upload-Command: upload, finalize`, `Content-Length: {byteCount}`. Response is an `Operation` JSON object.

**Step 3 — Poll:** GET the operation URL until `done == true`. On success, `response` contains the `FileSearchDocument`. On failure, `error` contains code and message. Poll interval: 1 second. Timeout: 5 minutes.

The initiation step requires `executeReturningResponse(_:)` (internal method on `InteractionsClient`) which returns `(Data, HTTPURLResponse)` so the caller can read the `x-goog-upload-url` response header. This method shares all error-handling logic with `execute(_:)`.
