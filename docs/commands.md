# Commands and subscriptions

Iced has two mechanisms beyond the basic update/view cycle: `Task` (async
commands from update) and `Subscription` (ongoing event sources). Plushie
provides Ruby equivalents for both.

## Commands

Sometimes `update` needs to do more than return a new model. It might
need to focus a text input, start an HTTP request, open a new window, or
schedule a delayed event. These are commands.

### Returning commands from update

`update` can return either a bare model or a `[model, commands]` array:

```ruby
# No commands -- just return the model:
in Event::Widget[type: :click, id: "simple"]
  model

# With commands -- return an array:
in Event::Widget[type: :click, id: "save"]
  [model, Command.async(-> { save_to_disk(model) }, :save_result)]
```

### Available commands

#### Async work

<!-- test: commands_async_construct -- keep this code block in sync with the test -->
```ruby
# Run a lambda asynchronously. Result is delivered as an event.
Command.async(callable, event_tag)

# The callable runs in a thread. When it returns, the runtime calls:
#   update(model, Event::Async[tag: event_tag, result: [:ok, result]])
```

```ruby
in Event::Widget[type: :click, id: "fetch"]
  cmd = Command.async(-> {
    resp = Net::HTTP.get(URI("https://api.example.com/data"))
    resp
  }, :data_fetched)

  [model.with(loading: true), cmd]

in Event::Async[tag: :data_fetched, result: [:ok, body]]
  model.with(loading: false, data: body)
```

#### Streaming async work

`Command.stream` spawns a thread that sends multiple intermediate results
to `update` over time. The callable receives an `emit` proc; each call to
`emit` delivers a tagged event through the normal update cycle. The
callable's final return value is also delivered.

<!-- test: commands_stream_construct -- keep this code block in sync with the test -->
```ruby
Command.stream(callable, event_tag)

# callable receives an emit proc:
#   emit.call(value) dispatches Event::Async[tag: event_tag, result: [:ok, value]]
```

```ruby
in Event::Widget[type: :click, id: "import"]
  cmd = Command.stream(->(emit) {
    rows = []
    File.foreach("big.csv").with_index(1) do |line, n|
      row = parse_row(line)
      emit.call({progress: n})
      rows << row
    end
    {complete: rows}
  }, :file_import)

  [model.with(importing: true), cmd]

in Event::Async[tag: :file_import, result: [:ok, {progress: n}]]
  model.with(rows_imported: n)

in Event::Async[tag: :file_import, result: [:ok, {complete: rows}]]
  model.with(importing: false, data: rows)
```

This is convenience sugar. You can achieve the same thing with a bare
`Thread` and a queue -- see [DIY patterns](#diy-patterns) below.

#### Cancelling async work

`Command.cancel` cancels a running `async` or `stream` command by its
event tag. The runtime tracks running threads by tag and terminates the
associated thread. If the task has already completed, this is a no-op.

<!-- test: commands_cancel_construct -- keep this code block in sync with the test -->
```ruby
Command.cancel(event_tag)
```

```ruby
in Event::Widget[type: :click, id: "cancel_import"]
  [model.with(importing: false), Command.cancel(:file_import)]
```

#### Done (lift a value)

`Command.done` wraps an already-resolved value as a command. The runtime
immediately dispatches `msg_fn.call(value)` through `update` without
spawning a thread. Useful for lifting a pure value into the command
pipeline.

<!-- test: commands_done_construct -- keep this code block in sync with the test -->
```ruby
Command.done(value, msg_fn)
```

```ruby
in Event::Widget[type: :click, id: "reset"]
  [model, Command.done(:defaults, ->(v) { [:config_loaded, v] })]
```

#### Exit

`Command.exit` terminates the application.

<!-- test: commands_exit_construct -- keep this code block in sync with the test -->
```ruby
Command.exit
```

#### Widget operations

##### Focus

<!-- test: commands_focus_construct -- keep this code block in sync with the test -->
```ruby
Command.focus(widget_id)           # Focus a text input
Command.focus_next                 # Focus next focusable widget
Command.focus_previous             # Focus previous focusable widget
```

Example:

```ruby
in Event::Widget[type: :click, id: "new_todo"]
  [model.with(input: ""), Command.focus("todo_input")]
```

##### Text operations

```ruby
Command.select_all(widget_id)                        # Select all text
Command.move_cursor_to_front(widget_id)              # Cursor to start
Command.move_cursor_to_end(widget_id)                # Cursor to end
Command.move_cursor_to(widget_id, position)          # Cursor to char position
Command.select_range(widget_id, start_pos, end_pos)  # Select character range
```

Example:

```ruby
in Event::Widget[type: :click, id: "select_word"]
  [model, Command.select_range("editor", 5, 10)]
```

##### Scroll operations

```ruby
Command.scroll_to(widget_id, offset_y)  # Scroll to absolute vertical position
Command.snap_to(widget_id, x, y)        # Snap scroll to absolute offset
Command.snap_to_end(widget_id)          # Snap to end of scrollable content
Command.scroll_by(widget_id, x, y)      # Scroll by relative delta
```

Example:

```ruby
in Event::Widget[type: :click, id: "scroll_bottom"]
  [model, Command.snap_to_end("chat_log")]
```

#### Window management

Windows are opened declaratively by including window nodes in the view tree.
There is no `open_window` command. To open a window, add a `window` node to
the tree returned by `view`. To close one, remove it or use `close_window`.

<!-- test: commands_close_window_construct -- keep this code block in sync with the test -->
```ruby
Command.close_window(window_id)                        # Close a window
Command.resize_window(window_id, width, height)        # Resize
Command.move_window(window_id, x, y)                   # Move
Command.maximize_window(window_id)                     # Maximize (default: true)
Command.maximize_window(window_id, false)              # Restore from maximized
Command.minimize_window(window_id)                     # Minimize (default: true)
Command.minimize_window(window_id, false)              # Restore from minimized
Command.set_window_mode(window_id, mode)               # :fullscreen, :windowed, etc.
Command.toggle_maximize(window_id)                     # Toggle maximize state
Command.toggle_decorations(window_id)                  # Toggle title bar/borders
Command.gain_focus(window_id)                          # Bring window to front
Command.set_window_level(window_id, level)             # :normal, :always_on_top, etc.
Command.drag_window(window_id)                         # Initiate OS window drag
Command.drag_resize_window(window_id, direction)       # Initiate OS resize from edge
Command.request_user_attention(window_id, urgency)     # Flash taskbar (:informational, :critical)
Command.screenshot(window_id, tag)                     # Capture window pixels
Command.set_resizable(window_id, value)                # Enable/disable resize
Command.set_min_size(window_id, width, height)         # Set minimum window size
Command.set_max_size(window_id, width, height)         # Set maximum window size
Command.enable_mouse_passthrough(window_id)            # Click-through window
Command.disable_mouse_passthrough(window_id)           # Normal click handling
Command.show_system_menu(window_id)                    # Show OS window menu
Command.set_icon(window_id, rgba_data, width, height)  # Set window icon (raw RGBA)
Command.set_resize_increments(window_id, width, height) # Set resize step increments
Command.allow_automatic_tabbing(enabled)               # Enable/disable macOS automatic tab grouping
```

Example:

```ruby
in Event::Widget[type: :click, id: "go_fullscreen"]
  [model, Command.set_window_mode("main", :fullscreen)]

in Event::Widget[type: :click, id: "pin_on_top"]
  [model, Command.set_window_level("main", :always_on_top)]
```

`set_icon` sends raw RGBA pixel data (base64-encoded for wire transport).
The `rgba_data` must be a binary string of `width * height * 4` bytes.

#### Window queries

Window queries are commands whose results arrive as events in `update`.
Despite accepting a `tag` parameter, window property queries use the
**effect response** transport -- results arrive as
`Event::Effect[request_id: id, result: result]` where `id` is the
**window_id string** (the `tag` is currently unused for these queries).
System queries use a separate path where the tag is used.

##### Window property queries

These go through the effect/window_op system. Results arrive in `update`
as `Event::Effect[request_id: window_id, result: [:ok, data]]` where
`window_id` is the string ID of the window and `data` varies by query type.

```ruby
Command.get_window_size(window_id, tag)
# Result: Event::Effect[request_id: window_id, result: [:ok, {"width" => w, "height" => h}]]

Command.get_window_position(window_id, tag)
# Result: Event::Effect[request_id: window_id, result: [:ok, {"x" => x, "y" => y}]]
# (nil if position is unavailable)

Command.get_mode(window_id, tag)
# Result: Event::Effect[request_id: window_id, result: [:ok, mode]]
# mode is "windowed", "fullscreen", or "hidden"

Command.get_scale_factor(window_id, tag)
# Result: Event::Effect[request_id: window_id, result: [:ok, factor]]

Command.is_maximized(window_id, tag)
# Result: Event::Effect[request_id: window_id, result: [:ok, boolean]]

Command.is_minimized(window_id, tag)
# Result: Event::Effect[request_id: window_id, result: [:ok, boolean]]

Command.raw_id(window_id, tag)
# Result: Event::Effect[request_id: window_id, result: [:ok, platform_id]]

Command.monitor_size(window_id, tag)
# Result: Event::Effect[request_id: window_id, result: [:ok, {"width" => w, "height" => h}]]
# (nil if monitor cannot be determined)
```

Example:

```ruby
in Event::Widget[type: :click, id: "check_size"]
  [model, Command.get_window_size("main", :got_size)]

in Event::Effect[request_id: "main", result: [:ok, {"width" => w, "height" => h}]]
  model.with(window_width: w, window_height: h)
```

**Note:** Because the response is keyed by `window_id` rather than `tag`,
issuing multiple different queries against the same window will produce
results that share the same `window_id` key. Distinguish them by the shape
of the `data` hash (e.g. `{"width" => _, "height" => _}` for size vs.
`{"x" => _, "y" => _}` for position).

##### System queries

System-level queries use a different transport path. Results arrive as
dedicated events where the **tag** (stringified) identifies the response.

```ruby
Command.get_system_theme(tag)
# Result: Event::System[type: :system_theme, tag: tag_string, data: mode]
# mode is "light", "dark", or "none"

Command.get_system_info(tag)
# Result: Event::System[type: :system_info, tag: tag_string, data: info_hash]
# info_hash keys: "system_name", "system_kernel", "system_version",
#   "system_short_version", "cpu_brand", "cpu_cores", "memory_total",
#   "memory_used", "graphics_backend", "graphics_adapter"
# Requires the renderer to be built with the `sysinfo` feature.
```

**Important:** The `tag` arrives as a **string** in `update`, even if you
pass a symbol. `Command.get_system_theme(:theme_detected)` produces
`Event::System[type: :system_theme, tag: "theme_detected", data: mode]` --
match on the string, not the symbol.

```ruby
in Event::Widget[type: :click, id: "detect_theme"]
  [model, Command.get_system_theme(:theme_detected)]

in Event::System[type: :system_theme, tag: "theme_detected", data:]
  model.with(os_theme: data)
```

#### Image operations

In-memory images can be created, updated, and deleted at runtime. The
`Image` widget references them via `{handle: "name"}` as its source.

```ruby
Command.create_image(handle, data)                     # From PNG/JPEG bytes
Command.create_image(handle, width, height, pixels)    # From raw RGBA pixels
Command.update_image(handle, data)                     # Update with PNG/JPEG
Command.update_image(handle, width, height, pixels)    # Update with raw RGBA
Command.delete_image(handle)                           # Remove in-memory image
Command.clear_images                                   # Remove all in-memory images
```

Example:

```ruby
in Event::Widget[type: :click, id: "load_preview"]
  cmd = Command.async(-> {
    File.binread("preview.png")
  }, :preview_loaded)
  [model, cmd]

in Event::Async[tag: :preview_loaded, result: [:ok, data]]
  [model, Command.create_image("preview", data)]
```

Raw RGBA variant for procedurally generated images:

```ruby
in Event::Widget[type: :click, id: "generate_gradient"]
  width = 256
  height = 256
  pixels = String.new(encoding: Encoding::BINARY)
  height.times do |y|
    width.times do |x|
      pixels << [x, y, 128, 255].pack("C4")  # RGBA
    end
  end
  [model, Command.create_image("gradient", width, height, pixels)]
```

#### PaneGrid operations

Commands for manipulating panes in a `PaneGrid` widget.

```ruby
Command.pane_split(widget_id, pane, axis, new_pane_id)  # Split a pane
Command.pane_close(widget_id, pane)                     # Close a pane
Command.pane_swap(widget_id, pane_a, pane_b)            # Swap two panes
Command.pane_maximize(widget_id, pane)                  # Maximize a pane
Command.pane_restore(widget_id)                         # Restore from maximized
```

Example:

```ruby
in Event::Widget[type: :click, id: "split_editor"]
  cmd = Command.pane_split("pane_grid", "editor", :horizontal, "new_editor")
  [model, cmd]

in Event::Widget[type: :click, id: "close_pane"]
  [model, Command.pane_close("pane_grid", "editor")]

in Event::Widget[type: :click, id: "swap_panes"]
  [model, Command.pane_swap("pane_grid", "left", "right")]

in Event::Widget[type: :click, id: "maximize_pane"]
  [model, Command.pane_maximize("pane_grid", "editor")]

in Event::Widget[type: :click, id: "restore_panes"]
  [model, Command.pane_restore("pane_grid")]
```

#### Timers

<!-- test: commands_send_after_construct -- keep this code block in sync with the test -->
```ruby
Command.send_after(delay_ms, event)
```

```ruby
in Event::Widget[type: :click, id: "flash_message"]
  updated = model.with(message: "Saved!")
  [updated, Command.send_after(3000, :clear_message)]

in [:clear_message]
  model.with(message: nil)
```

#### Batch

<!-- test: commands_batch_construct -- keep this code block in sync with the test -->
```ruby
Command.batch([
  Command.focus("name_input"),
  Command.send_after(5000, :auto_save)
])
```

Commands in a batch are dispatched sequentially. Async commands spawn
concurrent threads, but the dispatch loop itself processes each command in
order.

#### Extension commands

Push data directly to a native Rust extension widget without triggering the
view/diff/patch cycle. Used for high-frequency data like terminal output or
streaming log lines.

```ruby
# Single command
Command.extension_command("term-1", "write", {data: output})

# Batch (all processed before next view cycle)
Command.extension_commands([
  ["term-1", "write", {data: line1}],
  ["log-1", "append", {line: entry}]
])
```

Extension commands are only meaningful for widgets backed by a
`WidgetExtension` Rust implementation. They are silently ignored for
widgets without an extension handler.

#### No-op

When `update` returns a bare model (not an array), the runtime treats it as
`[model, Command.none]`. You never need to write `Command.none` explicitly.

### Chaining commands

In iced, commands support `.then()` and `.chain()` for sequencing async
work. Plushie does not need dedicated chaining combinators because the Elm
update cycle provides this naturally: each `update` can return
`[model, commands]`, and the result of each command feeds back into
`update` as an event, which can return more commands.

The model is updated and `view` is re-rendered between each step. This
is actually more powerful than iced's chaining because you get full model
updates and UI refreshes at every link in the chain, not just at the end.

```ruby
# Step 1: user clicks "deploy" -- validate first
in Event::Widget[type: :click, id: "deploy"]
  cmd = Command.async(-> { validate_config(model.config) }, :validated)
  [model.with(status: :validating), cmd]

# Step 2: validation result arrives -- if OK, start the build
in Event::Async[tag: :validated, result: [:ok, :ok]]
  cmd = Command.async(-> { build_release(model.config) }, :built)
  [model.with(status: :building), cmd]

in Event::Async[tag: :validated, result: [:ok, [:error, reason]]]
  model.with(status: {failed: reason})

# Step 3: build result arrives -- if OK, push it
in Event::Async[tag: :built, result: [:ok, artifact]]
  cmd = Command.async(-> { push_artifact(artifact) }, :deployed)
  [model.with(status: :deploying), cmd]

# Step 4: done
in Event::Async[tag: :deployed, result: [:ok, :ok]]
  model.with(status: :live)
```

Each step is a separate `update` clause with its own model state. The
UI reflects progress at every stage. No special chaining API needed --
the architecture is the API.

### DIY patterns

The `Command` module is convenience sugar, not a requirement. Ruby
already has all the concurrency primitives you need. Some users will
prefer the direct approach, and that is perfectly fine.

#### Streaming with bare threads

The runtime processes events from a `Thread::Queue`. You can push messages
to it directly from any thread, and they arrive as events in `update`:

```ruby
in Event::Widget[type: :click, id: "import"]
  runtime_queue = Plushie.runtime_queue

  pid = Thread.new do
    File.foreach("big.csv").with_index(1) do |line, n|
      row = parse_row(line)
      runtime_queue.push([:import_progress, n, row])
    end
    runtime_queue.push(:import_done)
  end

  model.with(importing: true, import_thread: pid)

in [:import_progress, n, row]
  model.with(rows_imported: n, data: model.data + [row])

in [:import_done]
  model.with(importing: false, import_thread: nil)
```

#### Cancellation with Thread#kill

If you track the thread yourself, cancellation is just `Thread#kill`:

```ruby
in Event::Widget[type: :click, id: "cancel_import"]
  model.import_thread&.kill
  model.with(importing: false, import_thread: nil)
```

#### When to use which

Use `Command.async` and `Command.stream` when you want the runtime
to manage thread lifecycle and deliver results through the standard
tagged event convention. Use bare threads when you need more control
over message shapes, supervision, or when the command abstraction feels
like overhead for your use case.

### How commands work internally

Commands are data. They describe what should happen, not how. The runtime
interprets them:

- **Async commands** spawn a Ruby `Thread` managed by the runtime.
  When the thread completes, the result is wrapped in the event tag and
  dispatched through `update`.
- **Widget operations** are encoded as wire messages and sent to the
  renderer.
- **Window commands** are encoded as wire messages to the renderer.
- **Window property queries** (get_size, get_position, etc.) are sent as
  window_op wire messages. The renderer responds with an `effect_response`
  keyed by window_id. **System queries** (get_system_theme, get_system_info)
  use a separate `query_response` wire message keyed by tag.
- **Image operations** are encoded as wire messages to the renderer.
- **PaneGrid operations** are encoded as widget ops sent to the renderer.
- **Timers** use `Thread.new { sleep(delay); queue.push(event) }` under
  the hood.

Commands are not side effects in `update`. They are descriptions of side
effects that the runtime executes after `update` returns. This keeps
`update` testable:

```ruby
def test_clicking_fetch_returns_async_command
  app = MyApp.new
  model, cmd = app.update(Model.new(loading: false), Event::Widget.new(type: :click, id: "fetch"))

  assert model.loading
  assert_equal :async, cmd.type
end
```

## Subscriptions

Subscriptions are ongoing event sources. Unlike commands (one-shot),
subscriptions produce events continuously as long as they are active.

**Important: tag semantics differ by subscription type.** For timer
subscriptions (`every`), the tag becomes the event wrapper -- `update`
receives `Event::Timer[tag: tag, timestamp: ts]`. For all renderer
subscriptions (keyboard, mouse, window, etc.), the tag is management-only
and does NOT appear in the event. Renderer events arrive as fixed structs
like `Event::Key[type: :press, ...]` regardless of what tag you chose.

### The subscribe callback

```ruby
def subscribe(model)
  subs = []

  # Tick every second while the timer is running
  if model.timer_running
    subs << Subscription.every(1000, :tick)
  end

  # Always listen for keyboard shortcuts
  subs << Subscription.on_key_press(:key_event)

  subs
end
```

`subscribe` is called after every `update`. The runtime diffs the
returned subscription list against the previous one and starts/stops
subscriptions as needed. Subscriptions are identified by their
specification -- returning the same `Subscription.every(1000, :tick)` on
consecutive calls keeps the existing subscription alive; removing it stops
it.

### Available subscriptions

#### Time

```ruby
Subscription.every(interval_ms, event_tag)
# Delivers: Event::Timer[tag: event_tag, timestamp: ts]
```

#### Keyboard

```ruby
Subscription.on_key_press(event_tag)
# Delivers: Event::Key[type: :press, ...]

Subscription.on_key_release(event_tag)
# Delivers: Event::Key[type: :release, ...]

Subscription.on_modifiers_changed(event_tag)
# Delivers: Event::Modifiers[shift: bool, ctrl: bool, ...]

# The event_tag is used by the runtime to register/unregister the
# subscription with the renderer. It is NOT included in the event
# delivered to update. See docs/events.md for the full Key and
# Modifiers struct definitions.
```

#### Window lifecycle

```ruby
Subscription.on_window_close(event_tag)
# Delivers: [event_tag, window_id]

Subscription.on_window_open(event_tag)
# Delivers: Event::Window[type: :opened, window_id: wid, position: pos, width: w, height: h]

Subscription.on_window_resize(event_tag)
# Delivers: Event::Window[type: :resized, window_id: wid, width: w, height: h]

Subscription.on_window_focus(event_tag)
# Delivers: Event::Window[type: :focused, window_id: wid]

Subscription.on_window_unfocus(event_tag)
# Delivers: Event::Window[type: :unfocused, window_id: wid]

Subscription.on_window_move(event_tag)
# Delivers: Event::Window[type: :moved, window_id: wid, x: x, y: y]

Subscription.on_window_event(event_tag)
# Delivers: various Event::Window[type: ..., ...] (catch-all for window events)
```

#### Mouse

```ruby
Subscription.on_mouse_move(event_tag)
# Delivers: Event::Mouse[type: :moved, x: x, y: y]

Subscription.on_mouse_button(event_tag)
# Delivers: Event::Mouse[type: :button_pressed, button: btn]
#        or Event::Mouse[type: :button_released, button: btn]

Subscription.on_mouse_scroll(event_tag)
# Delivers: [:wheel_scrolled, delta_x, delta_y, unit]
```

#### Touch

```ruby
Subscription.on_touch(event_tag)
# Delivers: Event::Touch[type: :pressed, finger_id: fid, x: x, y: y]
#           Event::Touch[type: :moved, ...]
#           Event::Touch[type: :lifted, ...]
#           Event::Touch[type: :lost, ...]
```

#### IME (Input Method Editor)

```ruby
Subscription.on_ime(event_tag)
# Delivers: Event::Ime[type: :opened]
#           Event::Ime[type: :preedit, text: text, cursor: [start_pos, end_pos] | nil]
#           Event::Ime[type: :commit, text: text]
#           Event::Ime[type: :closed]
```

#### System

```ruby
Subscription.on_theme_change(event_tag)
# Delivers: Event::System[type: :theme_changed, data: mode]  (mode is "light" or "dark")

Subscription.on_animation_frame(event_tag)
# Delivers: Event::System[type: :animation_frame, data: timestamp]

Subscription.on_file_drop(event_tag)
# Delivers: Event::Window[type: :file_dropped, window_id: wid, path: path]
#           Event::Window[type: :file_hovered, window_id: wid, path: path]
#           Event::Window[type: :files_hovered_left, window_id: wid]
```

#### Catch-all

```ruby
Subscription.on_event(event_tag)
# Receives all renderer events. Shape varies by event family.
```

#### Batch

```ruby
Subscription.batch(subscriptions)
# Combines multiple subscriptions into a flat list. Identity function.
```

### Event rate limiting

The renderer supports rate limiting for high-frequency events (mouse moves,
scroll, animation frames, slider drags, etc.). This reduces wire traffic
and host CPU usage. Three configuration levels, in order of priority:

#### Per-widget `event_rate` prop

Widgets that emit high-frequency events accept an `event_rate` option:

```ruby
# Volume slider limited to 15 events/sec, seek bar at 60:
slider("volume", [0, 100], model.volume, event_rate: 15)
slider("seek", [0, model.duration], model.position, event_rate: 60)
```

Supported on: `Slider`, `VerticalSlider`, `Canvas`, `MouseArea`, `Sensor`,
`PaneGrid`, and all extension widgets.

#### Per-subscription `max_rate`

Renderer subscriptions accept a `max_rate` option:

```ruby
# Rate-limit mouse moves to 30 events per second:
Subscription.on_mouse_move(:mouse, max_rate: 30)

# Animation frames at 60fps:
Subscription.on_animation_frame(:frame, max_rate: 60)

# Subscribe but never emit (capture tracking only):
Subscription.on_mouse_move(:mouse, max_rate: 0)
```

Timer subscriptions (`every`) do not support `max_rate`.

#### Global `default_event_rate` setting

A global default applied to all coalescable event types:

```ruby
def settings
  {default_event_rate: 60}
end
```

Set to 60 for most apps. Lower for dashboards or remote rendering.
Omit for unlimited (current default behavior).

### Subscription lifecycle

Subscriptions are declarative. You do not start or stop them imperatively.
You return a list from `subscribe`, and the runtime manages the rest:

```ruby
def subscribe(model)
  subs = []

  if model.polling
    subs << Subscription.every(5000, :poll)
  end

  # Listen for keyboard shortcuts only when the editor is focused
  if model.editor_focused
    subs << Subscription.on_key_press(:editor_keys)
  end

  # Always track window resize
  subs << Subscription.on_window_resize(:win_resize)

  subs
end

in Event::Widget[type: :click, id: "start_polling"]
  model.with(polling: true)

in Event::Widget[type: :click, id: "stop_polling"]
  model.with(polling: false)

in Event::Timer[tag: :poll]
  [model, Command.async(-> { fetch_data }, :data_received)]

in Event::Async[tag: :data_received, result: [:ok, data]]
  model.with(data: data)
```

When `polling` becomes true, the runtime starts the timer. When it becomes
false, the runtime stops it. No explicit cleanup needed. The same applies to
the keyboard subscription -- it activates and deactivates based on model
state.

### How subscriptions work internally

- **Time subscriptions** use a Ruby `Thread` with a `sleep` loop.
- **Keyboard, mouse, touch, and window subscriptions** are registered with
  the renderer via wire messages. The renderer sends events when they occur.
- **System subscriptions** (theme change, animation frame, file drop) are
  also renderer-side event sources.

Subscriptions that require the renderer (everything except timers) are
paused during renderer restart and resumed once the renderer is back.

## Application settings

The `settings` callback is documented in
[app-behaviour.md](app-behaviour.md). Notable settings relevant to
commands and rendering:

- `vsync` -- boolean (default `true`). Controls vertical sync. Set to
  `false` for uncapped frame rates (useful for benchmarks or animation-heavy
  apps at the cost of higher GPU usage).
- `scale_factor` -- number (default `1.0`). Global UI scale factor applied
  to all windows. Values greater than 1.0 make the UI larger; less than 1.0
  makes it smaller.
- `default_event_rate` -- integer. Maximum events per second for coalescable
  event types. Omit for unlimited (default). See [Event rate limiting](#event-rate-limiting).

```ruby
def settings
  {
    antialiasing: true,
    vsync: false,
    scale_factor: 1.5,
    default_event_rate: 60
  }
end
```

## Commands vs. effects

Commands are Ruby-side operations handled by the runtime. Effects are
native platform operations handled by the renderer (see [effects.md](effects.md)).

| | Commands | Effects |
|---|---|---|
| Handled by | Ruby runtime | Rust renderer |
| Examples | async work, timers, focus | file dialogs, clipboard, notifications |
| Transport | internal | wire protocol request/response |
| Return from | `update` | `update` (via `Plushie::Effects`) |

Widget operations and window commands are a hybrid -- they are initiated
from the Ruby side but executed by the renderer. They use the command
mechanism for the API but effect/effect_response for the transport.
