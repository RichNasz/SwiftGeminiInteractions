# how-polling.md — Background Poll Algorithm

## Clock type
`ContinuousClock` is used for all deadline measurement, not `Date` or `DispatchTime`. `ContinuousClock` is monotonic and unaffected by system clock changes, making it suitable for measuring elapsed time.

## Deadline computation
At the start of `poll(id:timeout:interval:)`, the deadline is computed once: `let deadline = clock.now + timeout`. `timeout` is a `Duration` value (default `.seconds(300)`). `clock.now` returns a `ContinuousClock.Instant`.

## Poll loop structure
1. Check `clock.now < deadline`; if false, fall through to the timeout throw.
2. Call `get(id:)` to fetch the current interaction state.
3. If `interaction.isComplete` returns `true`, return the interaction immediately.
4. Compute remaining time: `let remaining = deadline - clock.now`.
5. If `remaining > .zero`, sleep for `min(interval, remaining)` — clamping the sleep to the remaining budget prevents overshooting the deadline by a full interval.
6. Loop back to step 1.
7. After the loop exits (deadline exceeded), throw `GeminiInteractionsError.pollTimeout(id: id)`.

## Terminal statuses / isComplete
`Interaction.isComplete` is a computed property that returns `true` when `status` is `.completed`, `.failed`, `.cancelled`, `.incomplete`, or `.budgetExceeded`. It returns `false` for `.inProgress` and `.requiresAction`. When `isComplete` is true, `poll` returns; the caller must inspect `interaction.status` to distinguish success from failure.

## Sleep clamping
`Task.sleep(for: min(interval, remaining))` ensures the final sleep before timeout does not extend beyond the deadline. For example, with a 5-second interval and 2 seconds remaining, the sleep is 2 seconds rather than 5. This bounds how long poll can overshoot the requested timeout.

## Throws on timeout
`GeminiInteractionsError.pollTimeout(id: id)` carries the interaction ID. This is the only error thrown by `poll` itself — errors from `get(id:)` propagate directly without wrapping (they are already `GeminiInteractionsError` values).
