# Testing

Plushie ships a test framework that drives your app against the real
renderer binary. Every test exercises the full wire protocol, widget
callbacks, and effect plumbing, so bugs that live at the SDK / renderer
boundary are caught the same way a user would hit them.

The framework lives in `Plushie::Test`, with a Minitest subclass
(`Plushie::Test::Case`), an RSpec module (`Plushie::Test::RSpec`), a
shared helper mixin (`Plushie::Test::Helpers`), the session pool
(`Plushie::Test::SessionPool`), snapshot helpers
(`Plushie::Test::Snapshot`), and a `.plushie` script runner
(`Plushie::Test::Script`).

## Setup

Load the framework from your test helper:

```ruby
# test/test_helper.rb
require "plushie"
require "plushie/test"
require "minitest/autorun"
```

The session pool is lazy: it boots a shared renderer process the first
time `Plushie::Test.pool` is called and tears it down via `at_exit`.
No explicit setup call is required.

## Minitest

`Plushie::Test::Case` subclasses `Minitest::Test`, includes
`Plushie::Test::Helpers`, and wires session setup and teardown into
`setup` / `teardown`. Declare the app with `app`:

```ruby
class CounterTest < Plushie::Test::Case
  app Counter

  def test_clicking_increment_updates_counter
    click("#increment")
    assert_text "#count", "Count: 1"
  end

  def test_double_increment
    2.times { click("#increment") }
    assert_text "#count", "Count: 2"
  end
end
```

Each test gets its own session. On teardown the case asserts no
renderer diagnostics are pending (validation warnings from
`Plushie.configuration.validate_props = true`) and releases the
session back to the pool.

## RSpec

`Plushie::Test::RSpec` mirrors the same lifecycle via `before(:each)` /
`after(:each)` hooks. Include it in your example group and declare the
app with `plushie_app`:

```ruby
RSpec.describe Counter do
  include Plushie::Test::RSpec
  plushie_app Counter

  it "increments" do
    click("#increment")
    expect(text(find!("#count"))).to eq("Count: 1")
  end
end
```

Nested contexts inherit the app declaration from the enclosing group.

### Manual session lifecycle

For cases where you cannot use either mixin (custom harness classes,
multiple apps in one example), `Plushie::Test::Helpers` exposes
`plushie_start(app_class)` and `plushie_stop` directly:

```ruby
include Plushie::Test::Helpers

before { plushie_start(Counter) }
after  { plushie_stop }
```

The session lives on `Thread.current[:_plushie_test_session]` so the
helper methods resolve it without ceremony.

## Backends

`Plushie::Test.backend` resolves the backend in this order:
`PLUSHIE_TEST_BACKEND` env var, then
`Plushie.configuration.test_backend`, then the default `:mock`.

| Backend | Process | Rendering | Screenshots | Effects |
|---|---|---|---|---|
| `:mock` | `plushie --mock --max-sessions N` | Protocol only | Hash only | Stubs only |
| `:headless` | `plushie --headless --max-sessions N` | Software | Pixel | Stubs only |
| `:windowed` | `plushie --max-sessions N` | Real iced windows | Pixel | Real |

```bash
bundle exec rake test                                  # :mock
PLUSHIE_TEST_BACKEND=headless bundle exec rake test
PLUSHIE_TEST_BACKEND=windowed bundle exec rake test
```

The mock backend is fast enough for TDD. The headless backend exercises
the real rendering pipeline over software (no display server required).
The windowed backend opens real windows; run it behind Xvfb or a
Wayland compositor on CI.

Tests are written once and run against all three backends without
changes. Features that depend on pixels (screenshots, actual event
injection by the compositor) are gated at the assertion level: for
example, `assert_screenshot` is a no-op on `:mock`.

## Interaction helpers

All interactions live on `Plushie::Test::Helpers` and route through
the current session. Each call blocks until the resulting events have
been fed through `update` and the next view has been rendered and
snapshotted.

| Method | Widget types | Event produced |
|---|---|---|
| `click(selector)` | button, any clickable | `:click` |
| `type_text(selector, text)` | text_input, text_editor | `:input` |
| `submit(selector)` | text_input | `:submit` |
| `toggle(selector)` | checkbox, toggler | `:toggle` |
| `select(selector, value)` | pick_list, combo_box, radio | `:select` |
| `slide(selector, value)` | slider, vertical_slider | `:slide` |
| `press(key)` | n/a | `Event::Key[type: :press]` |
| `release(key)` | n/a | `Event::Key[type: :release]` |
| `type_key(key)` | n/a | press + release |
| `move_to(x, y)` | n/a | pointer position |
| `click_element(canvas_id, element_id)` | canvas | `:click` scoped to an element |
| `focus_element(canvas_id, element_id)` | canvas | `Command.focus` to `"canvas/element"` |

`toggle` and `submit` read the current value from the local tree
before sending the interact message, so the event the renderer
produces carries the right state.

### Selectors

Selector strings follow a unified grammar:

| Form | Matches |
|---|---|
| `"#id"` or `"id"` | Widget ID. A bare string without `#` is treated as an ID. |
| `"#form/save"` | Scoped path (parent / child). |
| `"window#id"` | Widget in a specific window. |
| `"window#form/save"` | Scoped path in a specific window. |
| `":focused"` | Currently focused widget. |
| `"[text=Save]"` | Widget with matching text content. |
| `"[role=button]"` | Widget with accessibility role. |
| `"[label=Name]"` | Widget with accessibility label. |

The same grammar works for every selector argument: `click`,
`type_text`, `find`, `find!`, `assert_text`, `assert_exists`, and so
on. Id selectors are validated against the local tree before the
interact message is sent so missing widgets fail fast with a clear
error message and "did you mean" suggestions based on similar IDs.

### Key names

Key names are passed through to the renderer, which normalises case,
strips whitespace and separators, and recognises the usual aliases:

- Arrow keys: `"left"`, `"arrowleft"`, `"left_arrow"`
- `"enter"` / `"return"`, `"esc"` / `"escape"`
- `"bs"` / `"backspace"`, `"del"` / `"delete"`
- Single characters: `"s"`, `"a"`, `"1"` (case preserved)
- Function keys: `"F1"` through `"F12"`
- Modifier combos: `"ctrl+s"`, `"Shift+Left_Arrow"`, `"Alt+F4"`
- Modifier aliases: `ctrl`/`control`, `alt`/`option`/`opt`,
  `logo`/`super`/`win`/`meta`/`command`/`cmd`

## Queries

| Method | Returns |
|---|---|
| `find(selector)` | Element hash, or `nil` if not found |
| `find!(selector)` | Element hash, or raises `Plushie::Error` |
| `find_by_role(role)` | First widget whose accessibility role matches |
| `find_by_label(label)` | First widget whose accessibility label matches |
| `find_focused` | Currently focused widget |
| `text(element)` | Display text: `content`, `label`, `value`, or `placeholder` (whichever is present) |
| `model` | Current app model |
| `tree` | Current tree from the renderer |

`find!` includes the current tree IDs and up to three similar IDs in
its error message when a widget is missing, making the common
"selector typo" case quick to diagnose.

## Assertions

The assertion helpers raise through the host framework (Minitest
`Minitest::Assertion`, RSpec `ExpectationNotMetError`). Each wraps a
query and a comparison:

| Method | Description |
|---|---|
| `assert_text(selector, expected)` | Widget text equals `expected` |
| `assert_exists(selector)` | Widget is present in the tree |
| `assert_not_exists(selector)` | Widget is not in the tree |
| `assert_model(expected)` | Model equals `expected` |
| `assert_a11y(selector, expected)` | Every key in `expected` appears in the resolved a11y hash |
| `assert_no_diagnostics` | No prop validation warnings have been emitted |
| `assert_tree_hash(name)` | Structural tree hash matches the golden file |
| `assert_screenshot(name)` | Pixel hash matches the golden file |

```ruby
def test_autosave_banner_renders_after_input
  type_text("#editor", "hello")
  assert_exists "#autosave_banner"
  assert_text "#autosave_banner", "Saved"
  assert_a11y "#autosave_banner", role: "status", live: "polite"
end
```

`assert_no_diagnostics` is called automatically by
`Plushie::Test::Case` on teardown. Call it explicitly mid-test to
fence a block of assertions against renderer-side warnings.

`resolved_a11y(selector)` returns the resolved a11y hash for direct
inspection. It layers render-pipeline inference (placeholder becomes
description on text-entry widgets, alt becomes label on media widgets)
on top of the explicit `a11y` prop, so assertions reflect what
assistive technology actually sees.

## Effect stubs

Effect stubs are the only sanctioned mock mechanism. They register at
the renderer, not at the SDK, so the full encode / decode path is
still exercised. A stub registers by effect **kind** (not tag) and
applies to every effect of that kind until unregistered.

```ruby
def test_import_loads_selected_file
  register_effect_stub(:file_open, {path: "/tmp/notes.txt"})

  click("#import")

  assert_text "#status", "Imported /tmp/notes.txt"
end
```

| Method | Description |
|---|---|
| `register_effect_stub(kind, response)` | Install a canned response for a kind of effect |
| `unregister_effect_stub(kind)` | Remove a stub |

The `response` is encoded directly into the effect's wire result, so
it should match the shape the renderer would otherwise produce. For
file dialogs that is `{path:}` or `{paths:}`; for clipboard reads,
`{text:}`; for notifications, an acknowledgement hash.

To simulate a cancelled dialog, return `{cancelled: true}`.

## Frame advancement

Animation tests step the renderer's clock deterministically via
`advance_frame`:

```ruby
def test_fade_in_completes_after_one_second
  click("#reveal")

  advance_frame(0)
  advance_frame(500)    # halfway through the transition
  advance_frame(1_000)  # transition complete

  assert_a11y "#panel", hidden: false
end
```

| Method | Description |
|---|---|
| `advance_frame(timestamp)` | Send `Plushie::Command.advance_frame(timestamp)` to the renderer |
| `skip_transitions` | Advance to `10_000` ms, completing any in-flight transition |

Frame advancement drives renderer-side transitions and springs (see
the [Animation reference](animation.md)). SDK-side tweens driven by
`Plushie::Subscription.on_animation_frame` run synchronously in test
mode and don't need frame advancement.

## Snapshots

Golden-file snapshots live under `test/snapshots/` (tree hashes and
JSON trees) and `test/screenshots/` (pixel hashes). First run writes
the golden file; subsequent runs compare against it.

| Method | Source module | File |
|---|---|---|
| `tree_hash(name)` | `Plushie::Test::Helpers` | None; returns the hash to the caller |
| `assert_tree_hash(name)` | `Plushie::Test::Snapshot` | `test/snapshots/NAME.sha256` |
| `assert_tree_snapshot(tree, path)` | `Plushie::Test::Snapshot` | Caller-specified JSON file |
| `screenshot(name, width:, height:)` | `Plushie::Test::Helpers` | None; returns the response hash |
| `assert_screenshot(name)` | `Plushie::Test::Snapshot` | `test/screenshots/NAME.sha256` |
| `save_screenshot(name)` | `Plushie::Test::Helpers` | `test/screenshots/NAME.rgba` |

`assert_tree_snapshot` serialises the tree with `:meta` stripped so
internal SDK bookkeeping doesn't invalidate the golden. `strip_meta`
also handles `Plushie::Node` instances by converting them to their
wire form first.

`assert_screenshot` is a no-op on the `:mock` backend: pixels are
meaningless without rendering, and returning early keeps the same
test passing on every backend.

### Updating goldens

Set the matching environment variable to overwrite the golden file
instead of asserting:

```bash
PLUSHIE_UPDATE_SNAPSHOTS=1 bundle exec rake test     # tree hashes, JSON snapshots
PLUSHIE_UPDATE_SCREENSHOTS=1 bundle exec rake test   # pixel screenshot hashes
```

These are separate variables so a UI change that reshapes the tree
but not the pixels (or vice versa) can be reviewed independently.

## Session pool

The pool owns a single `plushie --mock --max-sessions N` (or
`--headless`, or windowed) process and multiplexes test sessions over
it via per-session IDs. Responses are demultiplexed by the `session`
field on the wire and dispatched to the owning session's queue.

| Option | Type | Default |
|---|---|---|
| `mode` | `:mock`, `:headless`, `:windowed` | `:mock` |
| `format` | `:msgpack`, `:json` | `:msgpack` |
| `max_sessions` | Integer | `8` |
| `binary` | String, nil | Auto-resolved via `Plushie::Binary.path!` |

Parallel tests are safe: each session has its own ID and isolated
state on the renderer side. When the pool is full,
`SessionPool#register` raises immediately so leaked sessions are
visible rather than causing test hangs.

On session unregister the pool sends a `reset` message to the
renderer and waits for `reset_response` and `session_closed`. This
clears per-session widget state between tests without the cost of a
fresh subprocess.

## .plushie scripts

`.plushie` is a declarative text format for recorded sessions. A
YAML-style header (`key value` per line) is separated from the
instruction list by a line of five or more dashes:

```
app Counter
viewport 800x600
theme dark
-----
click "#increment"
click "#increment"
assert_text "#count" "Count: 2"
tree_hash "counter-at-2"
```

### Header fields

| Key | Purpose |
|---|---|
| `app` | Required. Constant name of the `Plushie::App` class to run. |
| `viewport` | Window size hint (e.g. `800x600`). |
| `theme` | Theme name. |
| `backend` | `mock`, `headless`, or `windowed`. |

### Instructions

| Instruction | Description |
|---|---|
| `click SELECTOR` | Click a widget |
| `type SELECTOR TEXT` | Type text into a widget |
| `type_key KEY` | Press and release a key |
| `press KEY` | Key down |
| `release KEY` | Key up |
| `move X,Y` | Move the cursor |
| `expect TEXT` | Assert that `TEXT` appears anywhere in the tree |
| `assert_text SELECTOR TEXT` | Assert widget text equals `TEXT` |
| `assert_model EXPR` | Assert `model.to_s` equals `EXPR` |
| `tree_hash NAME` | Capture a structural tree hash |
| `screenshot NAME` | Capture a screenshot |
| `wait SECONDS` | Pause for the given number of seconds |

Strings are double-quoted; unquoted tokens run to the next
whitespace. Lines starting with `#` are comments.

### Running scripts

Two Rake tasks drive scripts from the command line:

```bash
bundle exec rake plushie:script                         # run every script under test/scripts/
bundle exec rake plushie:script[test/scripts/ui.plushie] # run a specific script
bundle exec rake plushie:replay[test/scripts/ui.plushie] # replay with real windows
```

`plushie:script` uses the currently selected backend (default
`:mock`). `plushie:replay` forces the `:windowed` backend with a
dedicated single-session pool so the script can be watched in real
time. See the [Rake tasks reference](rake-tasks.md).

## Gotchas

- **`width: :fill` on intermediate containers.** Iced containers
  shrink-wrap their children by default. If a row or column does not
  set `width: :fill`, a child widget's `width: :fill` has nothing to
  fill and collapses to zero. When a test fails with "widget not
  visible" or a surprising layout, check parent container widths
  first.
- **Event field access.** Event payloads live on the `value` field,
  never `data`. Scalar events (`:input`, `:slide`) carry the value
  directly; structured events (`:press`, `:key_press`) carry a
  symbol-keyed Hash. Manually constructed events hide protocol
  mismatches, so prefer driving behaviour through the helpers and
  letting the renderer synthesise events.
- **Native widgets need `new_instance`.** The session pool
  multiplexes sessions over one renderer process. Native widgets that
  don't implement `new_instance()` in their Rust impl cause the pool
  to hang on session reset. Add it to every `PlushieWidget` impl you
  ship.
- **Canvas element click uses a separate helper.** A canvas element
  is not a tree node; its ID lives inside the canvas's registry.
  `click_element(canvas_id, element_id)` (or `focus_element`)
  targets an element directly. `click("#canvas/element")` also works
  but resolves parent-first.

## See also

- [Commands reference](commands.md), effect stubs, async
  mechanics, and `advance_frame`
- [Events reference](events.md), the event classes the runtime
  delivers to `update` during tests
- [Configuration reference](configuration.md), `test_backend`,
  `PLUSHIE_TEST_BACKEND`, and binary resolution
- [Rake tasks reference](rake-tasks.md), `plushie:script`,
  `plushie:replay`, and the preflight task
