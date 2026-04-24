# Shared State

The pad has a file manager, styling, animation, async effects, custom
canvas widgets, and a test suite. This final chapter takes it in a
different direction: more than one person at a time. Multiple
connections to the same app, one authoritative model, changes from
any client visible in every attached window.

Ruby does not ship a turn-key SSH server or a "collaboration" module.
What it ships is the transport pieces: a local renderer subprocess, a
stdio mode, and an iostream adapter hook for custom byte streams. The
rest (who listens on what port, how clients authenticate, how state
broadcasts between runtimes) is regular Ruby on top of those pieces.
This chapter walks through what is possible and where the seams are.

## Two multiplexing models

Plushie has two different "multiple things sharing one thing" stories
and they are easy to confuse. Keep them separate:

**Renderer multiplexing.** One `plushie` binary, many logical
sessions. The renderer accepts `--max-sessions N` and demultiplexes
messages by a `session` field. The SDK uses this for the test session
pool so hundreds of tests can share one GPU process. Each session has
its own widget tree, event queue, and window set inside the renderer.

**Runtime multiplexing.** One Ruby app process, many connected
`Plushie::Runtime` instances. Each runtime owns its own Elm loop:
model, subscriptions, command execution. They talk to separate
transports and know nothing about each other unless the app wires
them together.

Shared state is a runtime-multiplexing problem. The session pool is a
testing-infrastructure detail, covered briefly below to clear it out
of the way, then set aside.

### The session pool (for tests)

`Plushie::Test::SessionPool` spawns one `plushie --mock --max-sessions 8`
subprocess and multiplexes test sessions over it:

```ruby
pool = Plushie::Test::SessionPool.new(
  mode: :mock,
  format: :msgpack,
  max_sessions: 8
)
pool.start
session_id = pool.register
# ... run a test against session_id ...
pool.unregister(session_id)
```

Each registered session gets a unique ID (`"test_1"`, `"test_2"`, ...)
injected into outbound messages; inbound messages are demuxed by
`session:` field and forwarded to a per-session `Thread::Queue`. The
renderer side runs each session in its own thread. `Event::SessionError`
and `Event::SessionClosed` surface session-level failures through the
inbound stream without taking the whole pool down. The testing guide
covers the rest of the pool API; here it is enough to note that this
is scoped to testing. Production apps run one runtime per app instance
and talk to a dedicated renderer.

## Transports for remote rendering

The runtime's `transport:` option decides where the wire protocol
goes. Three modes:

```ruby
Plushie.run(Pad)                                  # :spawn  (default)
Plushie.run(Pad, transport: :stdio)               # :stdio
Plushie.run(Pad, transport: [:iostream, adapter]) # custom adapter
```

`:spawn` is the local-desktop default. The SDK launches the renderer
as a child process via `Open3.popen2`, with a filtered environment
built by `Plushie::RendererEnv.build` (display, GPU, fonts, locale,
accessibility, and anything prefixed with `PLUSHIE_`; everything else
is stripped).

`:stdio` attaches the runtime to the parent process's own stdin and
stdout. The renderer is now the parent: it spawns the Ruby app and
speaks wire protocol directly over those pipes. Use this for the
"renderer runs locally, app runs on a server" pattern:

```bash
plushie --exec "ssh pad-server bundle exec rake plushie:connect[Pad]"
```

The `plushie:connect` Rake task in `plushie/rake.rb` is a one-liner
for this: it calls `Plushie.run(app_class, transport: :stdio)`.

`[:iostream, adapter]` accepts an arbitrary object that mediates
between the runtime and some other byte stream: a TCP socket, a
WebSocket, an SSH channel, an in-memory pair, anything that can
shuttle framed bytes. The adapter contract is small, documented in
`Plushie::Connection.iostream`, and shown in the next section.

## The iostream adapter contract

Two methods, two callbacks:

| Method on adapter | When | Purpose |
|---|---|---|
| `on_bridge(connection)` | Connection setup | Adapter stores the `Connection` and starts its reader |
| `send_data(data)` | SDK outbound | Adapter writes framed bytes to the transport |

| Callback on connection | When | Purpose |
|---|---|---|
| `connection.receive_data(data)` | Inbound | One complete protocol message, framing already stripped |
| `connection.transport_closed(reason)` | Transport died | Triggers the runtime's renderer-exit path |

The shipped example adapter is `Plushie::Transport::TCPAdapter`:

```ruby
require "socket"
require "plushie/transport/tcp_adapter"

socket = TCPSocket.new("localhost", 4000)
adapter = Plushie::Transport::TCPAdapter.new(socket)
Plushie.run(Pad, transport: [:iostream, adapter], format: :msgpack)
```

Inside the adapter, a background reader thread reads from the socket
in 64 KiB chunks, decodes length-prefixed frames via
`Plushie::Transport::Framing.decode_packets`, and forwards each
complete message to `@connection.receive_data`. Outbound bytes are
framed with `Framing.encode_packet` and written back. Nagle's
algorithm is disabled on the socket so small protocol messages do
not sit in a send buffer waiting for more data.

The TCP adapter is deliberately unopinionated about who is the server
and who is the client: pass any connected `TCPSocket` and it works.
It also works for Unix domain sockets (`UNIXSocket`) and any IO that
quacks like one.

## Thread safety, once

Before building anything on top of the transports, pin down the
threading model, because that is what makes or breaks multi-runtime
code in Ruby:

- Each `Plushie::Runtime` owns a single event loop thread
  (`plushie-runtime`). All updates to `@model`, `@previous_tree`,
  subscriptions, and pending effects happen on that thread.
- The bridge runs its own forwarder thread (`plushie-bridge-forwarder`)
  that reads decoded messages off the connection queue and pushes them
  onto the runtime's `Thread::Queue`.
- The connection runs a reader thread (`plushie-connection-reader`)
  that parses wire frames off the transport.
- Async tasks (`Command.task`) run on worker threads from
  `Plushie::ThreadPool` and deliver results back through the event
  queue.
- An iostream adapter brings its own reader thread for the underlying
  transport.

The invariant that makes this tractable: user code only runs on the
runtime thread. `update` is serial. `view` is serial. The adapter,
the bridge, and async workers do not call into user code directly;
they push messages onto queues, and the event loop drains those
queues sequentially. This is the same shape as the Elixir runtime,
expressed in Ruby threads instead of processes.

When two runtimes share an app-level state holder, that holder must
be thread-safe. A `Mutex`-guarded struct or a worker thread backed by
a `Thread::Queue` both work. Plain instance variables do not.

## Shared state: one actor, many runtimes

The goal: one authoritative model in the process, each client a
`Plushie::Runtime` bound to its own transport, changes broadcast to
every client. A rough picture:

```
  client A socket <-> runtime A (view, diff, patch)
                         ^
                         | apply local events
                         v
                    SharedStore thread
                    (model, client list)
                         ^
                         | apply local events
                         v
  client B socket <-> runtime B (view, diff, patch)
```

Each runtime is a full Elm loop: its own subscriptions, event
coalescing, error isolation, renderer restart. The shared store holds
the model, runs one piece of update logic for state-changing events,
and pushes the new model back to every attached runtime.

### The blunt bit

The Elixir SDK exposes `Plushie.Runtime.dispatch/2` for injecting
arbitrary events into a running runtime from outside. Ruby does not.
`Plushie::Runtime#event_queue` is private; there is no supported
public call that injects an `Event` into another runtime's loop.

Two ways to route shared-state updates into a runtime without that
hook:

1. **Per-runtime polling subscription.** Each runtime subscribes to a
   timer, and on each tick pulls the current shared model from the
   store. Simple, but tick-bounded (25-50 ms latency is typical) and
   wakes up even when nothing changed.

2. **Long-poll via `Command.task`.** Each runtime runs an async task
   that blocks on a `Thread::Queue` handed out by the shared store.
   When the task returns, dispatch a fresh task to wait for the next
   change. No idle polling, event-loop latency is close to zero, but
   you are writing your own pub/sub plumbing.

The second pattern reads closer to what other SDKs do and is the one
used below. Neither is elegant; both are honest descriptions of what
the SDK supports today.

### The shared store

`SharedStore` holds the model and a list of subscriber queues. Updates
happen under a `Mutex` so the Ruby runtime's lack of an STM is not a
problem:

```ruby
class SharedStore
  def initialize(initial)
    @mutex = Mutex.new
    @model = initial
    @subscribers = []
  end

  def get = @mutex.synchronize { @model }

  def subscribe
    queue = Thread::Queue.new
    @mutex.synchronize { @subscribers << queue }
    queue.push(@model) # seed with the current value
    queue
  end

  def unsubscribe(queue)
    @mutex.synchronize { @subscribers.delete(queue) }
    queue.close
  end

  def apply(&block)
    new_model =
      @mutex.synchronize do
        @model = safe_apply(@model, block)
      end
    broadcast(new_model)
  end

  private

  def safe_apply(model, block)
    block.call(model)
  rescue => e
    warn("shared store apply failed: #{e.class}: #{e.message}")
    model
  end

  def broadcast(model)
    @mutex.synchronize do
      @subscribers.each { |q| q.push(model) }
    end
  end
end
```

`apply` runs the mutation under the mutex so two concurrent events
cannot produce a lost update. The `begin/rescue` inside `safe_apply`
is the equivalent of the Elixir demo's `try/rescue`: a buggy update
from one client does not poison the shared model.

### Wiring a runtime to the store

Each runtime has two jobs on attach: feed local state-changing events
to the store, and pull remote broadcasts in as local events. The
long-poll pattern handles the second half:

```ruby
class CollabPad
  include Plushie::App

  def initialize(store)
    @store = store
    @subscription_queue = nil
  end

  def init(_opts)
    @subscription_queue = @store.subscribe
    initial = @store.get
    [
      Model.new(shared: initial, local: LocalModel.default),
      Plushie::Command.task(-> { @subscription_queue.pop }, :broadcast)
    ]
  end

  def update(model, event)
    case event
    in Event::Async[tag: :broadcast, result: new_shared]
      # Replace the shared half of the model, keep the local half.
      # Re-arm the long-poll for the next broadcast.
      [
        model.with(shared: new_shared),
        Plushie::Command.task(-> { @subscription_queue.pop }, :broadcast)
      ]

    in Event::Widget[type: :click, id: "increment"]
      @store.apply { |m| m.with(count: m.count + 1) }
      model # local no-op, the broadcast will land shortly

    in Event::Widget[type: :toggle, id: "dark_mode"]
      # Local-only state: never touches the store.
      model.with(local: model.local.with(dark_mode: !model.local.dark_mode))
    end
  end

  def view(model)
    window("main", title: "Shared counter") do
      column(padding: 16, spacing: 12) do
        text("count", "Count: #{model.shared.count}", size: 24)
        button("increment", "+1")
        toggler("dark_mode", "Dark mode", value: model.local.dark_mode)
      end
    end
  end
end
```

The ceremony is unavoidable: `init` returns an initial
`Command.task`, every `:broadcast` match re-arms the next one, and
the store is an instance variable bound to this runtime. When the
runtime stops, `@store.unsubscribe(@subscription_queue)` should be
called from a teardown hook; the cleanest place is a custom
`handle_renderer_exit` that calls it when the exit type is
`:connection_lost` or `:crash`.

### Splitting shared from local

Note the split in `Model`: a `shared` struct (updated by broadcasts)
and a `local` struct (updated only by this client). The broadcast
replaces `shared` wholesale but never touches `local`. Without the
split, a dark-mode toggle in one window would snap back on the next
broadcast from another client.

Anything per-client goes in `LocalModel`: UI toggles, the currently
focused note, scroll position, temporary form input. Anything every
client should see goes in `SharedModel`: the document contents, the
cursor list, the persistent counter.

## Running over stdio and SSH

The first end-to-end topology is the simplest: the renderer runs on
the user's desktop, the Ruby app runs on a shared server, SSH carries
the wire protocol. No custom transport, no TCP adapter, just stdio.

On the server, write a tiny launcher:

```ruby
#!/usr/bin/env ruby
require "plushie"
require_relative "collab_pad"

Plushie.run(CollabPad.new(Shared.global_store), transport: :stdio)
```

Put it on the user's PATH as `collab-pad`. Then from a client:

```bash
plushie --exec "ssh pad-server collab-pad"
```

Two clients, two SSH sessions, two Ruby processes, two
`SharedStore` subscribers, one model in memory on the server.
Click `+1` on either client and both windows tick up.

The fine print:

- Each SSH login spawns a new Ruby process. `Shared.global_store`
  must live somewhere all processes can see it, which rules out a
  plain module constant. Either put the store in a long-running
  parent process that the SSH command talks to (via Unix socket,
  the next section), or use Redis / a database as the shared backend.
- `authorized_keys` decides who can log in. The SDK does no
  authentication of its own; do not expose stdio transport to an
  untrusted network.
- `PLUSHIE_*` environment variables inherit from the SSH session.
  `PLUSHIE_BINARY_PATH` is harmless; `RUST_LOG=plushie=debug` makes
  the renderer chatty; there are no credentials in the renderer
  environment because `RendererEnv.build` strips unknown vars.

## Running over TCP

For a single long-running process with multiple concurrent clients,
`TCPAdapter` is the right fit. The server process owns the store and
listens on a port; each accepted connection gets a fresh runtime
bound to that socket.

```ruby
require "socket"
require "plushie"
require "plushie/transport/tcp_adapter"

store = SharedStore.new(SharedModel.new(count: 0))
server = TCPServer.new("127.0.0.1", 4000)

loop do
  socket  = server.accept
  adapter = Plushie::Transport::TCPAdapter.new(socket)
  app     = CollabPad.new(store)

  Thread.new do
    begin
      Plushie.run(app, transport: [:iostream, adapter], format: :msgpack)
    rescue => e
      warn("client died: #{e.class}: #{e.message}")
    end
  end
end
```

One runtime per connection, one shared store in the parent thread.
`Plushie.run` blocks the client thread until the renderer exits;
when it returns, the socket is already closed by the adapter's
`stop` method.

Connect a renderer to it:

```bash
plushie --connect tcp://127.0.0.1:4000
```

The wire protocol does not change between transports. The same
`view`, the same events, the same patches. Only the bytes take a
different road.

### Security considerations

TCP exposes a wire-protocol endpoint on a network. Pre-flight notes:

- **Bind locally.** `"127.0.0.1"` means this process only. Do not bind
  `"0.0.0.0"` unless there is a firewall, a reverse proxy, or some
  other access control in front.
- **No built-in auth.** The SDK has an optional `token:` runtime
  option that is forwarded in the Settings handshake, but the
  renderer does not enforce it and no SDK-side check compares it
  against an allowed list. Treat the token as a marker, not a
  credential. Real authentication belongs in the accept loop (TLS
  client certs, a PAM check, whatever fits).
- **No arbitrary eval.** The wire protocol carries widget patches and
  events, not Ruby code. A malicious client cannot send a message
  that the SDK will `eval`. But events do reach `update`, and if
  `update` calls `Object.const_get(event.value)` or similar you have
  reinvented the hole. Treat inbound events as untrusted input.
- **No secret leakage across sessions.** Two runtimes sharing a
  process share the Ruby heap. If `update` reads `ENV["API_KEY"]`
  into the model, every connected client sees it. Keep secrets out
  of the model, or split the shared model so client-visible fields
  are explicit.
- **Framing overflow.** `Plushie::Transport::Framing::MAX_MESSAGE_SIZE`
  is 64 MiB; frames larger than that raise `BufferOverflowError` in
  the reader thread and close the connection. The adapter's
  `transport_closed` callback routes through the runtime's renderer-
  exit handling, so the affected client drops cleanly without
  taking the server down.

## Verify it

The shared store is a plain Ruby object that tests without any
rendering at all:

```ruby
class SharedStoreTest < Minitest::Test
  def test_broadcasts_to_every_subscriber
    store = SharedStore.new(SharedModel.new(count: 0))
    a = store.subscribe
    b = store.subscribe

    # Drain seeded initial value from each.
    a.pop
    b.pop

    store.apply { |m| m.with(count: m.count + 1) }

    assert_equal 1, a.pop.count
    assert_equal 1, b.pop.count
  end

  def test_rescues_update_errors
    store = SharedStore.new(SharedModel.new(count: 0))
    store.apply { |_| raise "boom" }
    assert_equal 0, store.get.count
  end
end
```

For integration coverage against the real renderer, reach for
`Plushie::Test::Case`. Run two sessions against the same store and
assert that an event on one shows up in the other's tree:

```ruby
class CollabIntegrationTest < Plushie::Test::Case
  def setup
    super
    @store = SharedStore.new(SharedModel.new(count: 0))
  end

  def test_increment_broadcasts_to_the_other_client
    with_runtime(CollabPad.new(@store)) do |a|
      with_runtime(CollabPad.new(@store)) do |b|
        a.click("#increment")
        b.await_model { |m| m.shared.count == 1 }

        assert_equal 1, b.model.shared.count
      end
    end
  end
end
```

`with_runtime` is a fixture helper you write on top of
`Plushie::Test::Case`; the testing reference documents the available
primitives if you prefer to wire it differently.

## Exercise: a user list

Add a connected-user list to the shared counter:

1. Extend `SharedModel` with a `users:` field, an array of
   `{id:, name:}` hashes.
2. On runtime attach, append a user to the store and broadcast.
   On detach (trigger from `handle_renderer_exit`), remove the user.
3. Render the list in `view` as a `column` of `text` nodes in a side
   pane. Count the entries in the header.
4. Bonus: give each user a color (hash their id to an HSL value),
   draw a small circle next to their name using the `canvas` widget.

Start with the detach step: Ruby's lack of `DOWN` monitors means the
store has to notice when a subscriber stops pulling. A `last_seen`
timestamp on each subscription and a janitor thread that evicts
stale subscribers after, say, 30 seconds is the honest way. The
alternative is an explicit `@store.unsubscribe` in
`handle_renderer_exit`, which works for clean disconnects but misses
the "ssh session torn down by the network" case.

Solutions drift toward application-level conventions fast. That is
fine. The SDK gives you transports and an Elm loop; how many people
collaborate on what model, and how that model heals after a dropped
session, belongs in the app.

## See also

- [Configuration reference](../reference/configuration.md),
  `transport:`, `token:`, and the `settings` handshake flow
- [Wire Protocol reference](../reference/wire-protocol.md), framing
  and the iostream adapter's message contract
- [Testing reference](../reference/testing.md), the session pool
  and `Plushie::Test::Case` helpers used in the verify section
- [Events reference](../reference/events.md), `Event::Async`,
  `Event::SessionError`, and the renderer-exit event taxonomy
- [Commands reference](../reference/commands.md), `Command.task`
  and the long-poll pattern

## Next chapter

[Native Extensions](17-native-extensions.md)
