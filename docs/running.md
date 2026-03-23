# Running plushie

Plushie's **renderer** draws windows and handles input. Your Ruby
code (the **host**) manages state and builds the UI tree. They talk
over a wire protocol -- locally through a pipe, remotely over SSH,
or through any transport you provide. This guide covers all the ways
to connect them.

## Local desktop

The simplest setup: the host spawns the renderer as a child process.

```sh
bundle exec ruby lib/my_app.rb
```

Or from code:

```ruby
Plushie.run(MyApp)
```

The renderer is resolved automatically. For most projects,
`bundle exec rake plushie:download` fetches a precompiled renderer and
you're done. If you have native Rust extensions,
`bundle exec rake plushie:build` compiles a custom renderer. You can
also set `PLUSHIE_BINARY_PATH` explicitly, or use `Plushie.configure`:

```ruby
Plushie.configure do |config|
  config.binary_path = "/opt/plushie/bin/plushie"
  config.source_path = "~/projects/plushie"   # used by rake plushie:build
end
```

### Dev mode

`Plushie::DevServer` watches your source files and reloads on change.
Edit code, save, see the result instantly. The model state is preserved
across reloads.

```sh
bundle exec ruby lib/my_app.rb              # live reload enabled
bundle exec ruby lib/my_app.rb --no-watch   # disable file watching
```

### Exec mode

The renderer can spawn the host instead of the other way around. This
is useful when plushie is the entry point (a release binary or launcher)
and it's the foundation for remote rendering over SSH.

```sh
plushie --exec "bundle exec ruby lib/my_app.rb --connect"
```

The renderer controls the lifecycle. When the user closes the window,
the renderer closes stdin, and the Ruby process exits cleanly.

## Remote rendering

Your host runs on a server. You want to see its UI on your laptop.
The renderer runs locally (where your display is), the host runs
remotely (where the data is), and SSH connects them:

```
[your laptop]                    [server]
renderer        <--- SSH --->    host
  draws windows                    init/update/view
  handles input                    business logic
```

Your `init`/`update`/`view` code doesn't change at all.

### Prerequisites

- **Your laptop**: the `plushie` renderer installed and on your PATH.
- **The server**: your Ruby project deployed with its dependencies.
  The server does NOT need the renderer or a display server.
- **SSH access**: you can `ssh user@server` from your laptop.

### Quick start

```sh
plushie --exec "ssh user@server 'cd /app && bundle exec ruby lib/my_app.rb --connect'"
```

The renderer on your laptop spawns an SSH session, which starts the
host on the server. The wire protocol flows through the SSH tunnel.

### In-process SSH

If your server already runs a Ruby process (a Rails service, a data
pipeline), you can connect directly to the running VM using a custom
transport adapter. See [custom transports](#the-protocol) below.

### Binary distribution

The renderer always runs on the **display machine** (your laptop,
not the server):

| Your project uses | Renderer needed | How to get it |
|---|---|---|
| Built-in widgets only | Precompiled | `rake plushie:download` or GitHub release |
| Pure Ruby extensions | Precompiled | Same -- composites don't need a custom build |
| Native Rust extensions | Custom build | `rake plushie:build` targeting your laptop's architecture |

## Resiliency

Things go wrong. Renderers crash, code has bugs, networks drop.
Plushie handles these without losing your model state.

### Renderer crashes

If the renderer crashes (segfault, GPU error, out of memory), the
host detects it and restarts automatically with exponential backoff.
Your model state is preserved -- the new renderer receives fresh
settings, a full snapshot of the current UI, and re-synced
subscriptions and windows.

The host retries up to 5 times (100ms, 200ms, 400ms, 800ms, 1.6s).
If all retries fail, it logs troubleshooting steps and the plushie
runtime stops. The rest of your application is unaffected. A
successful connection resets the retry counter, so intermittent
crashes get a fresh budget each time.

### Exceptions in your code

If `update` or `view` raises, the runtime catches it, logs the
error with a full backtrace, and keeps the previous model state.
The window stays open and continues responding to events. You don't
need begin/rescue in your callbacks.

After 100 consecutive errors, log output is suppressed to prevent
flooding, with periodic reminders every 1000 errors.

### Network drops

When an SSH connection drops, both sides detect the broken pipe:

- **The renderer** sees the host's stdout close.
- **The host** sees stdin close. Without daemon mode, the plushie
  runtime exits. With daemon mode, plushie keeps running with the
  model preserved.

When a new renderer connects, the host sends a snapshot of the
current state. No restart, no state loss.

```ruby
Plushie.run(MyApp, transport: :stdio, daemon: true)
```

### Window close

When the user closes the last window, your `update` receives the
event. You can save state, persist data, or show a confirmation
dialog. In non-daemon mode, the runtime exits. In daemon mode,
it keeps running and waits for a new renderer to connect.

## Event rate limiting

Over a network, continuous events like mouse moves, scroll, and
slider drags can overwhelm the connection. Rate limiting tells the
renderer to buffer these and deliver at a controlled frequency.
Discrete events like clicks and key presses are never rate-limited.

Rate limiting is useful locally too -- a dashboard doesn't need
1000 mouse move updates per second even on a fast machine.

### Global default

```ruby
def settings
  {default_event_rate: 60}   # 60 events/sec -- good for most cases
end
```

For a monitoring dashboard:

```ruby
def settings
  {default_event_rate: 15}
end
```

### Per-subscription

```ruby
def subscribe(model)
  [
    Subscription.on_mouse_move(:mouse, max_rate: 30),
    Subscription.on_animation_frame(:frame, max_rate: 60),
    Subscription.on_mouse_move(:capture, max_rate: 0)   # capture only
  ]
end
```

### Per-widget

```ruby
slider("volume", [0, 100], model.volume, event_rate: 15)
slider("seek", [0, model.duration], model.position, event_rate: 60)
```

### Latency and animations

| Transport | Localhost | LAN | WAN |
|---|---|---|---|
| Port (local) | < 1ms | -- | -- |
| SSH | -- | 1-5ms | 20-150ms |

On a LAN, animations are smooth and interactions feel instant. Over a
WAN (50ms+), user interactions have a visible round-trip delay. Design
for this by keeping UI responsive to local input (hover effects, focus
states) and accepting that model updates lag by the round-trip time.

## Token authentication

When using `--exec` or remote rendering, you can require the host to
authenticate with a token. The renderer generates a random token and
passes it to the host process. The host must include the token in its
Settings message. Connections with an invalid token are rejected.

Configure token auth via `Plushie.configure`:

```ruby
Plushie.configure do |config|
  # Token is read from PLUSHIE_TOKEN env var when using --exec
end
```

Or pass `token:` directly to `Plushie.run`:

```ruby
Plushie.run(MyApp, transport: :stdio, token: ENV["PLUSHIE_TOKEN"])
```

## IoStream transport

The iostream transport lets you connect the Plushie runtime to any
bidirectional message-passing channel. Instead of spawning a child
process, pass a process or object that speaks the iostream protocol:

```ruby
Plushie.run(MyApp, transport: [:iostream, adapter_pid])
```

This is useful for embedding a Plushie app inside an existing process
(e.g. connecting over a TCP socket, WebSocket, or custom IPC).

## Custom transports

For advanced use cases, the iostream transport lets you bridge any
I/O mechanism to plushie. Write an adapter that speaks a simple
four-message protocol, and plushie handles the rest.

### The protocol

| Direction | Message | Purpose |
|---|---|---|
| Bridge -> Adapter | `[:iostream_bridge, bridge]` | Init handshake |
| Adapter -> Bridge | `[:iostream_data, binary]` | One complete protocol message |
| Bridge -> Adapter | `[:iostream_send, iodata]` | Protocol message to send |
| Adapter -> Bridge | `[:iostream_closed, reason]` | Transport closed |

### Example: TCP adapter

```ruby
class TCPAdapter
  def initialize(socket)
    @socket = socket
    @bridge = nil
    @buffer = "".b
  end

  def handle_message(msg)
    case msg
    in [:iostream_bridge, bridge]
      @bridge = bridge

    in [:iostream_send, data]
      @socket.write(Plushie::Transport::Framing.encode_packet(data))

    in [:tcp_data, data]
      messages, @buffer = Plushie::Transport::Framing.decode_packets(@buffer + data)
      messages.each { |m| @bridge.push([:iostream_data, m]) }

    in [:tcp_closed]
      @bridge&.push([:iostream_closed, :tcp_closed])
    end
  end
end
```

### Framing

Raw byte streams (SSH channels, raw sockets) need message boundaries.
`Plushie::Transport::Framing` handles this:

```ruby
# MessagePack: 4-byte length prefix
encoded = Plushie::Transport::Framing.encode_packet(data)
messages, remaining = Plushie::Transport::Framing.decode_packets(buffer + chunk)

# JSON: newline-delimited
encoded = Plushie::Transport::Framing.encode_line(data)
lines, remaining = Plushie::Transport::Framing.decode_lines(buffer + chunk)
```

## How props reach the renderer

When you return a tree from `view`, it passes through stages before
reaching the wire:

1. **Widget builders** (DSL block methods, `Plushie::Widget::*` modules)
   return `Node` objects with raw Ruby values.

2. **Tree normalization** (`Plushie::Tree.normalize`) walks the tree
   and encodes each prop value via the `Plushie::Encode` module.
   Scoped IDs are resolved here.

3. **Protocol encoding** stringifies symbol keys to strings,
   then serializes to MessagePack or JSON.

## Next steps

- [Getting started](getting-started.md) -- setup, first app
- [Commands and subscriptions](commands.md) -- event rate limiting details
- [Testing](testing.md) -- three-backend test framework
- [Extensions](extensions.md) -- custom widgets
