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

#### Cancelling async work

```ruby
Command.cancel(event_tag)
```

```ruby
in Event::Widget[type: :click, id: "cancel_import"]
  [model.with(importing: false), Command.cancel(:file_import)]
```

#### Done (lift a value)

`Command.done` wraps an already-resolved value as a command. The runtime
immediately dispatches it through `update` without spawning a thread.

```ruby
Command.done(value, msg_fn)
```

#### Exit

```ruby
Command.exit
```

#### Widget operations

##### Focus

```ruby
Command.focus(widget_id)           # Focus a text input
Command.focus_next                 # Focus next focusable widget
Command.focus_previous             # Focus previous focusable widget
```

##### Text operations

```ruby
Command.select_all(widget_id)
Command.move_cursor_to_front(widget_id)
Command.move_cursor_to_end(widget_id)
Command.move_cursor_to(widget_id, position)
Command.select_range(widget_id, start_pos, end_pos)
```

##### Scroll operations

```ruby
Command.scroll_to(widget_id, offset_y)
Command.snap_to(widget_id, x, y)
Command.snap_to_end(widget_id)
Command.scroll_by(widget_id, x, y)
```

#### Window management

Windows are opened declaratively by including window nodes in the view tree.
There is no `open_window` command. To close one, remove it or use
`close_window`.

```ruby
Command.close_window(window_id)
Command.resize_window(window_id, width, height)
Command.move_window(window_id, x, y)
Command.maximize_window(window_id)
Command.minimize_window(window_id)
Command.set_window_mode(window_id, mode)       # :fullscreen, :windowed, etc.
Command.toggle_maximize(window_id)
Command.toggle_decorations(window_id)
Command.gain_focus(window_id)
Command.set_window_level(window_id, level)      # :normal, :always_on_top, etc.
Command.drag_window(window_id)
Command.request_user_attention(window_id, urgency)
Command.screenshot(window_id, tag)
Command.set_resizable(window_id, value)
Command.set_min_size(window_id, width, height)
Command.set_max_size(window_id, width, height)
Command.set_icon(window_id, rgba_data, width, height)
```

#### Window queries

Window queries are commands whose results arrive as events in `update`.

##### Window property queries

```ruby
Command.get_window_size(window_id, tag)
# Result: Event::Effect[request_id: window_id, result: [:ok, {"width" => w, "height" => h}]]

Command.get_window_position(window_id, tag)
Command.get_mode(window_id, tag)
Command.get_scale_factor(window_id, tag)
Command.is_maximized(window_id, tag)
Command.is_minimized(window_id, tag)
Command.monitor_size(window_id, tag)
```

##### System queries

```ruby
Command.get_system_theme(tag)
# Result: Event::System[type: :system_theme, tag: "theme_detected", data: mode]

Command.get_system_info(tag)
```

**Important:** The `tag` arrives as a **string** in `update`, even if you
pass a symbol.

```ruby
in Event::Widget[type: :click, id: "detect_theme"]
  [model, Command.get_system_theme(:theme_detected)]

in Event::System[type: :system_theme, tag: "theme_detected", data:]
  model.with(os_theme: data)
```

#### Image operations

```ruby
Command.create_image(handle, data)
Command.create_image(handle, width, height, pixels)
Command.update_image(handle, data)
Command.delete_image(handle)
```

#### PaneGrid operations

```ruby
Command.pane_split(widget_id, pane, axis, new_pane_id)
Command.pane_close(widget_id, pane)
Command.pane_swap(widget_id, pane_a, pane_b)
Command.pane_maximize(widget_id, pane)
Command.pane_restore(widget_id)
```

#### Timers

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

```ruby
Command.batch([
  Command.focus("name_input"),
  Command.send_after(5000, :auto_save)
])
```

#### Extension commands

```ruby
Command.extension_command("term-1", "write", {data: output})

Command.extension_commands([
  ["term-1", "write", {data: line1}],
  ["log-1", "append", {line: entry}]
])
```

### Chaining commands

Plushie does not need dedicated chaining combinators because the Elm
update cycle provides this naturally: each `update` can return
`[model, commands]`, and the result of each command feeds back into
`update` as an event, which can return more commands.

```ruby
# Step 1: user clicks "deploy" -- validate first
in Event::Widget[type: :click, id: "deploy"]
  cmd = Command.async(-> { validate_config(model.config) }, :validated)
  [model.with(status: :validating), cmd]

# Step 2: validation result arrives -- if OK, start the build
in Event::Async[tag: :validated, result: [:ok, :ok]]
  cmd = Command.async(-> { build_release(model.config) }, :built)
  [model.with(status: :building), cmd]

# Step 3: build result -- if OK, push it
in Event::Async[tag: :built, result: [:ok, artifact]]
  cmd = Command.async(-> { push_artifact(artifact) }, :deployed)
  [model.with(status: :deploying), cmd]

# Step 4: done
in Event::Async[tag: :deployed, result: [:ok, :ok]]
  model.with(status: :live)
```

### DIY patterns

The `Command` module is convenience sugar, not a requirement. Ruby
already has all the concurrency primitives you need.

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

#### Cancellation

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
over message shapes or when the command abstraction feels like overhead
for your use case.

## Subscriptions

Subscriptions are ongoing event sources. Unlike commands (one-shot),
subscriptions produce events continuously as long as they are active.

**Important: tag semantics differ by subscription type.** For timer
subscriptions (`every`), the tag becomes the event wrapper. For all
renderer subscriptions (keyboard, mouse, window, etc.), the tag is
management-only and does NOT appear in the event.

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
subscriptions as needed.

### Available subscriptions

#### Time

```ruby
Subscription.every(interval_ms, event_tag)
# Delivers: Event::Timer[tag: event_tag, timestamp: ts]
```

#### Keyboard

```ruby
Subscription.on_key_press(event_tag)
Subscription.on_key_release(event_tag)
Subscription.on_modifiers_changed(event_tag)
```

#### Window lifecycle

```ruby
Subscription.on_window_close(event_tag)
Subscription.on_window_open(event_tag)
Subscription.on_window_resize(event_tag)
Subscription.on_window_focus(event_tag)
Subscription.on_window_unfocus(event_tag)
Subscription.on_window_move(event_tag)
Subscription.on_window_event(event_tag)
```

#### Mouse

```ruby
Subscription.on_mouse_move(event_tag)
Subscription.on_mouse_button(event_tag)
Subscription.on_mouse_scroll(event_tag)
```

#### Touch

```ruby
Subscription.on_touch(event_tag)
```

#### IME

```ruby
Subscription.on_ime(event_tag)
```

#### System

```ruby
Subscription.on_theme_change(event_tag)
Subscription.on_animation_frame(event_tag)
Subscription.on_file_drop(event_tag)
```

### Event rate limiting

The renderer supports rate limiting for high-frequency events.

#### Per-widget `event_rate` prop

```ruby
slider("volume", [0, 100], model.volume, event_rate: 15)
slider("seek", [0, model.duration], model.position, event_rate: 60)
```

#### Per-subscription `max_rate`

```ruby
Subscription.on_mouse_move(:mouse, max_rate: 30)
Subscription.on_animation_frame(:frame, max_rate: 60)
Subscription.on_mouse_move(:mouse, max_rate: 0)  # capture only
```

#### Global `default_event_rate` setting

```ruby
def settings
  {default_event_rate: 60}
end
```

### Subscription lifecycle

Subscriptions are declarative. You do not start or stop them imperatively.
You return a list from `subscribe`, and the runtime manages the rest:

```ruby
def subscribe(model)
  if model.polling
    [Subscription.every(5000, :poll)]
  else
    []
  end
end

# ...

in Event::Widget[type: :click, id: "start_polling"]
  model.with(polling: true)

in Event::Widget[type: :click, id: "stop_polling"]
  model.with(polling: false)

in Event::Timer[tag: :poll]
  [model, Command.async(-> { fetch_data }, :data_received)]
```

## Application settings

The `settings` callback is documented in
[app-behaviour.md](app-behaviour.md). Notable settings relevant to
commands and rendering:

- `vsync` -- boolean (default `true`). Controls vertical sync.
- `scale_factor` -- number (default `1.0`). Global UI scale factor.
- `default_event_rate` -- integer. Maximum events per second for coalescable
  event types.

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
