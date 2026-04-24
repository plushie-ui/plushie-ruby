# Wire Protocol

The wire protocol defines the message format between the Ruby SDK
and the Rust renderer binary. The protocol itself is
language-agnostic and shared across every Plushie SDK. This page
covers the Ruby perspective: how `Plushie::Protocol` encodes and
decodes messages, how `Plushie::Connection` manages the pipe, and
how `Plushie::Bridge` keeps the renderer alive across restarts.

For the complete message format specification (every field, every
patch operation, every event family), see the
[Renderer Protocol Spec](https://github.com/plushie-ui/plushie-rust/blob/main/docs/protocol.md).

## Wire formats

Two formats carry the same message structures. The format is set
per connection via the `format:` keyword on `Plushie.run`,
`Plushie.start`, or `Plushie::Connection.spawn`.

### MessagePack (default)

Each message is prefixed with a 4-byte big-endian unsigned integer
giving the payload size:

```
<size:uint32_be><payload:bytes>
```

MessagePack encoding is handled by the `msgpack` gem. Encoding
pass-through for binary payloads (font bytes, raw RGBA pixels,
encoded PNG/JPEG data) is native to the format, so image uploads
don't pay a base64 tax.

### JSON (JSONL)

Each message is a single JSON object terminated by `\n`. Messages
must not contain embedded newlines. Use JSONL when you want to
tail `plushie.log` by eye or pipe frames through `jq`:

```bash
RUST_LOG=plushie=debug bundle exec ruby app.rb --json 2>protocol.log
```

Binary payloads are base64-encoded in JSONL mode. The
`Plushie::Protocol::Encode.encode_binary` helper applies the right
transform automatically for `data` and `pixels` fields.

### Format auto-detection

The renderer auto-detects the format from the first byte of
stdin: `0x7B` (`{`) means JSON, anything else means MessagePack.
The `--json` and `--msgpack` CLI flags override auto-detection;
the Ruby SDK passes the matching flag to the spawned process.

### Maximum frame size

`Plushie::Transport::Framing::MAX_MESSAGE_SIZE` is 64 MiB. The
framing helpers raise `Plushie::Transport::BufferOverflowError`
when a frame exceeds the cap, matching the renderer's own limit
so both ends reject at the same threshold.

## Protocol version

The current protocol version is `Plushie::Protocol::PROTOCOL_VERSION`
(`1`). The SDK sends it inside the Settings message and verifies
the version the renderer echoes back in the Hello response. A
mismatch raises `Plushie::ProtocolVersionMismatchError` during
handshake.

## Startup handshake

The Connection drives a fixed startup sequence:

1. **SDK spawns the renderer** via `Open3.popen2` with a filtered
   environment built by `Plushie::RendererEnv.build`. Credentials
   from the parent process are stripped so they don't leak into
   the child.
2. **SDK sends Settings** as the first message.
   `Plushie::Protocol::Encode.encode_settings` merges the app's
   settings hash with `protocol_version` and emits a wire frame.
3. **Renderer auto-detects format** from the first byte and reads
   the Settings.
4. **Renderer sends Hello** with `version`, `protocol`, mode
   (`mock`, `headless`, `windowed`), and the set of registered
   `native_widgets` and `widgets`.
5. **SDK validates required widgets.** Each configured native
   widget must appear in the Hello's widget list, otherwise
   `Plushie::Error` is raised with the missing names.
6. **SDK sends Snapshot.** The runtime calls `view`, normalises
   the tree, and emits a full tree via `encode_snapshot`.
7. **Normal message exchange begins.**

After the handshake, `Plushie::Connection#hello` exposes the
stored Hello hash for inspection.

## Encoding (SDK to renderer)

Every outbound message goes through `Plushie::Protocol::Encode`.
The methods return wire-ready bytes; the Connection or the
SessionPool injects the `session:` field before handing them to
the transport.

| Method | Message type | When sent |
|---|---|---|
| `encode_settings(settings, format)` | `settings` | Startup, renderer restart |
| `encode_snapshot(tree, format)` | `snapshot` | First render, renderer restart, interact fallback |
| `encode_patch(ops, format)` | `patch` | Incremental tree updates |
| `encode_subscribe(kind, tag, format, max_rate:, window_id:)` | `subscribe` | Subscription activation |
| `encode_unsubscribe(kind, tag:, format:)` | `unsubscribe` | Subscription removal |
| `encode_effect(id, kind, payload, format)` | `effect` | Platform effect requests |
| `encode_command(id, family, value, format)` | `command` | Widget-targeted commands |
| `encode_commands(commands, format)` | `commands` | Batch of widget-targeted commands |
| `encode_widget_op(op, payload, format)` | `widget_op` | Non-targeted operations (focus cycling, announce, load_font) |
| `encode_window_op(op, window_id, payload, format)` | `window_op` | Window open, close, update |
| `encode_system_op(op, payload, format)` | `system_op` | System-level operations |
| `encode_system_query(op, payload, format)` | `system_query` | System-level queries |
| `encode_image_op(op, payload, format)` | `image_op` | In-memory image lifecycle |
| `encode_query(id, target, selector, format)` | `query` | Find widget, read tree |
| `encode_interact(id, action, selector, payload, format)` | `interact` | Test interactions |
| `encode_advance_frame(timestamp, format)` | `advance_frame` | Manual frame step |
| `encode_tree_hash(id, name, format)` | `tree_hash` | Structural hash query |
| `encode_screenshot(id, name, width, height, format)` | `screenshot` | Pixel capture |
| `encode_reset(id, format)` | `reset` | Tear down a session |
| `encode_register_effect_stub(kind, response, format)` | `register_effect_stub` | Register a canned effect response |
| `encode_unregister_effect_stub(kind, format)` | `unregister_effect_stub` | Remove a stub |

### Key stringification

The SDK works with symbol keys in view code (`{type: :click, id:
"save"}`). At encode time,
`Plushie::Protocol::Encode.stringify_keys` walks the message
recursively and converts every symbol key to a string. View code
never has to think about the atom-vs-string boundary.

### Binary fields

`encode_binary` picks the right transform per format: base64 for
JSON, raw bytes for MessagePack. The image and font helpers call
it automatically for `data` and `pixels`; direct callers to
`encode_widget_op` with a binary `data` field get the same
treatment via `encode_binary_field`.

## Decoding (renderer to SDK)

`Plushie::Protocol::Decode.decode_message` deserialises the
inbound frame and dispatches on the `type` field to the matching
typed `Plushie::Event::*` struct.

| Wire type | Decoded to | Delivered via |
|---|---|---|
| `hello` | `Hash` | `Connection#hello`, runtime handshake |
| `event` | `Event::Widget`, `Event::Key`, `Event::Window`, etc. | `update` |
| `diagnostic` | `Event::DiagnosticMessage` | `update` (or logged) |
| `effect_response` | mapped to `Event::Effect[tag:, result:]` | `update` |
| `query_response` | Hash | Runtime query resolver |
| `op_query_response` | Hash | Runtime query resolver |
| `interact_step` | Hash | Test backend |
| `interact_response` | Hash | Test backend |
| `tree_hash_response` | Hash | Test backend |
| `screenshot_response` | Hash | `update` |
| `reset_response` | Hash | Session pool |
| `effect_stub_register_ack` / `effect_stub_unregister_ack` | `{type: :effect_stub_ack, kind: ...}` | Runtime resolves pending stub call |

### Safe decoding

Malformed frames (bad JSON, truncated MessagePack) return a hash
with an `"error"` key rather than raising, so the reader thread
stays alive. `decode_message` returns `nil` for errored frames,
and the Connection silently drops them.

### Named keys and parsers

Renderer strings are translated to idiomatic Ruby values before
they reach `update`:

- `Plushie::Protocol::Keys::NAMED_KEYS` maps PascalCase variant
  names from the Rust keyboard enum (`"ArrowUp"`, `"Escape"`,
  `"F1"`) to snake_case Ruby symbols (`:arrow_up`, `:escape`,
  `:f1`). Single-character keys (`"a"`, `"1"`, `"/"`) pass through
  as strings.
- `Plushie::Protocol::Parsers` converts mouse buttons
  (`"left"` to `:left`), scroll units, and pane drag strings
  (`"picked"`, `"dropped"`, `"canceled"`) to symbols.

## Snapshots and patches

The runtime decides whether to send a snapshot or a patch after
every update cycle:

- **Snapshot** is sent on the first render, after a renderer
  restart, and as a fallback when `view` raises during an
  `interact_step`. It resets all renderer-side caches.
- **Patch** is sent when the tree changes incrementally.
  `Plushie::Tree.diff` compares the previous and new normalised
  trees and produces an array of ops (`replace_node`,
  `update_props`, `insert_child`, `remove_child`). If the diff is
  empty, no message is sent.

The renderer preserves widget caches (layer tessellation, text
layout, scroll position) for unchanged subtrees across patches.

## Connection and Bridge

`Plushie::Connection` owns the bidirectional pipe. It supports
three construction paths:

- `Connection.spawn(format:, binary:, mode:, max_sessions:, log_level:, settings:)` starts a renderer
  subprocess via `Open3.popen2`, performs the handshake, and
  starts a reader thread.
- `Connection.attach(stdin:, stdout:, format:, settings:)` wraps
  existing IO streams. Used by the `:stdio` transport when the
  Ruby process is the renderer's child (exec-style deployments).
- `Connection.iostream(adapter:, format:, settings:)` talks to a
  user-supplied adapter that mediates framing for SSH channels,
  TCP sockets, or WebSockets. The adapter implements `on_bridge`
  and `send_data`; the connection calls `receive_data` and
  `transport_closed` back.

`send_encoded` serialises writes through a mutex so encoder
threads and the main runtime can both emit messages safely. The
reader thread loops on `read_msgpack_loop` or `read_json_loop`
depending on the configured format.

`Plushie::Bridge` wraps a Connection with restart and heartbeat
logic. It pushes decoded events onto the runtime's event queue
tagged with one of three markers:

- `[:renderer_event, msg]` for normal protocol messages
- `[:renderer_exited, reason]` when the connection drops
- `[:renderer_restarted]` after a successful reconnect

### Restart behavior

When the renderer exits unexpectedly, the Bridge reconnects with
exponential backoff: `BACKOFF_BASE_MS` of 100ms, capped at
`BACKOFF_MAX_MS` of 5s, giving up after `MAX_RETRIES` (5) failed
attempts. These constants match the other host SDKs so restart
behavior is consistent across implementations.

On a successful restart, the runtime runs a fresh resync:
pending effects fail with `"renderer_restarted"`, the in-flight
interact (if any) is cancelled, Settings are re-sent, the view
is re-rendered as a Snapshot, tracked windows are re-opened, and
subscriptions are re-subscribed. App state (the model, in-flight
async tasks, streams) is preserved throughout.

### Heartbeat watchdog

The Bridge runs a watchdog timer (`DEFAULT_HEARTBEAT_INTERVAL`,
30s) that triggers a restart if no message arrives from the
renderer in that window. Set `heartbeat_interval: nil` when
constructing the Bridge to disable it.

## The interact protocol

Test interactions (`click`, `type_text`, `toggle`, etc.) use a
synchronous request-response cycle:

1. The test calls `runtime.interact(action, selector, payload)`,
   which pushes the request onto the event queue.
2. The runtime sends an `interact` message and remembers the
   pending ID.
3. The renderer resolves the selector, simulates the interaction,
   and sends one or more `interact_step` messages with events
   produced along the way.
4. A final `interact_response` carries the last batch of events.
5. The runtime filters out responses with stale IDs (timed-out
   interactions), runs the events through `update`, and returns
   the final event list to the test.

The runtime caps interact execution so a single failure can't
block the queue forever; `handle_interact_timeout` surfaces a
`Plushie::Error`.

## Session multiplexing

Every wire message carries a `session` field (string). In
single-session mode (the default), this is `""`. In multiplexed
mode, each test session gets an isolated session ID and the
renderer maintains per-session state (tree, subscriptions,
effects, caches) keyed by the field.

`Plushie::Test::SessionPool` owns a single
`plushie-renderer --mock --max-sessions N` process and assigns
session IDs (`"test_1"`, `"test_2"`, ...) as tests register. Per
session:

- Sessions are created implicitly on the first message that
  carries a new session ID.
- `Reset` tears a session down. The pool waits for
  `reset_response` and `session_closed` before recycling.
- The session ID can be reused once `session_closed` lands.
- `--max-sessions` limits concurrent sessions; exceeding the
  limit raises at registration.

Session-scoped errors arrive as `Event::SessionError` (code,
message) and `Event::SessionClosed` events. See the
[Events reference](events.md) for the field lists.

## Custom transports

For deployments that don't use a spawned subprocess (e.g. remote
rendering over SSH, multi-process supervision), pass
`transport: :stdio` to write directly to the parent process's
stdio pipes, or `transport: [:iostream, adapter]` to use a
user-supplied adapter.

Adapters implement framing themselves, but the
`Plushie::Transport::Framing` module provides the building blocks:

- `encode_packet(data)` / `decode_packets(buffer)` for
  length-prefixed MessagePack frames.
- `encode_line(data)` / `decode_lines(buffer)` for
  newline-delimited JSONL.

Both paths raise `BufferOverflowError` for frames over 64 MiB.

## See also

- [Testing reference](testing.md) - the test harness, effect
  stubs, session pool, and `interact` helpers
- [Configuration reference](configuration.md) - transport modes,
  iostream adapter contract, renderer binary resolution
- [Events reference](events.md) - the typed event classes the
  decode layer produces
- [Renderer Protocol Spec](https://github.com/plushie-ui/plushie-rust/blob/main/docs/protocol.md)
  - authoritative message format reference
