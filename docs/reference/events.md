# Events

All user interactions, system responses, and asynchronous results
are delivered to your app's `update` method as immutable `Data`
classes under `Plushie::Event`. Pattern-match on them with Ruby's
`case/in` syntax.

This page is a comprehensive reference. For a gentler introduction,
see the [Events guide](../guides/05-events.md).

## Event taxonomy

| Category | Class | Source |
|---|---|---|
| Widget interaction | `Event::Widget` | Renderer (widget callbacks) |
| Keyboard | `Event::Key` | Subscription (key press/release) |
| Modifier state | `Event::Modifiers` | Subscription (modifier change) |
| Pointer (mouse) | `Event::Widget` | Subscription (global pointer) |
| Pointer (touch) | `Event::Widget` | Subscription (touchscreen) |
| IME | `Event::Ime` | Subscription (input method editor) |
| Window lifecycle | `Event::Window` | Renderer (open, close, resize, etc.) |
| System | `Event::System` | Renderer (theme change, animation frame) |
| Timer | `Event::Timer` | Subscription (`Subscription.every`) |
| Async result | `Event::Async` | Command (`Command.task`) |
| Stream value | `Event::Stream` | Command (`Command.stream`) |
| Effect response | `Event::Effect` | Renderer (file dialogs, clipboard, etc.) |
| Command error | `Event::CommandError` | Renderer (command failure) |
| Session error | `Event::SessionError` | Renderer (multiplexed session failure) |
| Session closed | `Event::SessionClosed` | Renderer (session exit) |

All Plushie events are Ruby `Data` classes with an `Event::` prefix.
Use Ruby pattern matching (`case/in`) to destructure them.

## Widget event types

Every built-in `type:` symbol, its payload carrier, and a short
description. Carrier indicates where data lands in the `value` field:
**none** (no payload), **value** (scalar), or **map** (symbol-keyed
hash inside `value`).

### Standard widget events

| Type | Carrier | Description |
|---|---|---|
| `:click` | none | Button pressed |
| `:input` | value (string) | Text input changed |
| `:submit` | value (string) | Text input submitted (Enter) |
| `:toggle` | value (boolean) | Toggler or checkbox toggled |
| `:select` | value (any) | Pick list / combo box selection |
| `:slide` | value (number) | Slider moved |
| `:slide_release` | value (number) | Slider released at final value |
| `:paste` | value (string) | Paste action on a text input |
| `:open` | none | Expandable opened |
| `:close` | none | Expandable closed |
| `:option_hovered` | value (any) | Pick list option hovered |
| `:key_binding` | value (map) | Key binding activated |
| `:link_click` | value (string) | Link span or markdown link activated |
| `:sort` | value (string) | Table column sort requested |
| `:scrolled` | value (map) | Scrollable viewport offset changed (`absolute_x`, `absolute_y`, `relative_x`, `relative_y`, `bounds_width`, `bounds_height`, `content_width`, `content_height`) |
| `:pane_focus_cycle` | value (map) | Pane focus cycle requested (`pane`) |
| `:transition_complete` | value (map) | Renderer-side transition completed (`tag`, `prop`) |
| `:status` | value (string) | Widget interaction status changed (see below) |

### Status events

Every built-in widget emits `:status` events when its interaction
status changes. The runtime tracks these internally for focus and
hover queries. Derived `:focused` and `:blurred` events are
dispatched to `update` on focus transitions.

Status names: `"active"`, `"hovered"`, `"focused"`, `"pressed"`,
`"dragged"`, `"disabled"`, `"opened"`. Not all widgets support all
statuses (e.g., only sliders emit `"dragged"`).

### Pointer events

Unified pointer events for canvas-level, pointer area, and sensor
interactions. The `pointer` field identifies the input device
(`:mouse`, `:touch`, `:pen`); `button` identifies the button
involved; `modifiers` carries the current modifier state.

| Type | Carrier | Fields |
|---|---|---|
| `:press` | value (map) | `x`, `y`, `button`, `pointer`, `finger`, `modifiers` |
| `:release` | value (map) | `x`, `y`, `button`, `pointer`, `finger`, `modifiers` |
| `:move` | value (map) | `x`, `y`, `pointer`, `finger`, `modifiers` |
| `:scroll` | value (map) | `x`, `y`, `delta_x`, `delta_y`, `pointer`, `modifiers` |
| `:enter` | value (map) | `x`, `y` |
| `:exit` | value (map) | `x`, `y` |
| `:double_click` | value (map) | `x`, `y`, `pointer`, `modifiers` |
| `:resize` | value (map) | `width`, `height` |

The `button` field is one of `:left`, `:right`, `:middle`, `:back`,
`:forward`. The `pointer` field is one of `:mouse`, `:touch`, `:pen`.
The `finger` field is a number for touch events and `nil` otherwise.

Note: `:scroll` is pointer input (wheel delta at coordinates).
`:scrolled` in the standard widget events table above is scrollable
container state reporting its viewport offset.

### Generic element events

Focus, blur, drag, and scoped keyboard events emitted by interactive
elements (canvas groups, widgets, and so on). Canvas element clicks
arrive as regular `:click` events with the canvas ID in scope. See
the [Canvas reference](canvas.md) for details.

| Type | Carrier | Fields |
|---|---|---|
| `:focused` | none | |
| `:blurred` | none | |
| `:drag` | value (map) | `x`, `y`, `delta_x`, `delta_y` |
| `:drag_end` | value (map) | `x`, `y` |
| `:key_press` | value (map) | `key`, `modified_key`, `physical_key`, `location`, `modifiers`, `text`, `repeat` |
| `:key_release` | value (map) | same fields as `:key_press` |

### Pane grid events

| Type | Carrier | Fields |
|---|---|---|
| `:pane_resized` | value (map) | `split`, `ratio` |
| `:pane_dragged` | value (map) | `pane`, `target`, `action`, `region`, `edge` |
| `:pane_clicked` | value (map) | `pane` |

### Category predicates

`Event::Widget` instances expose boolean predicates for quick
filtering:

```ruby
event.pointer?   # press, release, move, scroll, enter, exit, double_click
event.keyboard?  # key_press, key_release
event.pane?      # pane_resized, pane_dragged, pane_clicked, pane_focus_cycle
event.focus?     # focused, blurred
event.drag?      # drag, drag_end
```

### Custom widget event types

Custom widgets declared with `Plushie::Widget.define` can register
their own event types. Their `type:` field uses a `[widget_type,
event_name]` two-element array rather than a bare symbol. The
`value` payload is whatever the widget's `event` declaration names.
See the [Custom widgets reference](custom-widgets.md).

## Class reference

### `Event::Widget`

The workhorse event class. Covers all widget interactions: buttons,
inputs, sliders, canvas, pointer areas, sensors, panes, and custom
widgets.

| Field | Type | Description |
|---|---|---|
| `type` | Symbol or `[Symbol, Symbol]` | Event family (see tables above) |
| `id` | String | Widget ID |
| `scope` | `[String]` | Reversed ancestor scope chain (immediate parent first, `window_id` last) |
| `value` | Object or nil | Payload (scalar or symbol-keyed Hash) |
| `window_id` | String or nil | Source window |

### `Event::Key`

Keyboard press and release events from subscriptions.

| Field | Type | Description |
|---|---|---|
| `type` | `:press` or `:release` | Key action |
| `key` | Symbol or String | Logical key |
| `modified_key` | Symbol, String, or nil | Key with modifiers applied |
| `physical_key` | Symbol, String, or nil | Physical scan code |
| `location` | `:standard`, `:left`, `:right`, `:numpad` | Key location |
| `modifiers` | Hash | Modifier state (see below) |
| `text` | String or nil | Text produced by key |
| `repeat` | Boolean | Whether this is a repeat event |
| `captured` | Boolean | Whether a widget consumed it |
| `window_id` | String or nil | Source window |

#### Modifiers hash

The `modifiers` field is a symbol-keyed hash with boolean flags:

| Key | Purpose |
|---|---|
| `:ctrl` | Control key |
| `:shift` | Shift key |
| `:alt` | Alt key (Option on macOS) |
| `:logo` | Logo / Super key (Windows key, Command symbol on macOS) |
| `:command` | **Platform-aware**: Ctrl on Linux and Windows, Cmd on macOS |

`:command` is the one to use for cross-platform shortcuts. Match on
`{ command: true }` and it works on all platforms.

For code that prefers a typed wrapper, `Plushie::KeyModifiers.from_hash`
produces a `KeyModifiers` value with predicate methods (`#ctrl?`,
`#shift?`, `#alt?`, `#logo?`, `#command?`).

### `Event::Modifiers`

Modifier state change event. Fires when the set of held modifiers
changes.

| Field | Type | Description |
|---|---|---|
| `modifiers` | Hash | Current modifier state (same keys as above) |
| `captured` | Boolean | Subscription captured |
| `window_id` | String or nil | Source window |

### `Event::Ime`

Input Method Editor events from subscriptions. Lifecycle:
`:opened` -> `:preedit` (repeated) -> `:commit` -> `:closed`.

| Field | Type | Description |
|---|---|---|
| `type` | `:opened`, `:preedit`, `:commit`, `:closed` | IME phase |
| `id` | String or nil | Target widget ID |
| `scope` | `[String]` | Reversed ancestor scope chain |
| `text` | String or nil | Composition or commit text |
| `cursor` | `[Integer, Integer]` or nil | Byte offsets in preedit |
| `captured` | Boolean | Subscription captured |
| `window_id` | String or nil | Source window |

### `Event::Window`

Window lifecycle events from the renderer.

| Field | Type | Description |
|---|---|---|
| `type` | Symbol (see below) | Window event kind |
| `window_id` | String | Window identifier |
| `x`, `y` | Number or nil | Position (for `:moved`) |
| `width`, `height` | Number or nil | Size (for `:resized`, `:opened`) |
| `scale_factor` | Number or nil | DPI scale (for `:rescaled`) |
| `path` | String or nil | File path (for `:file_dropped`, `:file_hovered`) |

Window event types: `:opened`, `:closed`, `:close_requested`,
`:moved`, `:resized`, `:focused`, `:unfocused`, `:rescaled`,
`:file_hovered`, `:file_dropped`, `:files_hovered_left`.

### `Event::System`

System runtime signals.

| Field | Type | Description |
|---|---|---|
| `type` | `:theme_changed`, `:animation_frame` | System event kind |
| `tag` | Symbol or nil | Subscription tag (for `:animation_frame`) |
| `value` | Object or nil | Payload (theme name, frame delta ms, etc.) |

### `Event::Timer`

Timer tick events from `Plushie::Subscription.every`.

| Field | Type | Description |
|---|---|---|
| `tag` | Symbol | User-defined tag from the subscription |
| `timestamp` | Integer | Monotonic timestamp in ms |

### `Event::Async`

Results from `Plushie::Command.task` lambdas.

| Field | Type | Description |
|---|---|---|
| `tag` | Symbol | User-defined tag |
| `result` | Object | Return value of the async lambda |

### `Event::Stream`

Intermediate values from `Plushie::Command.stream` producers.

| Field | Type | Description |
|---|---|---|
| `tag` | Symbol | User-defined tag |
| `value` | Object | Emitted stream value |

### `Event::Effect`

Platform effect responses (file dialogs, clipboard, notifications).

| Field | Type | Description |
|---|---|---|
| `tag` | Symbol | User-defined tag from the effect command |
| `result` | `Event::Effect::Result::*` | Typed outcome |

The `result` field is a typed `Data` class under
`Event::Effect::Result`, not a tuple. Match on the specific class.

| Result class | Fields | Meaning |
|---|---|---|
| `Result::FileOpened` | `path` | `Plushie::Effect.open_file` completed |
| `Result::FilesOpened` | `paths` | Multi-file open completed |
| `Result::FileSaved` | `path` | `Plushie::Effect.save_file` completed |
| `Result::DirectorySelected` | `path` | Directory picker completed |
| `Result::DirectoriesSelected` | `paths` | Multi-directory picker completed |
| `Result::ClipboardText` | `text` | Clipboard text read |
| `Result::ClipboardHtml` | `html`, `alt_text` | Clipboard HTML read |
| `Result::ClipboardWritten` | | Clipboard write succeeded |
| `Result::ClipboardCleared` | | Clipboard clear succeeded |
| `Result::NotificationShown` | | Notification delivered |
| `Result::Cancelled` | | User cancelled (normal outcome, not an error) |
| `Result::Timeout` | | Effect timed out |
| `Result::Error` | `message` | Effect failed with reason |
| `Result::Unsupported` | | Effect not supported on this platform |
| `Result::RendererRestarted` | | Effect invalidated by renderer restart |

### `Event::CommandError`

Renderer error for a command.

| Field | Type | Description |
|---|---|---|
| `reason` | String | Machine-readable reason |
| `id` | String or nil | Target widget ID |
| `family` | String or nil | Command family name |
| `widget_type` | String or nil | Native widget type |
| `message` | String or nil | Human-readable error text |

### `Event::SessionError`

A multiplexed session encountered an error. Only delivered when the
renderer is run with `--max-sessions > 1`.

| Field | Type | Description |
|---|---|---|
| `session` | String | Session ID that errored |
| `code` | String | Stable diagnostic code |
| `error` | String | Human-readable description |

Known codes include `session_panic`, `max_sessions_reached`,
`session_channel_closed`, `writer_dead`, `font_cap_exceeded`,
`renderer_panic`, `session_reset_in_progress`,
`session_backpressure_overflow`.

### `Event::SessionClosed`

Emitted when a multiplexed session exits cleanly.

| Field | Type | Description |
|---|---|---|
| `session` | String | Session ID that was closed |
| `reason` | String | Close reason from the renderer |

## Pattern matching cookbook

### Match by widget ID

```ruby
case event
in Event::Widget[type: :click, id: "save"]
  model.with(saved: true)
end
```

### Match by type with payload

```ruby
case event
in Event::Widget[type: :input, id: "search", value: text]
  model.with(query: text)

in Event::Widget[type: :toggle, id: "dark_mode", value: on]
  model.with(dark_mode: on)

in Event::Widget[type: :slide, id: "volume", value: level]
  model.with(volume: level)
end
```

### Match by scope (dynamic lists)

When items render inside a named container with a dynamic ID, that
container's ID appears at the front of the event's scope:

```ruby
case event
in Event::Widget[type: :click, id: "delete", scope: [item_id, *]]
  model.with(items: model.items.except(item_id))
end
```

### Match key with modifiers

```ruby
case event
in Event::Key[type: :press, key: "s", modifiers: { command: true }]
  [model, Plushie::Command.task(-> { save(model) }, :saved)]

in Event::Key[type: :press, key: "Escape"]
  close_dialog(model)
end
```

### Match pointer event with device type

```ruby
case event
# Mouse click
in Event::Widget[type: :press, id: "area",
    value: { pointer: :mouse, button: :left }]
  select(model)

# Touch press
in Event::Widget[type: :press, id: "area",
    value: { pointer: :touch, finger: }]
  touch_start(model, finger)
end
```

### Match pointer event with modifiers

```ruby
case event
# Shift-click for multi-select
in Event::Widget[type: :press, id: "item",
    value: { modifiers: { shift: true } }]
  add_to_selection(model)

# Ctrl-drag for panning
in Event::Widget[type: :move, id: "canvas",
    value: { x:, y:, modifiers: { ctrl: true } }]
  pan(model, x, y)
end
```

### Match custom widget event

```ruby
case event
in Event::Widget[type: [:color_picker, :change], value: { hue: }]
  model.with(hue: hue)
end
```

### Match async result

```ruby
case event
in Event::Async[tag: :fetch, result: data]
  model.with(items: data, loading: false)
end
```

If the lambda can raise, wrap its body in a begin/rescue and return
a tagged tuple yourself, then match on that shape:

```ruby
Plushie::Command.task(-> {
  begin
    [:ok, fetch_data]
  rescue => e
    [:error, e.message]
  end
}, :fetch)

case event
in Event::Async[tag: :fetch, result: [:ok, data]]
  model.with(items: data, loading: false)

in Event::Async[tag: :fetch, result: [:error, reason]]
  model.with(error: reason, loading: false)
end
```

### Match stream values

```ruby
case event
in Event::Stream[tag: :download, value: { progress: pct }]
  model.with(progress: pct)
end
```

### Match effect result

```ruby
case event
in Event::Effect[tag: :open_file, result: Event::Effect::Result::FileOpened[path:]]
  load_file(model, path)

in Event::Effect[tag: :open_file, result: Event::Effect::Result::Cancelled[]]
  model

in Event::Effect[tag: :open_file, result: Event::Effect::Result::Error[message:]]
  model.with(error: message)
end
```

### Match timer tick

```ruby
case event
in Event::Timer[tag: :tick]
  model.with(ticks: model.ticks + 1)
end
```

### Match window events

```ruby
case event
in Event::Window[type: :close_requested, window_id:]
  close_window(model, window_id)

in Event::Window[type: :resized, width:, height:]
  model.with(width: width, height: height)
end
```

### Reconstruct the full scoped path

`Plushie::Event.target` reconstructs the forward-order path from
`id` and `scope`:

```ruby
event = Event::Widget.new(
  type: :click, id: "save",
  scope: ["form", "sidebar", "main"],
  window_id: "main"
)
Plushie::Event.target(event)
# => "sidebar/form/save"
```

### Catch-all clause

Always include a catch-all as the last branch of the `case/in`:

```ruby
case event
in ...specific matches...
else
  model
end
```

Forgetting the `else` raises `NoMatchingPatternError`. The runtime
rescues it, logs with a helpful message, and preserves the previous
model, but the missing branch is a bug and should be fixed.

## Event flow

Events travel through a fixed pipeline before reaching your
`update` method:

1. **Renderer** detects a user interaction and encodes an event
   message.
2. **Bridge** (`Plushie::Bridge`) receives the wire frame, decodes
   it via `Plushie::Protocol::Decode`, and hands the struct to the
   runtime.
3. **Runtime** (`Plushie::Runtime`) receives the event. If the
   event targets a widget with a registered `handle_event` callback,
   the runtime walks the scope chain (innermost widget handler
   first) before delivering to the app. Widget handlers can emit,
   transform, consume, or ignore events.
4. **App** receives the event in `update` (unless a widget handler
   consumed it).

### Coalescable events

High-frequency events (pointer `:move` and container `:resize`)
are coalescable. When multiple events of the same type arrive for
the same source before the runtime processes them, only the latest
is delivered. This prevents queue backup during rapid mouse
movement or window resizing. A zero-delay timer flushes coalesced
events before the next non-coalescable event, preserving relative
ordering.

### Widget handler interception

Custom widgets with `handle_event` callbacks are registered in a
handler registry derived from the current view tree. When an event
arrives, the runtime checks the scope chain for registered handlers.
Each handler can return:

- `[:emit, family, data]` - transform and re-emit as a new event
- `[:update_state, new_state]` - update widget state, suppress event
- `:ignored` - pass through to the next handler
- `:consumed` - suppress the event entirely

Render-only widgets (no events, no state) are skipped in the
registry and have zero overhead in the event path.

## See also

- [Subscriptions reference](subscriptions.md) - keyboard, pointer,
  timer, and other event sources
- [Commands reference](commands.md) - the commands that produce
  async, stream, and effect events
- [Scoped IDs reference](scoped-ids.md) - how container scoping
  affects event IDs
- [Custom widgets reference](custom-widgets.md) - declaring custom
  event types
- [Events guide](../guides/05-events.md) - events, pattern matching,
  and the event log
