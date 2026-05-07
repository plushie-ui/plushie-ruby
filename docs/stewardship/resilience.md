# Resilience

plushie-ruby is meant to behave predictably when things go wrong:
an exception in the user's `update`, a malformed wire message
from the renderer, the renderer process crashing, a broken pipe,
a `view` that raises, a subscription source that explodes.
Resilience here is graceful behavior under those conditions, not
hardening against an attacker; that distinction lives in
`trust-model.md`.

The user-facing promise is the host SDK's half of the broader
Plushie promise: a renderer crash auto-recovers with state
re-sync, an app exception reverts to the last good state, neither
side takes the other down. This doc describes how plushie-ruby
holds up that half.

## What resilience means here

- **App exception revert.** Exceptions in `init`, `update`, and
  `view` are caught by the runtime (`rescue StandardError`),
  logged, and the model reverts to its pre-call state. The user
  does not need to wrap callbacks in `begin/rescue`. After a
  flood threshold the runtime suppresses further log output and
  emits one log per sample interval; the next clean call clears
  the suppression. `NoMatchingPatternError` gets a special hint
  suggesting an `else` clause in the user's `case/in` block.
- **Renderer crash auto-recovery.** The Bridge owns connection
  lifecycle. On unexpected exit it reconnects with bounded
  exponential backoff and pushes a `[:renderer_exited, reason]`
  then `[:renderer_restarted]` pair through the event queue. The
  Runtime owns the resync flow: re-send settings, render a fresh
  snapshot, re-sync subscriptions. The user's
  `handle_renderer_exit` callback can adjust the model before
  re-sync (e.g., reset transient UI state).
- **Bridge heartbeat.** A watchdog timer detects hung renderers.
  When no message arrives within the configured
  `heartbeat_interval`, a synthetic close is pushed through the
  queue to trigger
  the restart path. A renderer that wedges instead of crashing
  cannot leave the host running against a half-open transport.
- **StandardError, not Exception.** Rescues in the runtime catch
  `StandardError`, not `Exception`. Interrupts (`SystemExit`,
  `Interrupt`, `SignalException`) propagate through. A user's
  Ctrl-C is honored; runtime errors are isolated; deeper errors
  (memory, stack overflow) are not papered over.
- **Defensive parsing on the wire.** The codec assumes its input
  could be wrong: malformed MessagePack, unknown event variants,
  missing required fields, type-coercion mismatches. Rejection
  with a structured error is the right outcome; crashing the
  runtime is not.
- **Return-shape validation.** `update` must return a bare model
  or `[model, command]`. Anything else raises with a helpful
  message rather than silently corrupting state. See
  `elm-invariants.md`.
- **Bounded queues.** The runtime's event queue is a
  `BoundedQueue`. Coalescable events (move, scroll, resize)
  collapse to last-wins under load; the queue cannot grow
  unbounded under a flooding renderer.
- **Subscription failure isolation.** A subscription source that
  raises does not take the runtime down. The error surfaces as
  a structured event through the normal dispatch path; the
  runtime's update loop survives.
- **Thread isolation for async work.** `Command.task` and
  `Command.stream` spawn dedicated threads with cancellation
  handles. An exception in user-supplied callable code is
  caught, logged, and surfaced as an `Event::Async` with
  `:error` rather than killing the thread silently.

## What is appropriate to fail fast on

Some conditions are not recoverable at the framework level and
should fail fast rather than degrade:

- **Programming errors that violate runtime invariants.** Wrong
  return shape from `init`/`update`, an app class that does not
  include `Plushie::App`, a value that the encoder cannot
  serialize. The right behavior is a clear error (e.g.,
  `Plushie::Encode.encode_value` raising `ArgumentError`), not
  silent fallback.
- **Unrecoverable bridge startup.** If the renderer binary
  cannot be located or fails to spawn, the bridge raises with a
  clear message. Attempting to operate without a renderer is
  not a degraded mode worth supporting.
- **Wire framing corruption.** A truncated or unparseable frame
  on the bridge's input is not a recoverable condition; the
  bridge surfaces it and tears down the connection so the
  restart path can fire.

The line: degrade gracefully on user-facing conditions (app code
errors, parse errors, transport hiccups, renderer crashes). Fail
fast on framework-level invariant violations.

## Patterns in the codebase

Worth maintaining as the project evolves:

- `rescue StandardError` (or bare `rescue =>`) around `init`,
  `update`, `view`, and widget event handlers in the runtime;
  revert-and-log on exception.
- Wire-edge validation in `Plushie::Protocol::Decode` and
  `Plushie::Protocol::Parsers`; structured errors, never silent
  passthrough of malformed input.
- Effect request tracking with timeout; stale responses dropped,
  in-flight responses correlated by wire ID.
- Bridge restart with fresh snapshot re-sync rather than
  attempting to replay buffered events.
- Coalescable event handling for high-frequency sources (move,
  scroll, resize) so a flooding renderer cannot overwhelm the
  runtime's queue.
- Suppression of repeated error logs after a flood threshold,
  with auto-clear on the next clean call.
- Mutex-protected writes on the connection so concurrent senders
  do not interleave wire frames.

## What resilience is not

- **Not adversarial-input hardening.** The threat model is
  "things go wrong," not "attacker is trying to crash."
  Findings framed as the latter are usually misframed; see
  `trust-model.md`.
- **Not perfectionism.** The runtime does not try to fix the
  user's logic for them; it reverts and logs. The DSL does not
  invent placeholder widgets for missing types; it raises.
- **Not retry-at-any-cost.** A failed command surfaces a
  structured `Event::CommandError` (or analogous) so the user's
  `update` decides whether to retry. The runtime does not retry
  on its own (other than the bridge restart loop, which has a
  bounded retry count).
- **Not rescuing `Exception`.** `Exception` is too wide. A
  rescue clause that catches `Interrupt`, `SystemExit`, or
  `SignalException` papers over the user's Ctrl-C and the OS's
  shutdown signals. Bare `rescue` (which catches `StandardError`)
  is the right shape; explicit `rescue Exception` is a
  resilience bug unless the surrounding code re-raises after
  cleanup.
- **Not defense against impossible states.** Adding a defensive
  branch for a condition that cannot occur given the surrounding
  invariants is accidental complexity, not resilience. The bar
  for "cannot occur" is reading the surrounding code and being
  confident in the invariant.

## Implications

- A real things-go-wrong path producing an ungraceful failure
  (an unhandled exception in the runtime loop, a missed revert
  on view error, a stale effect tag delivering to the wrong
  handler, a bridge that hangs instead of triggering restart on
  broken pipe) is in scope today and earns priority.
- Inconsistency between resilience patterns (one site reverts on
  error, another swallows; one source logs and retries, another
  logs and gives up) is itself a resilience bug because future
  maintainers cannot predict behavior.
- Defensive layers for conditions that cannot occur given the
  surrounding invariants are out of scope; they add accidental
  complexity without reducing real failure modes.
- Aborting on conditions where graceful degradation is the right
  answer ("this should crash the process on bad event content")
  is the wrong direction; the established pattern is
  reject-and-report.
