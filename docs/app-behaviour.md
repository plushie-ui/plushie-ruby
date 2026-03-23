# App behaviour

`Plushie::App` is the only module an app developer includes. It follows the
Elm architecture: model, update, view.

## Callbacks

```ruby
# Required:
def init(opts) -> model | [model, Command]
def update(model, event) -> model | [model, Command]
def view(model) -> Node

# Optional:
def subscribe(model) -> [Subscription]
def handle_renderer_exit(model, exit_reason) -> model
def window_config(model) -> Hash
def settings -> Hash
```

### init

Returns the initial model, optionally with commands. Called once when the
runtime starts.

<!-- test: app_behaviour_init_bare_model, app_behaviour_init_with_command -- keep this code block in sync with the test -->
```ruby
def init(_opts)
  Model.new(
    todos: [],
    input: "",
    filter: :all
  )
end

# Or with a command:
def init(_opts)
  model = Model.new(todos: [], loading: true)
  [model, Command.async(-> { load_todos_from_disk }, :todos_loaded)]
end
```

The model can be any object, but `Plushie::Model.define` works best. The
runtime does not inspect or modify the model -- it is fully owned by the
app.

`opts` is a hash passed through from the runtime start call, so apps can
accept configuration at startup.

### update

Receives the current model and an event, returns the next model -- optionally
with commands.

<!-- test: app_behaviour_update_add_todo, app_behaviour_update_submit_returns_focus -- keep this code block in sync with the test -->
```ruby
def update(model, event)
  case event
  in Event::Widget[type: :click, id: "add_todo"]
    new_todo = {id: SecureRandom.uuid, text: model.input, done: false}
    model.with(todos: [new_todo] + model.todos, input: "")

  in Event::Widget[type: :input, id: "todo_field", value:]
    model.with(input: value)

  # Returning commands:
  in Event::Widget[type: :submit, id: "todo_field"]
    new_todo = {id: SecureRandom.uuid, text: model.input, done: false}
    updated = model.with(todos: [new_todo] + model.todos, input: "")
    [updated, Command.focus("todo_field")]

  else
    model
  end
end
```

Return a bare model when no side effects are needed. Return `[model, command]`
when you need async work, widget operations, window management, or timers.
See [commands.md](commands.md) for the full command API.

Events are Data types under `Plushie::Event::*`. See [events.md](events.md)
for the full event taxonomy. Common families:

- `Event::Widget[type: :click, id: id]` -- button press
- `Event::Widget[type: :input, id: id, value: val]` -- text input change
- `Event::Widget[type: :select, id: id, value: val]` -- selection change
- `Event::Widget[type: :toggle, id: id, value: val]` -- checkbox/toggler change
- `Event::Widget[type: :submit, id: id, value: val]` -- form field submission
- `Event::Key[type: :press, ...]` -- keyboard event (via subscription)
- `Event::Key[type: :release, ...]` -- keyboard release (via subscription)
- `Event::Window[type: :close_requested, window_id: id]` -- window close requested
- `Event::Window[type: :resized, window_id: id, width: w, height: h]` -- window resized
- `Event::Canvas[type: :press, id: id, x: x, y: y, button: btn]` -- canvas interaction
- `Event::Sensor[type: :resize, id: id, width: w, height: h]` -- sensor size change
- `Event::Pane[type: :clicked, id: id, pane: pane]` -- pane grid click

### view

Receives the current model, returns a UI tree.

<!-- test: app_behaviour_view_basic_structure -- keep this code block in sync with the test -->
```ruby
def view(model)
  window("main", title: "Todos") do
    column(padding: 16, spacing: 8) do
      row(spacing: 8) do
        text_input("todo_field", model.input, placeholder: "What needs doing?")
        button("add_todo", "Add")
      end

      filtered_todos(model).each do |todo|
        row(todo[:id], spacing: 8) do
          checkbox("toggle", todo[:done])
          text(todo[:text])
        end
      end
    end
  end
end
```

The view method is called after every update. It must be a pure function
of the model. The runtime diffs the returned tree against the previous one
and sends only the changes to the renderer.

UI trees are `Node` objects. The block-based DSL provides builder methods
for composition, but you can also build nodes directly if preferred.

## Lifecycle

```
Plushie.run(MyApp, opts)
  |
  v
init(opts) -> [model, commands]
  |
  v
subscribe(model) -> active subscriptions
  |
  v
view(model) -> initial tree -> send snapshot to renderer
  |
  v
[event from renderer / subscription / command result]
  |
  v
update(model, event) -> [model, commands]
  |
  v
subscribe(model) -> diff subscriptions (start/stop as needed)
  |
  v
view(model) -> next tree -> diff -> send patch to renderer
  |
  v
[repeat from event]
```

### subscribe (optional)

Returns a list of active subscriptions based on the current model. Called
after every `update`. The runtime diffs the list and starts/stops
subscriptions automatically.

<!-- test: app_behaviour_subscribe_without_auto_refresh, app_behaviour_subscribe_with_auto_refresh -- keep this code block in sync with the test -->
```ruby
def subscribe(model)
  subs = [Subscription.on_key_press(:key_event)]

  if model.auto_refresh
    [Subscription.every(5000, :refresh)] + subs
  else
    subs
  end
end
```

Default: `[]` (no subscriptions). See [commands.md](commands.md) for the
full subscription API.

### handle_renderer_exit (optional)

Called when the renderer process exits unexpectedly. Return the model to
use when the renderer restarts. Default: return model unchanged.

```ruby
def handle_renderer_exit(model, _reason)
  model.with(status: :renderer_restarting)
end
```

### window_config (optional)

Called when windows are opened, including at startup and after renderer
restart. Default: single window with app class name as title.

<!-- test: app_behaviour_window_config -- keep this code block in sync with the test -->
```ruby
def window_config(_model)
  {
    title: "My App",
    width: 800,
    height: 600,
    min_size: {width: 400, height: 300},
    resizable: true,
    theme: :dark
  }
end
```

### settings (optional)

Called once at startup to provide application-level settings to the
renderer. Returns a hash.

<!-- test: app_behaviour_settings -- keep this code block in sync with the test -->
```ruby
def settings
  {
    default_font: {family: "monospace"},
    default_text_size: 16,
    antialiasing: true,
    fonts: ["priv/fonts/Inter.ttf"]
  }
end
```

Supported keys:

- `default_font` -- a font specification hash (same format as font props)
- `default_text_size` -- a number (pixels)
- `antialiasing` -- boolean
- `fonts` -- list of font file paths to load
- `vsync` -- boolean (default `true`). Controls vertical sync.
- `scale_factor` -- number (default `1.0`). Global UI scale factor applied
  to all windows.

To follow the OS light/dark preference automatically, set the window
`theme` prop to `:system`. The renderer detects the current OS theme
and applies the matching built-in light or dark theme.

Default: `{}` (renderer uses its own defaults).

## Starting the runtime

```ruby
# From code:
Plushie.run(MyApp)
Plushie.run(MyApp, name: :my_app, binary: "/path/to/plushie")

# Start without blocking:
pid = Plushie.start(MyApp, name: :my_app)

# From the command line:
bundle exec ruby lib/my_app.rb
```

## Testing

Apps can be tested without a renderer:

```ruby
class MyAppTest < Minitest::Test
  def test_adding_a_todo
    model = MyApp.new.init({})
    model = MyApp.new.update(model, Event::Widget.new(type: :input, id: "todo_field", value: "Buy milk"))
    model = MyApp.new.update(model, Event::Widget.new(type: :click, id: "add_todo"))

    assert_equal "Buy milk", model.todos.first[:text]
    assert_equal "", model.input
  end

  def test_view_renders_todo_list
    model = Model.new(todos: [{id: 1, text: "Buy milk", done: false}], input: "", filter: :all)
    tree = Plushie::Tree.normalize(MyApp.new.view(model))

    assert Plushie::Tree.find(tree, "todo:1")
  end
end
```

Since `update` is a pure function and `view` returns plain nodes, no special
test infrastructure is needed. The renderer is not involved.

## Configuration

Application-level configuration is set via `Plushie.configure` or
environment variables.

| Key | Type | Default | Description |
|---|---|---|---|
| `test_backend` | `:mock`, `:headless`, `:windowed` | `:mock` | Test backend used by `Plushie::Test::Case`. Override per-run with `PLUSHIE_TEST_BACKEND` env var. |
| `test_format` | `:json`, `:msgpack` | `:msgpack` | Wire format for test sessions. Set to `:json` for easier debugging. |
| `extension_config` | `Hash` | `{}` | Configuration hash passed to widget extensions at runtime. |

## Multi-window

Plushie supports multiple windows driven declaratively from `view`. Windows
are nodes in the tree -- if a window node is present, the window is open; if
it disappears, the window closes.

### Returning multiple windows

`view` returns a list of window nodes (or a single window node for
single-window apps):

```ruby
def view(model)
  windows = [
    window("main", title: "My App") do
      main_content(model)
    end
  ]

  if model.inspector_open
    inspector = window("inspector", title: "Inspector", size: [400, 600]) do
      inspector_panel(model)
    end
    windows + [inspector]
  else
    windows
  end
end
```

Single-window apps can return a single window node directly (no array
needed). The runtime normalizes both forms internally.

### Window identity

Each window node has an `id` (like all nodes). The renderer uses this ID
to track which OS window corresponds to which tree node:

- **New ID appears** -- renderer opens a new OS window.
- **Existing ID present** -- renderer updates that window's content.
- **ID disappears** -- renderer closes that OS window.

Window IDs must be stable strings. Do not generate random IDs per render
or the renderer will close and reopen the window on every update.

### Window properties

```ruby
window("main",
  title: "My App",
  size: [800, 600],
  min_size: [400, 300],
  max_size: [1920, 1080],
  position: [100, 100],
  resizable: true,
  closeable: true,
  minimizable: true,
  decorations: true,
  transparent: false,
  visible: true,
  theme: :dark,         # or :system to follow OS preference
  level: :normal,       # :normal | :always_on_top | :always_on_bottom
  scale_factor: 1.5     # per-window UI scale (overrides global setting)
) do
  content(model)
end
```

Properties are set when the window first appears. To change properties
after creation, use window commands:

```ruby
def update(model, event)
  case event
  in Event::Widget[type: :click, id: "go_fullscreen"]
    [model, Command.set_window_mode("main", :fullscreen)]
  else
    model
  end
end
```

### Window events

Window events include the window ID so your app knows which window they
came from:

```ruby
def update(model, event)
  case event
  in Event::Window[type: :close_requested, window_id: "inspector"]
    model.with(inspector_open: false)

  in Event::Window[type: :close_requested, window_id: "main"]
    if model.unsaved_changes
      model.with(confirm_exit: true)
    else
      [model, Command.close_window("main")]
    end

  in Event::Window[type: :resized, window_id: "main", width:, height:]
    model.with(window_size: [width, height])

  in Event::Window[type: :focused, window_id:]
    model.with(active_window: window_id)

  else
    model
  end
end
```

### Window close behaviour

By default, when the user clicks the close button on a window, the
renderer sends a `Event::Window[type: :close_requested, ...]` event instead
of closing immediately. Your app decides what to do:

```ruby
# Let it close (remove it from view):
in Event::Window[type: :close_requested, window_id: "settings"]
  model.with(settings_open: false)

# Block the close:
in Event::Window[type: :close_requested, window_id: "main"]
  model.with(show_save_dialog: true)
```

If `close_requested` is not handled (falls through to the catch-all), the
window stays open. This prevents accidental closes. To close a window
programmatically, remove it from the tree (return `view` without it) or
use `Command.close_window(id)`.

### Opening windows declaratively

Windows are opened by adding window nodes to the tree returned by
`view`. There is no `open_window` command. To open a new window, set a
flag in your model and include the window node conditionally:

```ruby
def update(model, event)
  case event
  in Event::Widget[type: :click, id: "open_settings"]
    model.with(settings_open: true)
  else
    model
  end
end

def view(model)
  windows = [
    window("main", title: "My App") do
      main_content(model)
    end
  ]

  if model.settings_open
    settings = window("settings", title: "Settings", size: [500, 400]) do
      settings_panel(model)
    end
    windows + [settings]
  else
    windows
  end
end
```

### Primary window

The first window in the list returned by `view` is the primary window.
When the primary window is closed, the runtime exits (unless
`handle_renderer_exit` is overridden to prevent it).

Secondary windows can be opened and closed freely without affecting the
runtime lifecycle.

### Focus and active window

The renderer tracks which window has OS focus. Window focus/unfocus events
are delivered as:

```ruby
Event::Window[type: :focused, window_id: window_id]
Event::Window[type: :unfocused, window_id: window_id]
```

The app can use these to adjust behaviour (e.g., pause animations in
unfocused windows, track the active window for keyboard shortcuts).

### Example: dialog window

```ruby
def view(model)
  main = window("main", title: "App") do
    main_content(model)
  end

  if model.confirm_dialog
    dialog = window("confirm", title: "Confirm",
             size: [300, 150], resizable: false,
             level: :always_on_top) do
      column(padding: 16, spacing: 12) do
        text("prompt", "Are you sure?")
        row(spacing: 8) do
          button("confirm_yes", "Yes")
          button("confirm_no", "No")
        end
      end
    end
    [main, dialog]
  else
    main
  end
end
```

## How props reach the renderer

Values returned by `view` go through several transformation stages
before reaching the wire. Understanding this pipeline helps when
debugging unexpected behaviour or writing custom extensions.

1. **Widget builders** (DSL block methods, `Plushie::Widget::*` modules)
   return `Node` objects with raw Ruby values -- symbols, arrays, hashes.
   No encoding happens here.

2. **`Plushie::Tree.normalize`** walks the tree and encodes each prop
   value via the `Plushie::Encode` module. Symbols become strings (except
   `true`/`false`/`nil`), arrays stay as arrays, and custom types encode
   via their `Encode` implementation. Scoped IDs are prefixed at this
   stage.

3. **Protocol encoding** stringifies symbol keys to string keys, then
   serializes with JSON or MessagePack to produce wire bytes.

Each stage has a single responsibility. Widget builders don't worry
about wire encoding, the Encode module doesn't worry about serialization
format, and the Protocol layer doesn't know about widget types.

See [running.md](running.md) for more detail on the encoding pipeline
and transport modes.

## Renderer limits

The renderer enforces hard limits on various resources. Exceeding them
results in rejection, truncation, or clamping (depending on the
resource). Design your app to stay within these bounds.

| Resource | Limit | Behavior when exceeded |
|---|---|---|
| Font data (`load_font`) | 16 MiB decoded | Rejected with warning |
| Runtime font loads | 256 per process | Rejected with warning |
| Image handles | 4096 | Error response |
| Total image bytes | 1 GiB | Error response |
| Markdown content | 1 MiB | Truncated at UTF-8 boundary with warning |
| Text editor content | 10 MiB | Truncated at UTF-8 boundary with warning |
| Window size | 1..16384 px | Clamped with warning |
| Window position | -32768..32768 | Clamped with warning |
| Tree depth | 256 levels | Rendering/caching stops descending |

Image and font limits are per-process and survive Reset. Content limits
truncate at a UTF-8 character boundary.
