# Testing

## Philosophy

Progressive fidelity: test your app's logic with fast, pure-Ruby mock tests;
promote to headless or windowed backends when you need wire-protocol verification
or pixel-accurate screenshots.


## Unit testing

`update` is pure, `view` returns nodes. Plain Minitest -- no framework
needed.

### Testing update

```ruby
class MyAppTest < Minitest::Test
  def test_adding_a_todo_appends_and_clears_input
    model = Model.new(todos: [], input: "Buy milk")
    model = MyApp.new.update(model, Event::Widget.new(type: :click, id: "add_todo"))

    assert_equal "Buy milk", model.todos.first[:text]
    refute model.todos.first[:done]
    assert_equal "", model.input
  end
end
```

### Testing commands from update

Commands are plain `Command::Cmd` objects. Pattern-match on `type` and
`payload` to verify what `update` asked the runtime to do, without
executing anything.

```ruby
def test_submitting_todo_refocuses_the_input
  model = Model.new(todos: [], input: "Buy milk")
  model, cmd = MyApp.new.update(model, Event::Widget.new(type: :submit, id: "todo_input", value: "Buy milk"))

  assert_equal "Buy milk", model.todos.first[:text]
  assert_equal :focus, cmd.type
  assert_equal "todo_input", cmd.payload[:target]
end

def test_save_triggers_async_task
  model = Model.new(data: "unsaved")
  _model, cmd = MyApp.new.update(model, Event::Widget.new(type: :click, id: "save"))

  assert_equal :async, cmd.type
  assert_equal :save_result, cmd.payload[:tag]
end
```

### Testing view

```ruby
def test_view_shows_todo_count
  model = Model.new(todos: [{id: 1, text: "Buy milk", done: false}], input: "")
  tree = Plushie::Tree.normalize(MyApp.new.view(model))

  counter = Plushie::Tree.find(tree, "todo_count")
  refute_nil counter
  assert_includes counter.props[:content], "1"
end
```

### Testing init

```ruby
def test_init_returns_valid_initial_state
  model = MyApp.new.init({})

  assert_kind_of Array, model.todos
  assert_equal "", model.input
end
```

### Tree query helpers

`Plushie::Tree` provides helpers for querying view trees directly:

```ruby
Plushie::Tree.find(tree, "my_button")            # find node by ID
Plushie::Tree.exists?(tree, "my_button")         # check existence
Plushie::Tree.ids(tree)                           # all IDs (depth-first)
Plushie::Tree.find_all(tree) { |node| node.type == "button" }  # find by predicate
```

These work on the raw node maps returned by `view`. No test session or
backend required.

### JSON tree snapshots

For complex views, snapshot the entire tree as JSON to catch unintended
structural changes:

```ruby
def test_initial_view_snapshot
  model = MyApp.new.init({})
  tree = MyApp.new.view(model)

  Plushie::Test.assert_tree_snapshot(tree, "test/snapshots/initial_view.json")
end
```

First run writes the file. Subsequent runs compare and fail with a diff on
mismatch. Update after intentional changes:

```sh
PLUSHIE_UPDATE_SNAPSHOTS=1 bundle exec rake test
```

This is a pure JSON comparison -- it normalizes key ordering for stable
output. It is distinct from the framework's `assert_tree_hash` (which uses
SHA-256 hashes of the tree via a backend session) and `assert_screenshot`
(which compares pixel data).


## The test framework

Unit tests cover logic. But they cannot click a button, verify a widget
appears after an interaction, or catch a rendering regression when you bump
iced. That is what the test framework is for.

### Minitest

```ruby
class CounterTest < Plushie::Test::Case
  self.app = Counter

  def test_clicking_increment_updates_counter
    click("#increment")
    assert_text "#count", "1"
  end
end
```

### RSpec

```ruby
RSpec.describe Counter do
  include Plushie::Test::RSpec

  let(:app) { Counter }

  it "increments on click" do
    click("#increment")
    assert_text "#count", "1"
  end
end
```

`Plushie::Test::Case` (and the RSpec helper) starts a session, imports all
helper methods, and tears down on exit. The default backend is `:mock` --
the plushie binary in `--mock` mode (lightweight rendering, no display).
Sessions are pooled for performance.


## Selectors, interactions, and assertions

### Where do widget IDs come from?

Every widget in plushie gets an ID from the first argument to its builder.
For example, `button("save_btn", "Save")` creates a button with ID
`"save_btn"`.

When using selectors in tests, prefix the ID with `#`:

```ruby
click("#save_btn")
find!("#save_btn")
assert_text "#save_btn", "Save"
```

### Selectors

Two selector forms:

- **`"#id"`** -- find by widget ID. The `#` prefix is required.
- **`"text content"`** -- find by text content (checks `content`, `label`,
  `value`, `placeholder` props in that order, depth-first).

```ruby
click("#my_button")         # by ID
find!("Click me")           # by text content
assert_exists "#sidebar"    # by ID
```

### Element handles

`find` returns `nil` if not found. `find!` raises with a clear message.
Both return an `Element`:

```ruby
element = find!("#my-button")
element.id       # => "my-button"
element.type     # => "button"
element.props    # => {"label" => "Click me", ...}
element.children # => [...]
```

The `Element` struct has four fields:

| Field | Type | Description |
|---|---|---|
| `id` | `String` | The widget's ID |
| `type` | `String` | Widget type name (e.g. "button", "text", "container") |
| `props` | `Hash` | Widget properties (label, content, value, etc.) |
| `children` | `Array` | Nested child elements |

Use `text(element)` to extract display text from an element:

```ruby
assert_equal "42", text(find!("#count"))
```

`text` checks props in order: `content`, `label`, `value`, `placeholder`.
Returns `nil` if no text prop is found.

### Interaction functions

All interaction methods accept a selector string. They are available
automatically in `Plushie::Test::Case`.

| Method | Widget types | Event produced |
|---|---|---|
| `click(selector)` | `button` | `Event::Widget[type: :click]` |
| `type_text(selector, text)` | `text_input`, `text_editor` | `Event::Widget[type: :input]` |
| `submit(selector)` | `text_input` | `Event::Widget[type: :submit]` |
| `toggle(selector)` | `checkbox`, `toggler` | `Event::Widget[type: :toggle]` |
| `select(selector, value)` | `pick_list`, `combo_box`, `radio` | `Event::Widget[type: :select]` |
| `slide(selector, value)` | `slider`, `vertical_slider` | `Event::Widget[type: :slide]` |

Interacting with the wrong widget type raises with an actionable hint:

```
cannot click a checkbox widget -- use toggle instead
```

### Assertions

```ruby
# Text content
assert_text "#count", "42"

# Existence
assert_exists "#my-button"
assert_not_exists "#admin-panel"

# Full model equality
assert_model({count: 5, name: "test"})

# Direct model inspection
assert_equal 5, model.count

# Direct element access when you need more control
element = find!("#count")
assert_equal "42", text(element)
assert_equal "text", element.type
```


## API reference

All of the following are available in `Plushie::Test::Case`:

| Method | Description |
|---|---|
| `find(selector)` | Find element by selector, returns `nil` if not found |
| `find!(selector)` | Find element by selector, raises if not found |
| `click(selector)` | Click a button widget |
| `type_text(selector, text)` | Type text into a text_input or text_editor |
| `submit(selector)` | Submit a text_input (simulates pressing enter) |
| `toggle(selector)` | Toggle a checkbox or toggler |
| `select(selector, value)` | Select a value from pick_list, combo_box, or radio |
| `slide(selector, value)` | Slide a slider to a numeric value |
| `model` | Returns the current app model |
| `tree` | Returns the current normalized UI tree |
| `text(element)` | Extract text content from an Element |
| `tree_hash(name)` | Capture a structural tree hash |
| `screenshot(name)` | Capture a pixel screenshot (no-op on mock) |
| `save_screenshot(name)` | Capture screenshot and save as PNG to `test/screenshots/` |
| `assert_text(selector, expected)` | Assert widget contains expected text |
| `assert_exists(selector)` | Assert widget exists in the tree |
| `assert_not_exists(selector)` | Assert widget does NOT exist in the tree |
| `assert_model(expected)` | Assert model equals expected (strict equality) |
| `assert_tree_hash(name)` | Capture tree hash and assert it matches golden file |
| `assert_screenshot(name)` | Capture screenshot and assert it matches golden file |
| `await_async(tag, timeout: 5000)` | Wait for a tagged async task to complete |
| `press(key)` | Press a key (key down). Supports modifiers: `"ctrl+s"` |
| `release(key)` | Release a key (key up). Supports modifiers: `"ctrl+s"` |
| `move_to(x, y)` | Move the cursor to absolute coordinates |
| `type_key(key)` | Type a key (press + release). Supports modifiers: `"enter"` |
| `reset` | Reset session to initial state |
| `start(app, opts)` | Start a session manually (when not using Case) |
| `session` | Returns the current test session |


## Backends

All tests work on all backends. Write tests once, swap backends without
changing assertions.

### Three backends

| | `:mock` | `:headless` | `:windowed` |
|---|---|---|---|
| **Speed** | ~ms | ~100ms | ~seconds |
| **Renderer** | Yes (`--mock`) | Yes (`--headless`) | Yes |
| **Display server** | No | No | Yes (Xvfb in CI) |
| **Protocol round-trip** | Yes | Yes | Yes |
| **Structural tree hashes** | Yes | Yes | Yes |
| **Pixel screenshots** | No | Yes (software) | Yes |
| **Effects** | Cancelled | Cancelled | Executed |
| **Subscriptions** | Tracked, not fired | Tracked, not fired | Active |
| **Real rendering** | No | Yes (tiny-skia) | Yes (GPU) |
| **Real windows** | No | No | Yes |

- **`:mock`** -- shared `plushie --mock` process with session
  multiplexing. Tests app logic, tree structure, and wire protocol.
  No rendering, no display, sub-millisecond. The right default for
  90% of tests.

- **`:headless`** -- `plushie --headless` with software rendering via
  tiny-skia (no display server). Pixel screenshots for visual
  regression. Catches rendering bugs that mock mode can't.

- **`:windowed`** -- `plushie` with real iced windows and GPU rendering.
  Effects execute, subscriptions fire, screenshots capture exactly
  what a user sees. Needs a display server (Xvfb or headless Weston).

### Backend selection

You never choose a backend in your test code. Backend selection is an
infrastructure decision made via environment variable or application config.
Tests are portable across all three.

| Priority | Source | Example |
|---|---|---|
| 1 | Environment variable | `PLUSHIE_TEST_BACKEND=headless bundle exec rake test` |
| 2 | Application config | `Plushie.configure { |c| c.test_backend = :mock }` |
| 3 | Default | `:mock` |


## Snapshots and screenshots

Plushie has three distinct regression testing mechanisms. Understanding the
difference is important.

### Structural tree hashes (`assert_tree_hash`)

`assert_tree_hash` captures a SHA-256 hash of the serialized UI tree and
compares it against a golden file. It works on all three backends because
every backend can produce a tree.

```ruby
def test_counter_initial_state
  assert_tree_hash("counter-initial")
end

def test_counter_after_increment
  click("#increment")
  assert_tree_hash("counter-at-1")
end
```

Golden files are stored in `test/snapshots/` as `.sha256` files. On first
run, the golden file is created automatically. On subsequent runs, the hash
is compared and the test fails on mismatch.

To update golden files after intentional changes:

```sh
PLUSHIE_UPDATE_SNAPSHOTS=1 bundle exec rake test
```

### Pixel screenshots (`assert_screenshot`)

`assert_screenshot` captures real RGBA pixel data and compares it against
a golden file. It produces meaningful data on both the `:windowed` backend (GPU
rendering via wgpu) and the `:headless` backend (software rendering via
tiny-skia). On `:mock`, it silently succeeds as a no-op (returns an
empty hash, which is accepted without creating or checking a golden file).

Note that headless screenshots use software rendering, so pixels will not
match GPU output exactly. Maintain separate golden files per backend, or
use headless screenshots for layout regression testing only.

```ruby
def test_counter_renders_correctly
  click("#increment")
  assert_screenshot("counter-at-1")
end
```

Golden files are stored in `test/screenshots/` as `.sha256` files. The
workflow is the same as structural snapshots but uses a separate env var:

```sh
PLUSHIE_UPDATE_SCREENSHOTS=1 bundle exec rake test
```

Because screenshots silently no-op on mock, you can include
`assert_screenshot` calls in any test without conditional logic. They will
produce assertions when run on the headless or windowed backends.

### JSON tree snapshots (`assert_tree_snapshot`)

`Plushie::Test.assert_tree_snapshot` is a unit-test-level tool that compares
a raw tree hash against a stored JSON file. No backend or session needed.
See the [Unit testing](#json-tree-snapshots) section above.

### When to use each

- **`assert_tree_hash`** -- always appropriate. Catches structural regressions
  (widgets appearing/disappearing, prop changes, nesting changes). Works on
  every backend. Use liberally.

- **`assert_screenshot`** -- after bumping iced, changing the renderer,
  modifying themes, or any change that affects visual output. Only meaningful
  on headless and windowed backends. Include alongside `assert_tree_hash` for
  critical views.

- **`assert_tree_snapshot`** -- for unit tests of `view` output. No
  framework overhead. Good for documenting what a view produces for a given
  model state.


## Script-based testing

`.plushie` scripts provide a declarative format for describing interaction
sequences. The format is a superset of iced's `.ice` test scripts -- the
core instructions (`click`, `type`, `expect`, `snapshot`) use the same
syntax. Plushie adds `assert_text`, `assert_model`, `screenshot`, `wait`, and
a header section for app configuration.

### The `.plushie` format

A `.plushie` file has a header and an instruction section separated by
`-----`:

```
app: Counter
viewport: 800x600
theme: dark
backend: mock
-----
click "#increment"
click "#increment"
expect "Count: 2"
tree_hash "counter-at-2"
screenshot "counter-pixels"
assert_text "#count" "2"
wait 500
```

#### Header fields

| Field | Required | Default | Description |
|---|---|---|---|
| `app` | Yes | -- | Class implementing the Plushie app |
| `viewport` | No | `800x600` | Viewport size as `WxH` |
| `theme` | No | `dark` | Theme name |
| `backend` | No | `mock` | Backend: `mock`, `headless`, or `windowed` |

Lines starting with `#` are comments (in both header and body sections).

#### Instructions

| Instruction | Syntax | Mock support | Description |
|---|---|---|---|
| `click` | `click "selector"` | Yes | Click a widget |
| `type` | `type "selector" "text"` | Yes | Type text into a widget |
| `type` (key) | `type enter` | Yes | Send a special key (press + release). Supports modifiers: `type ctrl+s` |
| `expect` | `expect "text"` | Yes | Assert text appears somewhere in the tree |
| `tree_hash` | `tree_hash "name"` | Yes | Capture and assert a structural tree hash |
| `screenshot` | `screenshot "name"` | No-op on mock | Capture and assert a pixel screenshot |
| `assert_text` | `assert_text "selector" "text"` | Yes | Assert widget has specific text |
| `assert_model` | `assert_model "expression"` | Yes | Assert expression appears in inspected model (substring match) |
| `press` | `press key` | Yes | Press a key down. Supports modifiers: `press ctrl+s` |
| `release` | `release key` | Yes | Release a key. Supports modifiers: `release ctrl+s` |
| `move` | `move "selector"` | No-op | Move mouse to a widget (requires widget bounds) |
| `move` (coords) | `move "x,y"` | Yes | Move mouse to pixel coordinates |
| `wait` | `wait 500` | Ignored (except replay) | Pause N milliseconds |

### Running scripts

```sh
bundle exec rake plushie:script
bundle exec rake plushie:script[test/scripts/counter.plushie]
```

### Replaying scripts

```sh
bundle exec rake plushie:replay[test/scripts/counter.plushie]
```

Replay mode forces the `:windowed` backend and respects `wait` timings, so you
see interactions happen in real time with real windows. Useful for debugging
visual issues, demos, and onboarding.


## Testing async workflows

### On the mock backend

The mock backend executes `async`, `stream`, and `done` commands
synchronously. When `update` returns a command like
`Command.async(-> { fetch_data }, :data_loaded)`, the backend
immediately calls the callable, gets the result, and dispatches
`Event::Async[tag: :data_loaded, result: [:ok, result]]` through
`update` -- all within the same call.

This means `await_async` returns immediately (the work is already
done):

```ruby
def test_fetching_data_loads_results
  click("#fetch")
  # On mock, the async command already executed synchronously.
  # await_async is a no-op -- the model is already updated.
  await_async(:data_loaded)
  assert model.results.length > 0
end
```

Widget ops (focus, scroll), window ops, and timers are silently skipped on
mock because they require a renderer. Test the command shape at the
unit test level instead:

```ruby
def test_clicking_fetch_starts_async_load
  app = MyApp.new
  model, cmd = app.update(Model.new(loading: false, data: nil), Event::Widget.new(type: :click, id: "fetch"))

  assert model.loading
  assert_equal :async, cmd.type
  assert_equal :data_loaded, cmd.payload[:tag]
end
```

### On headless and windowed backends

All three backends now use the shared `CommandProcessor` to execute async
commands synchronously. `await_async` returns immediately on all backends
because the commands have already completed.


## Debugging and error messages

### Element not found

```ruby
find!("#nonexistent")
# RuntimeError: Element not found: "#nonexistent"
```

Use `tree` to inspect the current tree and verify the widget's ID or text
content:

```ruby
pp tree  # print current tree structure
```

### Wrong interaction type

```ruby
click("#my-checkbox")
# RuntimeError: cannot click a checkbox widget -- use toggle instead
```

Use the correct interaction method for the widget type. Reference table:

| Widget type | Correct method |
|---|---|
| `button` | `click` |
| `text_input`, `text_editor` | `type_text` |
| `text_input` | `submit` |
| `checkbox`, `toggler` | `toggle` |
| `pick_list`, `combo_box`, `radio` | `select` |
| `slider`, `vertical_slider` | `slide` |

### Headless binary not built

```
RuntimeError: renderer exited with status 1
```

Build the renderer with the headless feature:

```sh
bundle exec rake plushie:build
```

### Inspecting state when a test fails

`model` and `tree` are your best debugging tools:

```ruby
def test_debugging_a_failing_test
  click("#increment")

  pp model  # inspect model after click
  pp tree   # inspect tree after click

  assert_equal "1", text(find!("#count"))
end
```


## Wire format in test backends

The headless and windowed backends communicate with the renderer using the same
wire protocol as the production Bridge. By default, both use MessagePack
(`{packet: 4}` framing). JSON is available for debugging:

```ruby
# In application config
Plushie.configure do |c|
  c.test_format = :json
end
```

Or pass `format: :json` in backend opts when starting a session manually:

```ruby
session = Plushie::Test::Session.start(MyApp, backend: Plushie::Test::Backend::Headless, format: :json)
```

The mock backend does not use a wire protocol (pure Ruby, no renderer
process), so the format option has no effect on it.


## CI configuration

### Mock CI (simplest)

No special setup. Works anywhere Ruby runs.

```yaml
- run: bundle exec rake test
```

### Headless CI

Requires the plushie binary (download or build from source).

```yaml
- run: bundle exec rake plushie:download
- run: PLUSHIE_TEST_BACKEND=headless bundle exec rake test
```

### Windowed CI

Requires a display server and GPU/software rendering. Two options:

**Option A: Xvfb (X11)**

```yaml
- run: bundle exec rake plushie:download
- run: sudo apt-get install -y xvfb mesa-vulkan-drivers
- run: |
    Xvfb :99 -screen 0 1024x768x24 &
    export DISPLAY=:99
    export WINIT_UNIX_BACKEND=x11
    PLUSHIE_TEST_BACKEND=windowed bundle exec rake test
```

**Option B: Weston (Wayland)**

Weston's headless backend provides a Wayland compositor without a physical
display. Combined with `vulkan-swrast` (Mesa software rasterizer), this
runs the full rendering pipeline on CPU.

```yaml
- run: bundle exec rake plushie:download
- run: sudo apt-get install -y weston mesa-vulkan-drivers
- run: |
    export XDG_RUNTIME_DIR=/tmp/plushie-xdg-runtime
    mkdir -p "$XDG_RUNTIME_DIR" && chmod 0700 "$XDG_RUNTIME_DIR"
    weston --backend=headless --width=1024 --height=768 --socket=plushie-test &
    sleep 1
    export WAYLAND_DISPLAY=plushie-test
    PLUSHIE_TEST_BACKEND=windowed bundle exec rake test
```

On Arch Linux, `weston` and `vulkan-swrast` are available via pacman.

### Progressive CI

Run mock tests fast, then promote to higher-fidelity backends for subsets:

```yaml
# All tests on mock (fast, catches logic bugs)
- run: bundle exec rake test

# Full suite on headless for protocol verification
- run: PLUSHIE_TEST_BACKEND=headless bundle exec rake test

# Windowed for pixel regression (tagged subset)
- run: |
    Xvfb :99 -screen 0 1024x768x24 &
    export DISPLAY=:99
    PLUSHIE_TEST_BACKEND=windowed bundle exec rake test TEST_OPTS="--tag windowed"
```

Tag tests that need a specific backend:

```ruby
# Minitest
class PixelTest < Plushie::Test::Case
  self.app = MyApp
  self.tags = [:windowed]

  def test_window_opens_and_renders
    # ...
  end
end
```


## Testing extensions

Extension widgets have two testing layers: Ruby-side logic (struct
building, command generation, demo app behavior) and Rust-side
rendering (the widget actually renders, handles events, etc.).

### Ruby-side: unit tests (no renderer)

Extension macros generate structs, setters, and protocol implementations.
Test these directly:

```ruby
class MyGaugeTest < Minitest::Test
  def test_new_creates_struct_with_defaults
    gauge = MyGauge.new("g1", value: 50)
    assert_equal "g1", gauge.id
    assert_equal 50, gauge.value
  end

  def test_build_produces_correct_node
    node = MyGauge.new("g1", value: 75).build
    assert_equal "gauge", node.type
    assert_equal 75, node.props[:value]
  end

  def test_push_command
    cmd = MyGauge.push("g1", 42.0)
    assert_equal :extension_command, cmd.type
  end
end
```

Demo apps test the extension in context:

```ruby
class MyGaugeDemoTest < Minitest::Test
  def test_view_produces_a_gauge_widget
    model = MyGauge::Demo.new.init({})
    tree = Plushie::Tree.normalize(MyGauge::Demo.new.view(model))
    gauge = Plushie::Tree.find(tree, "my-gauge")
    assert_equal "gauge", gauge.type
  end
end
```

### Rust-side: unit tests (no Ruby)

The `plushie_core::testing` module provides `TestEnv` and node factories
for testing `WidgetExtension::render()` in isolation:

```rust
use plushie_core::testing::*;
use plushie_core::prelude::*;

#[test]
fn gauge_renders_without_panic() {
    let ext = MyGaugeExtension::new();
    let test = TestEnv::default();
    let node = node_with_props("g1", "gauge", json!({"value": 75}));
    let env = test.env();
    let _element = ext.render(&node, &env);
}
```

### End-to-end: through the renderer

To verify extension widgets survive the wire protocol round-trip and
render correctly, build a custom renderer binary that includes the
extension's Rust crate:

```sh
# Build the custom renderer with your extension compiled in
bundle exec rake plushie:build

# Run tests through the real renderer (headless, no display server)
PLUSHIE_TEST_BACKEND=headless bundle exec rake test
```

Write end-to-end tests with `Plushie::Test::Case`:

```ruby
class MyGaugeEndToEndTest < Plushie::Test::Case
  self.app = MyGauge::Demo

  def test_gauge_appears_in_rendered_tree
    assert_exists "#my-gauge"
  end

  def test_gauge_responds_to_push_command
    click("#push-value")
    assert_text "#value-display", "42"
  end
end
```

These tests run on `:mock` by default (fast, logic-only). Set
`PLUSHIE_TEST_BACKEND=headless` to exercise the full Rust rendering path
with the extension compiled in.


## Known limitations

Workarounds and details for each limitation are noted inline below.

- Script instruction `move` (move cursor to a widget by selector) is a
  no-op. It requires widget bounds from layout, which only the renderer knows.
- `move_to` on the mock backend dispatches `Event::Mouse[type: :moved, x: x, y: y]`
  but has no spatial layout info. Mouse area enter/exit events won't fire.
- Pixel screenshots are only available on the headless and windowed backends
  (mock returns stubs).
- Headless screenshots use software rendering (tiny-skia) and may not match
  GPU output pixel-for-pixel.
- Script `assert_model` uses substring matching against the inspected model.
  Use specific substrings (`"count: 5"`) or use Minitest assertions for
  precise model checks.
- The `CommandProcessor` executes async/stream/batch commands synchronously
  in all test backends. Timing and concurrency bugs will not surface in mock
  tests. Use headless or windowed backends for concurrency-sensitive tests.
- Headless and windowed backends spawn a renderer via a subprocess. The
  teardown cleanup handles normal shutdown; if a test crashes without
  triggering it, Ruby's process exit propagation kills the child process.
