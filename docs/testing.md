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
helper methods, and tears down on exit. The default backend is `:mock`.
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
- **`"text content"`** -- find by text content.

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

Use `text(element)` to extract display text.

### Interaction functions

| Method | Widget types | Event produced |
|---|---|---|
| `click(selector)` | `button` | `Event::Widget[type: :click]` |
| `type_text(selector, text)` | `text_input`, `text_editor` | `Event::Widget[type: :input]` |
| `submit(selector)` | `text_input` | `Event::Widget[type: :submit]` |
| `toggle(selector)` | `checkbox`, `toggler` | `Event::Widget[type: :toggle]` |
| `select(selector, value)` | `pick_list`, `combo_box`, `radio` | `Event::Widget[type: :select]` |
| `slide(selector, value)` | `slider`, `vertical_slider` | `Event::Widget[type: :slide]` |

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

# Direct element access
element = find!("#count")
assert_equal "42", text(element)
```

## API reference

All of the following are available in `Plushie::Test::Case`:

| Method | Description |
|---|---|
| `find(selector)` | Find element, returns `nil` if not found |
| `find!(selector)` | Find element, raises if not found |
| `click(selector)` | Click a button widget |
| `type_text(selector, text)` | Type text into a text_input or text_editor |
| `submit(selector)` | Submit a text_input |
| `toggle(selector)` | Toggle a checkbox or toggler |
| `select(selector, value)` | Select a value from pick_list/combo_box/radio |
| `slide(selector, value)` | Slide a slider to a numeric value |
| `model` | Returns the current app model |
| `tree` | Returns the current normalized UI tree |
| `text(element)` | Extract text content from an Element |
| `tree_hash(name)` | Capture a structural tree hash |
| `screenshot(name)` | Capture a pixel screenshot (no-op on mock) |
| `save_screenshot(name)` | Capture screenshot and save as PNG |
| `assert_text(selector, expected)` | Assert widget contains expected text |
| `assert_exists(selector)` | Assert widget exists in the tree |
| `assert_not_exists(selector)` | Assert widget does NOT exist |
| `assert_model(expected)` | Assert model equals expected |
| `assert_tree_hash(name)` | Assert tree hash matches golden file |
| `assert_screenshot(name)` | Assert screenshot matches golden file |
| `await_async(tag, timeout: 5000)` | Wait for a tagged async task |
| `press(key)` | Press a key. Supports modifiers: `"ctrl+s"` |
| `release(key)` | Release a key |
| `move_to(x, y)` | Move cursor to absolute coordinates |
| `type_key(key)` | Type a key (press + release) |
| `reset` | Reset session to initial state |
| `start(app, opts)` | Start a session manually |
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
| **Real rendering** | No | Yes (tiny-skia) | Yes (GPU) |

### Backend selection

| Priority | Source | Example |
|---|---|---|
| 1 | Environment variable | `PLUSHIE_TEST_BACKEND=headless bundle exec rake test` |
| 2 | Application config | `Plushie.configure { |c| c.test_backend = :mock }` |
| 3 | Default | `:mock` |

## Snapshots and screenshots

### Structural tree hashes (`assert_tree_hash`)

```ruby
def test_counter_initial_state
  assert_tree_hash("counter-initial")
end

def test_counter_after_increment
  click("#increment")
  assert_tree_hash("counter-at-1")
end
```

Golden files are stored in `test/snapshots/` as `.sha256` files. Update:

```sh
PLUSHIE_UPDATE_SNAPSHOTS=1 bundle exec rake test
```

### Pixel screenshots (`assert_screenshot`)

```ruby
def test_counter_renders_correctly
  click("#increment")
  assert_screenshot("counter-at-1")
end
```

Update:

```sh
PLUSHIE_UPDATE_SCREENSHOTS=1 bundle exec rake test
```

## Script-based testing

`.plushie` scripts provide a declarative format for describing interaction
sequences.

### The `.plushie` format

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

### Running scripts

```sh
bundle exec rake plushie:script
bundle exec rake plushie:script[test/scripts/counter.plushie]
```

### Replaying scripts

```sh
bundle exec rake plushie:replay[test/scripts/counter.plushie]
```

Replay mode forces the `:windowed` backend and respects `wait` timings.

## CI configuration

### Mock CI (simplest)

```yaml
- run: bundle exec rake test
```

### Headless CI

```yaml
- run: bundle exec rake plushie:download
- run: PLUSHIE_TEST_BACKEND=headless bundle exec rake test
```

### Windowed CI

```yaml
- run: bundle exec rake plushie:download
- run: sudo apt-get install -y xvfb mesa-vulkan-drivers
- run: |
    Xvfb :99 -screen 0 1024x768x24 &
    export DISPLAY=:99
    export WINIT_UNIX_BACKEND=x11
    PLUSHIE_TEST_BACKEND=windowed bundle exec rake test
```

### Progressive CI

```yaml
# All tests on mock (fast)
- run: bundle exec rake test

# Full suite on headless
- run: PLUSHIE_TEST_BACKEND=headless bundle exec rake test

# Windowed for pixel regression (tagged subset)
- run: |
    Xvfb :99 -screen 0 1024x768x24 &
    export DISPLAY=:99
    PLUSHIE_TEST_BACKEND=windowed bundle exec rake test TEST_OPTS="--tag windowed"
```

## Testing extensions

Extension widgets have two testing layers: Ruby-side logic and Rust-side
rendering.

### Ruby-side: unit tests

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
end
```

### End-to-end: through the renderer

```sh
bundle exec rake plushie:build
PLUSHIE_TEST_BACKEND=headless bundle exec rake test
```

## Known limitations

- Script instruction `move` (move cursor to a widget by selector) is a
  no-op. It requires widget bounds from layout.
- Pixel screenshots are only available on headless and windowed backends.
- Headless screenshots use software rendering and may not match GPU output.
- The mock backend executes async commands synchronously. Timing and
  concurrency bugs will not surface in mock tests.
