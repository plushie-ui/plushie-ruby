# Concurrency shape

How plushie-ruby's runtime is structured under Ruby's
concurrency model, why the parts split the way they do, and the
threading discipline that holds them together. Other host SDKs
have their own concurrency shape; this is plushie-ruby's, and
it is downstream of Ruby and CRuby idioms rather than cross-
SDK convergence.

## The Connection / Bridge / Runtime split

Three layers, each with a single concern:

- **Connection** (`Plushie::Connection`). Owns the pipe to the
  renderer binary. Spawns the process, handles wire framing,
  manages a writer mutex for thread-safe sends, and runs a
  reader thread that pushes decoded messages onto a queue
  (or invokes a callback proc). Knows nothing about restarts,
  apps, or events at the semantic level. Usable standalone for
  scripting.
- **Bridge** (`Plushie::Bridge`). Wraps a Connection with
  restart logic. On unexpected exit, reconnects with bounded
  exponential backoff (100ms doubling to 5000ms, max 5
  retries) and pushes
  `[:renderer_event | :renderer_exited | :renderer_restarted]`
  pairs through the event queue. Owns the heartbeat watchdog.
  Knows nothing about app state.
- **Runtime** (`Plushie::Runtime`). Owns the app's
  `init`/`update`/`view` loop, the current model and tree, the
  subscription set, the widget handler registry, command
  execution, and the resync flow on bridge restart. Knows
  nothing about the wire format or the renderer process.

The split exists because the three responsibilities have
different lifetimes and different failure modes. Connection
crashes are pipe failures; the recovery is reconnect. Bridge
crashes are renderer crashes; the recovery is restart the
binary and replay state. Runtime crashes are app code crashes;
the recovery is revert to the last good model. Mixing the
three would couple recovery paths that should be independent.

## Threading model

All app state lives in the runtime thread. Events are
processed sequentially from a `BoundedQueue`. No shared mutable
state between threads; the queue is the sole synchronization
point.

- **Runtime thread**: sequential event processing. The Elm
  loop runs here. `update`, `view`, tree diff, command
  execution all happen on this thread, one event at a time.
- **Bridge thread / Connection reader thread**: read renderer
  stdout, decode wire frames, push decoded messages to the
  runtime's event queue. Never touch app state.
- **Thread pool** (`Plushie::ThreadPool`): bounded (CPU count
  by default) for non-cancellable background work. Used by
  the test framework and other infrastructure code. Not used
  for `Command.task` or `Command.stream`, which need
  individual cancel handles.
- **Async command threads**: `Command.task` and
  `Command.stream` spawn dedicated threads. The runtime
  tracks them by tag with a nonce; cancellation marks the
  nonce stale and the thread's result is discarded on
  arrival.
- **Timer scheduler thread** (`Plushie::TimerScheduler`): one
  thread, deadline-based `IO.select`, manages every active
  timer subscription. One thread per timer was the older
  pattern; the scheduler replaces it.
- **Connection writer mutex**: `Connection#send_message` is
  thread-safe. Writes from the runtime thread, async command
  threads, and effect callbacks serialize through the mutex.

The queue-as-sync-point rule: anything that wants to influence
app state pushes a tagged tuple onto the runtime's event
queue. The runtime pops, dispatches, and acts. Direct method
calls into the runtime from other threads are not a pattern
(test helpers excepted, where they are queue-pushes under the
hood).

## GVL awareness

CRuby's Global VM Lock means CPU-bound Ruby work in any thread
blocks every other Ruby thread. The runtime thread is the hot
path; CPU-bound Ruby in it is felt by every event. The
implications:

- **CPU-bound user work belongs in `Command.task`.** A worker
  thread spawned for the task lets the runtime continue
  processing other events. The GVL still serializes Ruby
  execution across threads, but I/O (file, socket, blocking C
  extensions) releases the GVL, so I/O-bound user work makes
  real progress in parallel with the runtime. CPU-bound user
  work in a task thread does not run in parallel with the
  runtime, but it does not block event delivery either; the
  runtime can interleave.
- **Framework CPU work avoids the per-event path.** Tree
  normalization is incremental (memo cache, widget view
  cache); diff is single-pass with LIS. Per-frame walks that
  do not depend on per-frame inputs are moved to startup, to
  subscription diff, or to the edge where the input changes.
  See `performance-bar.md`.
- **Blocking I/O on the runtime thread is wrong.** A
  synchronous file read in `update` blocks the runtime until
  it returns. Push it into `Command.task`.

JRuby and TruffleRuby do not have a GVL; the threading shape
still works there, with more real parallelism for CPU-bound
async work. The codebase is GVL-aware as a default but does
not depend on the GVL for correctness; the queue-as-sync-point
rule is what holds.

## Why threads, not fibers, not ractors

- **Fibers** are cooperative; they do not preempt. A fiber-
  based runtime would need explicit yield points and an event
  loop scheduler, recreating what `Thread` + `Queue` already
  gives us. The win is unclear, the cost is a new concurrency
  primitive everyone has to understand.
- **Ractors** are share-nothing actors with real parallelism
  on CRuby, but require data crossing ractor boundaries to
  be shareable. The widget tree, model, event payloads, and
  commands all involve user-supplied objects that may not
  satisfy the sharing rules. Until a workload appears that
  the threaded model cannot handle, ractors are a non-pattern.

Switching to fibers or ractors is a stewardship-level question,
not a routine refactor.

## Transport adapters

The Connection accepts three transport modes:

- `:spawn`: fork the renderer binary as a child process. The
  standard production transport.
- `:stdio`: use the current process's stdin/stdout. Used when
  this Ruby process was itself spawned by another process
  (e.g., `plushie --listen --exec ruby app.rb`).
- `[:iostream, adapter]`: a Ruby object that mediates between
  the Connection and an external I/O source (TCP socket, SSH
  channel, WebSocket). The adapter responds to `on_bridge`,
  `send_data`, and pushes received bytes via a method call.

Transport adapters are the right abstraction: every concrete
transport (stdio, spawn, TCP socket via the `tcp_adapter`
library, future SSH channel, future named pipe) implements the
same shape, the Connection code reads against the abstraction,
and adding a new transport does not require Connection
changes. This is the kind of small abstraction that earns its
place: multiple real implementations, the shared shape is
genuinely the same concept, and the call site reads cleanly.

## SessionPool architecture

The test framework runs sessions through a pool:

- **Multiplexed pool** for `mock` and `headless` backends.
  One renderer process started with `--max-sessions N`; each
  test gets a session ID. Wire messages are tagged with the
  session ID; the renderer routes to per-session state
  internally. Session startup is microseconds; renderer
  startup is amortized across the suite.
- **Per-session pool** for the `windowed` backend. One
  renderer process per session because real iced windows do
  not multiplex cleanly. Slower; used when window lifecycle
  matters.

The pool wraps the production `Connection`/`Bridge`/`Runtime`
pieces; it is not a separate runtime. Both `Plushie::Test::Case`
(Minitest) and `Plushie::Test::RSpec` set up a session and give
the test a `Session` object that drives the same wire path
production code uses.

## What's not used

- **`Mutex` for app state.** The runtime thread is the only
  thread that touches app state; no lock is needed. A mutex
  around model or tree access means some other thread is
  reaching into app state directly, which is a layering
  violation.
- **`Concurrent::*` primitives from concurrent-ruby.** The
  standard library plus the bespoke `BoundedQueue` and
  `TimerScheduler` cover the current needs. Pulling
  concurrent-ruby in for a single class is overhead that has
  not earned its place.
- **`Async` reactor as the runtime.** Same reasoning as
  fibers: explicit yield points everywhere, a new concurrency
  primitive everyone has to understand, no visible win.
- **Auto-bootstrap on require.** The user calls
  `Plushie.run(MyApp)` (blocking) or `Plushie.start(MyApp)`
  (background, returns a runtime handle). plushie-ruby is a
  library, not a framework that auto-starts.

## Implications

- A change that introduces a new long-lived thread gets a
  threading-level question first: where does it fit in the
  layering, what queue does it push to, how does it shut
  down, what does its crash mean for the rest of the runtime.
- A change that makes Connection or Bridge or Runtime do
  something one of the others already does is suspect. Wire
  framing in Runtime is wrong; app state in Connection is
  wrong; restart logic in Connection is wrong.
- A change that reaches into runtime state from another
  thread (other than via the event queue) is a layering
  violation and gets rewritten to push a tagged event.
- Tests that rely on internal threading structure (sleeping
  for a fixed time, checking thread counts, peeking at queue
  internals) are brittle and get rewritten to use the public
  Session API's synchronization barriers.
