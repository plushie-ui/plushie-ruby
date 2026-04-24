# Testing

Plushie tests exercise the real renderer binary. Every test starts
a real app session, connects it to the renderer through the same
wire protocol a user session uses, and drives interactions through
the pool. That catches the bugs that hide at the seam between the
SDK and the renderer: wire format drift, startup handshake
ordering, codec issues, widget callback plumbing.

This chapter covers the testing framework and applies it to the
pad. By the end, the pad has a Minitest suite covering its layout,
keyboard shortcuts, compile cycle, and auto-save timer, plus a
handful of effect-stubbed import tests.

## Setup

Load the framework from your test helper:

```ruby
# test/test_helper.rb
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "minitest/autorun"
require "plushie"
require "plushie/test"
require "plushie_pad"
```

The framework boots a shared renderer process lazily the first
time a test asks for a session. Teardown is registered via
`at_exit`, so no explicit setup call is required.

Tests run against the mock backend by default. Mock launches the
real renderer with `--mock`: real wire codecs, real handshake
ordering, no GPU rendering. That keeps the inner-loop fast without
sacrificing the wire-level coverage that makes these tests worth
writing.

The renderer binary must exist before tests run. Download a
precompiled artifact or build from source:

```bash
rake plushie:download          # precompiled
rake plushie:build             # from a plushie-rust checkout
```

If neither has run, the first test fails with a clear message
pointing at these rake tasks.

## Minitest

`Plushie::Test::Case` subclasses `Minitest::Test`, mixes in
`Plushie::Test::Helpers`, and owns session setup and teardown.
Declare the app class with `app`:

```ruby
require_relative "test_helper"

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

Each test gets its own session. The case calls
`assert_no_diagnostics` on teardown, so any prop validation warning
fires a test failure at the site that caused it.

## RSpec

`Plushie::Test::RSpec` mirrors the same lifecycle via
`before(:each)` and `after(:each)` hooks. Include it in your
example group and declare the app with `plushie_app`:

```ruby
RSpec.describe Counter do
  include Plushie::Test::RSpec
  plushie_app Counter

  it "increments" do
    click("#increment")
    expect(text(find!("#count"))).to eq("Count: 1")
  end

  context "after three clicks" do
    it "shows 3" do
      3.times { click("#increment") }
      expect(text(find!("#count"))).to eq("Count: 3")
    end
  end
end
```

Nested contexts inherit the app declaration from the enclosing
group. The RSpec integration carries the same helpers the Minitest
case does, so you can port tests back and forth without rewriting
bodies.

### Manual session lifecycle

When you cannot use either mixin (custom harness classes, multiple
apps in one example), `Plushie::Test::Helpers` exposes
`plushie_start(app_class)` and `plushie_stop` directly:

```ruby
class CustomHarnessTest < Minitest::Test
  include Plushie::Test::Helpers

  def setup
    plushie_start(Counter)
  end

  def teardown
    plushie_stop
  end
end
```

The session lives on `Thread.current[:_plushie_test_session]`, so
helper methods resolve it without extra wiring.

## Backends

Tests are backend-agnostic. The same test code runs against all
three backends:

| Backend | Process | Rendering | Screenshots | Effects |
|---|---|---|---|---|
| `:mock` | `plushie --mock` | Protocol only | Hash only | Stubs only |
| `:headless` | `plushie --headless` | Software | Pixel | Stubs only |
| `:windowed` | `plushie` | Real iced windows | Pixel | Real |

Select the backend with the `PLUSHIE_TEST_BACKEND` environment
variable:

```bash
bundle exec rake test                                  # :mock
PLUSHIE_TEST_BACKEND=headless bundle exec rake test
PLUSHIE_TEST_BACKEND=windowed bundle exec rake test
```

Mock is the fastest and the default. Headless exercises the real
rendering pipeline over a software rasterizer (no display server
required). Windowed opens real windows; run it behind Xvfb or a
Wayland compositor on CI.

Assertions that depend on pixels (`assert_screenshot`) are no-ops
on the mock backend, so the same test passes everywhere.

## Interactions

All interactions live on `Plushie::Test::Helpers` and route
through the current session. Each call blocks until the resulting
events have been fed through `update` and the next view has been
rendered and snapshotted.

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
| `click_element(canvas_id, element_id)` | canvas | scoped `:click` |
| `focus_element(canvas_id, element_id)` | canvas | `Command.focus` |

Interactions are synchronous. `click("#save")` returns only after
the click has been sent, `update` has processed the event, the new
view has been rendered, and any commands returned from `update`
have been dispatched. The next line of the test sees the settled
state.

### Selectors

Selector strings follow a unified grammar:

| Form | Matches |
|---|---|
| `"#id"` or `"id"` | Widget ID. Bare strings without `#` are also IDs. |
| `"#form/save"` | Scoped path (parent / child). |
| `"window#id"` | Widget in a specific window. |
| `"window#form/save"` | Scoped path in a specific window. |
| `":focused"` | Currently focused widget. |
| `"[text=Save]"` | Widget whose display text matches. |
| `"[role=button]"` | Widget with the given accessibility role. |
| `"[label=Name]"` | Widget with the given accessibility label. |

The same grammar works for every selector argument: `click`,
`type_text`, `find`, `find!`, `assert_text`, `assert_exists`, and
the rest. ID selectors are validated against the local tree before
the interact message is sent, so a missing widget fails fast with
a clear error and "did you mean" suggestions drawn from similar
IDs in the tree.

### Key names

Key names are passed to the renderer, which normalises case,
strips whitespace and separators, and recognises the usual
aliases: `"enter"` / `"return"`, `"esc"` / `"escape"`, `"bs"` /
`"backspace"`. Modifier combos use `+`: `"ctrl+s"`,
`"Shift+Left_Arrow"`, `"Alt+F4"`. Modifier aliases include
`ctrl` / `control`, `alt` / `option` / `opt`, and
`logo` / `super` / `win` / `meta` / `command` / `cmd`.

## Queries

| Method | Returns |
|---|---|
| `find(selector)` | Element hash, or `nil` if not found |
| `find!(selector)` | Element hash, or raises `Plushie::Error` |
| `find_by_role(role)` | First widget whose a11y role matches |
| `find_by_label(label)` | First widget whose a11y label matches |
| `find_focused` | Currently focused widget |
| `text(element)` | Display text of an element |
| `model` | Current app model |
| `tree` | Current tree from the renderer |

`find!` includes the current tree's IDs and up to three similar
IDs in its error message when a widget is missing. The selector
typo is almost always the first thing to suspect, and the hint
points right at it.

`text(element)` returns `content`, `label`, `value`, or
`placeholder`, whichever the widget carries. A `button` gives
back its label. A `text` widget gives back its content. A
`text_input` gives back its value (or its placeholder if empty).

## Assertions

Assertion helpers raise through the host framework: a
`Minitest::Assertion` in Minitest, an
`RSpec::Expectations::ExpectationNotMetError` in RSpec. Each wraps
a query and a comparison.

| Method | Description |
|---|---|
| `assert_text(selector, expected)` | Widget text equals `expected` |
| `assert_exists(selector)` | Widget is in the tree |
| `assert_not_exists(selector)` | Widget is not in the tree |
| `assert_model(expected)` | Model equals `expected` |
| `assert_a11y(selector, expected)` | Every key in `expected` is present in the resolved a11y hash |
| `assert_no_diagnostics` | No prop validation warnings are pending |

```ruby
def test_autosave_banner_renders_after_save
  type_text("#editor", "# edited")
  click("#save")
  assert_exists "#autosave_banner"
  assert_text "#autosave_banner", "Saved"
  assert_a11y "#autosave_banner", role: "status"
end
```

`assert_no_diagnostics` is called automatically by
`Plushie::Test::Case` on teardown. Call it explicitly mid-test to
fence a block of assertions against renderer-side warnings; useful
when a test deliberately induces a warning and you want to clear
the slate before the next block.

`resolved_a11y(selector)` returns the full resolved a11y hash for
direct inspection. It layers render-pipeline inference on top of
the explicit `a11y` prop: `placeholder` becomes `description` on
text-entry widgets, `alt` becomes `label` on media widgets. The
returned hash matches what assistive technology actually sees.

## Effect stubs

Effects (file dialogs, clipboard, notifications) open real OS
dialogs by default. In tests that is unacceptable: the dialog
blocks the run, you cannot script a user, and the CI box has no
display anyway. Effect stubs register a canned response for an
effect kind. The renderer returns that response immediately for
every effect of that kind.

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

Stubs register by **kind** (`:file_open`, `:clipboard_read`,
`:notification`), not by tag. A single stub handles every effect
of that kind for the rest of the test. The case teardown does not
clear stubs, so pair each `register_effect_stub` with an
`unregister_effect_stub` if the test reuses the same kind with a
different response later in its body.

The `response` is encoded straight into the effect's wire result,
so it should match the shape the renderer would otherwise produce.
File dialogs want `{path:}` or `{paths:}`. Clipboard reads want
`{text:}`. To simulate a cancelled dialog, return
`{cancelled: true}`. The event still arrives as
`Event::Effect::Result::Cancelled`, matching the reference in
[chapter 11](11-async-and-effects.md).

Because stubs register at the renderer, the full SDK encode /
decode path runs. A stub that passes a mistyped key still surfaces
wire bugs, which is the whole point of testing against the real
binary.

Async tasks (`Command.task`, `Command.stream`) need no
corresponding stubbing mechanism. In test mode they run
synchronously inside the session, so the result arrives before
the next interaction. The `await_async(tag)` helper exists for
API symmetry with asynchronous backends; it returns `:ok`
immediately in the current test mode.

## Snapshots

Golden-file snapshots live under `test/snapshots/` (tree hashes
and JSON trees) and `test/screenshots/` (pixel hashes). The first
run of a snapshot assertion writes the golden. Subsequent runs
compare against it.

| Method | File written | Purpose |
|---|---|---|
| `assert_tree_hash(name)` | `test/snapshots/NAME.sha256` | Structural hash |
| `assert_tree_snapshot(tree, path)` | Caller-specified JSON | Full tree |
| `assert_screenshot(name)` | `test/screenshots/NAME.sha256` | Pixel hash |
| `save_screenshot(name)` | `test/screenshots/NAME.rgba` | Raw pixel data |

```ruby
def test_pad_layout_is_stable
  assert_tree_hash "pad-initial"
  assert_tree_snapshot(tree, "test/snapshots/pad-initial.json")
end
```

`assert_tree_snapshot` strips `:meta` from the tree before
serialising, so internal SDK bookkeeping (widget state, event
specs, caller-supplied closures) doesn't invalidate the golden.
When `tree` is a `Plushie::Node`, it is converted to its wire form
first.

`assert_screenshot` is a no-op on the `:mock` backend: pixels are
meaningless without rendering, and returning early keeps the same
test passing on every backend. On `:headless` and `:windowed` it
captures the pixel hash through the renderer.

`save_screenshot` is the debugging variant. It captures the full
RGBA buffer and writes it to `test/screenshots/NAME.rgba`, which
you can convert to a PNG locally to see what the renderer actually
drew. Useful when a screenshot assertion fails and you want to
diff the goldens side by side.

### Updating goldens

Set the matching environment variable to overwrite the golden
file instead of asserting against it:

```bash
PLUSHIE_UPDATE_SNAPSHOTS=1 bundle exec rake test     # tree hashes, JSON trees
PLUSHIE_UPDATE_SCREENSHOTS=1 bundle exec rake test   # pixel hashes
```

Two variables, so a UI change that reshapes the tree but not the
pixels (or vice versa) can be reviewed independently. Always
inspect the diff before committing an updated golden: if you can
explain it in the commit message, the new golden is correct.

## .plushie scripts

`.plushie` is a declarative text format for recorded sessions. A
YAML-style header, five or more dashes, then an instruction list:

```
app PlushiePad::App
viewport 1024x768
theme dark
-----
type "#editor" "# smoke test"
click "#save"
assert_text "#status" "Saved"
tree_hash "pad-after-save"
```

Run scripts through Rake:

```bash
bundle exec rake plushie:script                          # every file under test/scripts/
bundle exec rake 'plushie:script[test/scripts/ui.plushie]'
bundle exec rake 'plushie:replay[test/scripts/ui.plushie]'
```

`plushie:script` uses the currently selected backend (default
`:mock`), so it fits into the normal `rake test` loop.
`plushie:replay` forces the `:windowed` backend with a dedicated
single-session pool so you can watch the script play in real time,
which is handy for recording walkthroughs or debugging an
interaction that only misbehaves with real rendering. See the
[Rake tasks reference](../reference/rake-tasks.md) for the full
task surface.

## Testing the pad

With the basics down, wire a suite onto the pad. The pad's
existing `test/app_test.rb` covers model-level behaviour against a
freshly constructed `App` instance without the renderer. That
catches the update logic in isolation, which is good, but it
misses anything that depends on the view layer, the wire
protocol, or keyboard plumbing. Sit the two styles side by side:

```ruby
# test/app_test.rb - existing, unit-level
class AppTest < Minitest::Test
  Event = Plushie::Event

  def setup
    @app = PlushiePad::App.new
    @model = @app.init(nil)
  end

  def test_editor_input_marks_dirty
    updated = @app.update(@model, Event::Widget.new(
      type: :input, id: "editor", value: "# new source"
    ))
    assert updated.dirty
  end
end
```

That test never talks to the renderer. It is fast, but it never
renders the tree, so a broken `view` method sails through.

Add a sibling `test/pad_test.rb` that drives the full loop through
the session pool:

```ruby
# test/pad_test.rb - new, integration-level
require_relative "test_helper"

class PadTest < Plushie::Test::Case
  app PlushiePad::App

  def test_initial_layout_renders_both_panes
    assert_exists "#editor"
    assert_exists "#preview"
    assert_not_exists "#error"
  end

  def test_typing_marks_dirty
    type_text("#editor", "# edited")
    assert model.dirty
  end

  def test_save_button_compiles_and_clears_dirty
    type_text("#editor", valid_experiment_source)
    click("#save")

    refute model.dirty
    assert_not_exists "#error"
    refute_nil model.preview
  end

  def test_ctrl_s_saves
    type_text("#editor", "# edited via shortcut")
    press("ctrl+s")
    refute model.dirty
  end

  def test_invalid_source_shows_error
    type_text("#editor", "module Experiment; raise 'boom'; end; Experiment.view")
    click("#save")
    assert_exists "#error"
    assert_match(/boom/, text(find!("#error")))
  end

  def test_escape_clears_error
    type_text("#editor", "not valid ruby")
    click("#save")
    assert_exists "#error"

    type_key("escape")
    assert_not_exists "#error"
  end

  private

  def valid_experiment_source
    <<~RUBY
      module Experiment
        def self.view
          Plushie::Widget::Text.new("t", "Test passed").build
        end
      end
    RUBY
  end
end
```

Each method drives a real compile cycle through the renderer. If
the wire message for `text_editor` input ever stops carrying
`value`, these tests catch it, which the unit test cannot. If the
view's Ctrl+S shortcut stops routing to save, these catch that
too.

### Testing the sidebar

The sidebar is a list of files rendered with scoped IDs. Click a
row, select its file; click a row's delete button, remove it. Both
paths ride through the pad's `Event::Widget` with a `scope:`
prefix, so the selector syntax for scoped paths pays off:

```ruby
def test_clicking_a_sidebar_entry_switches_active_file
  PlushiePad::Experiments.save("notes.rb", "# notes")
  reset   # pool reset, fresh pad instance picks up the new file

  click("#sidebar/notes.rb/select")
  assert_equal "notes.rb", model.active_file
end
```

`reset` sends a session-level reset to the renderer, which loops
the pad back through `init`. Useful when the test needs the app to
see a filesystem state that did not exist when the session
started.

### Testing the import effect

The pad's Import button opens a file dialog. In tests, stub the
dialog and give it a path to a fixture file:

```ruby
def test_import_adds_fixture_to_sidebar
  fixture = File.join(Dir.mktmpdir, "hello-imported.rb")
  File.write(fixture, "# fixture content")
  register_effect_stub(:file_open, {path: fixture})

  click("#import")

  assert_includes model.files, "hello-imported.rb"
  assert_equal "hello-imported.rb", model.active_file
ensure
  unregister_effect_stub(:file_open)
end
```

The stub applies to every `file_open` effect until unregistered.
The `ensure` block keeps the stub scoped to this test. Without it,
the next test that clicks Import will accidentally reuse the
fixture path.

### Snapshotting the layout

Once the pad's layout settles, lock the shape in with a tree hash.
Any later change that alters the tree will fail the assertion
until the golden is updated, which forces a deliberate review:

```ruby
def test_pad_layout_matches_snapshot
  assert_tree_hash "pad-initial"
end

def test_pad_after_save_matches_snapshot
  type_text("#editor", valid_experiment_source)
  click("#save")
  assert_tree_hash "pad-after-save"
end
```

On the first run these write `test/snapshots/pad-initial.sha256`
and `test/snapshots/pad-after-save.sha256`. Commit the goldens.
Every subsequent run compares against them.

## Exercise: test the auto-save timer

The pad has an auto-save feature: a `Plushie::Subscription.every`
that fires every second while the editor is dirty. The
subscription emits `Event::Timer[tag: :auto_save]`, the update
handler saves the current buffer, and the dirty flag clears.

Write a test that verifies the full loop. The shape:

1. Flip auto-save on (`toggle("#auto-save")`).
2. Type into the editor so the model is dirty.
3. Assert that `model.auto_save` is true and `model.dirty` is
   true, so the subscription is active.
4. Wait for the subscription to fire. The test harness routes
   timer subscriptions deterministically, so a `type_key("enter")`
   or an explicit `press("enter")` is not enough. For timer-driven
   behaviour, dispatch the event directly through the session
   helpers, or advance the clock and let the subscription fire.
5. Assert that `model.dirty` is now false and `model.preview` has
   been refreshed.

Hints:

- The auto-save subscription is wired up in `subscribe(model)`. The
  subscription only registers when both `model.auto_save` and
  `model.dirty` are true, so the tests above already cover the
  predicate half of the wiring.
- The result of a successful auto-save is the same as the result of
  clicking Save: `dirty` clears, `preview` refreshes. You can
  borrow the assertions from `test_save_button_compiles_and_clears_dirty`.
- If you end up writing a whole-loop test and finding yourself
  needing to pause for a real second, reach for `advance_frame` or
  invert the test: assert that the subscription is registered,
  and trust the existing integration tests for the tick handler.

Bonus rounds:

- Turn auto-save off after an edit and assert that the subscription
  disappears from `subscribe(model)`. The view should not carry a
  timer anymore.
- Write an effect-stubbed test for the Import button that feeds in
  a file path whose basename collides with an existing experiment
  and asserts the pad picks a unique name (`hello-2.rb`, ...).
- Snapshot the error state: type garbage into the editor, save,
  and `assert_tree_hash "pad-error"`. Compare the diff when you
  later restyle the error banner.

## See also

- [Testing reference](../reference/testing.md), the full helper
  API, selector grammar, and backend matrix
- [Commands reference](../reference/commands.md), `advance_frame`,
  effect stubs, and the command surface the renderer services
- [Events reference](../reference/events.md), the event classes
  the runtime delivers to `update` during tests
- [Rake tasks reference](../reference/rake-tasks.md),
  `plushie:script`, `plushie:replay`, and the preflight task

## Next chapter

[Shared State](16-shared-state.md)
