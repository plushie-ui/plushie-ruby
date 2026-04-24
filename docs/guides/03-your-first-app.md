# Your First App

In the previous chapter we built a counter and learned the
init/update/view cycle. Now we start building **Plushie Pad**, a
live Ruby experiment editor that grows with you throughout the
rest of this guide.

The pad is the running example for every remaining chapter. By
the end of the series it has a sidebar listing saved experiments,
a syntax-highlighted code editor, a preview pane that evaluates
Ruby source and renders the result, an event log, undo / redo,
auto-save, and keyboard shortcuts. We grow into all of that one
chapter at a time.

This chapter scaffolds the project and gets a minimal two-pane
skeleton rendering on screen. The editor will be editable. The
preview area will be a placeholder. Everything else arrives
later.

## Why Ruby?

Ruby ships `Kernel#eval` and `Module.module_eval` in its standard
library, so the pad can compile experiments at runtime without
FFI, subprocesses, or a separate toolchain. Each experiment is a
plain Ruby file that defines `Experiment.view` and returns a
`Plushie::Node`. The pad evaluates the source inside a fresh
anonymous module and renders whatever `view` returns.

That's a lot of machinery to introduce at once. We won't actually
wire up compilation until the next chapter. For now the editor
content is just a string in the model.

## Project layout

Create a new directory next to your other projects and populate
it with this layout:

```
plushie_pad/
  bin/
    plushie_pad              # launcher script
  experiments/
    hello.rb                 # starter experiment (placeholder for now)
  lib/
    plushie_pad.rb           # top-level require + module namespace
    plushie_pad/
      app.rb                 # main Elm loop (init/update/view)
  Gemfile                    # pins the local plushie SDK
  Rakefile                   # test + lint tasks
```

Each file has a narrow job. `bin/plushie_pad` is the entry point
the user runs. `lib/plushie_pad.rb` is the library root and
requires everything else. `lib/plushie_pad/app.rb` holds the
`App` class with `init`, `update`, and `view`. `experiments/`
will eventually hold the Ruby files the pad compiles; for now
it's just a directory.

### Gemfile

```ruby
source "https://rubygems.org"

gem "plushie", path: "../plushie-ruby"

group :development, :test do
  gem "minitest", "~> 5.16"
  gem "standard", "~> 1.3"
  gem "rake", "~> 13.0"
end
```

The `path:` dependency points at your local `plushie-ruby`
checkout. Adjust the relative path to wherever the gem lives on
your machine. Once Plushie ships to RubyGems this will become
`gem "plushie", "~> 0.1"`.

Run `bundle install` to resolve the dependencies.

### Rakefile

```ruby
require "minitest/test_task"

Minitest::TestTask.create

require "standard/rake"

task default: %i[test standard]
```

`rake` runs the test suite and the `standard` linter. We have no
tests yet, and that's fine: `rake test` happily does nothing
until we add some in the later chapters.

### bin/plushie_pad

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "plushie_pad"

Plushie.run(PlushiePad::App)
```

Make it executable with `chmod +x bin/plushie_pad`. The script
adds `lib/` to the load path, requires the top-level pad file,
and hands the `App` class to `Plushie.run`, which instantiates
the app, starts the runtime, and blocks until the window closes.

See the [App Lifecycle reference](../reference/app-lifecycle.md)
for how `Plushie.run` differs from `Plushie.start`.

### lib/plushie_pad.rb

```ruby
# frozen_string_literal: true

require "plushie"

# Plushie Pad: a live Ruby experiment editor.
module PlushiePad
end

require_relative "plushie_pad/app"
```

The top-level file establishes the namespace and requires the
`App` class. Later chapters add `require_relative "plushie_pad/compile"`
and `require_relative "plushie_pad/experiments"` here as we
introduce compilation and disk storage.

### experiments/hello.rb

```ruby
# Experiment: hello
# A placeholder file. Chapter 4 teaches the pad how to compile
# this into a rendered preview.
module Experiment
  def self.view
    Plushie::Widget::Column.new("root", padding: 16, spacing: 8)
      .push(Plushie::Widget::Text.new("greeting", "Hello from hello!", size: 24))
      .push(Plushie::Widget::Text.new("hint", "Edit me and press Save."))
      .build
  end
end
```

This is the format every experiment follows: a `module Experiment`
exposing `self.view`, returning a `Plushie::Node`. The pad doesn't
read this file yet; we ship it so there's something reasonable
waiting when compilation lands next chapter.

Note the typed builder API (`Plushie::Widget::Column.new(...)
.push(...).build`) rather than the block DSL. Experiments compile
in a fresh anonymous module without an app context, so the DSL
context stack is unavailable. The typed builders work anywhere.

## The skeleton App

Here is the complete `lib/plushie_pad/app.rb` for this chapter.
Save it verbatim and we'll walk through the key parts below.

```ruby
# frozen_string_literal: true

require "plushie"

module PlushiePad
  # The main Plushie Pad app. In this chapter the pad is a
  # two-pane shell: an editable text buffer on the left and a
  # placeholder message on the right. Subsequent chapters add
  # compilation, events, a sidebar, undo, and the rest.
  class App
    include Plushie::App

    Model = Plushie::Model.define(
      :source, # current editor buffer (String)
      :preview # placeholder for now; will hold a Plushie::Node later
    )

    def init(_opts)
      Model.new(
        source: "# Write some Ruby here. Save to render.\n",
        preview: nil
      )
    end

    def update(model, event)
      case event
      in Event::Widget[type: :input, id: "editor", value: source]
        model.with(source: source)
      else
        model
      end
    end

    def view(model)
      window("main", title: "Plushie Pad", theme: :dark) do
        column("root", width: :fill, height: :fill) do
          row("split", width: :fill, height: :fill) do
            editor_pane(model)
            preview_pane(model)
          end
          toolbar
        end
      end
    end

    private

    def editor_pane(model)
      text_editor("editor", model.source,
        width: [:fill_portion, 1],
        height: :fill,
        highlight_syntax: "ruby",
        font: :monospace)
    end

    def preview_pane(model)
      container("preview",
        width: [:fill_portion, 1],
        height: :fill,
        padding: 16) do
        if model.preview
          # Placeholder wiring: chapter 4 replaces this with a
          # real compile + render pass.
          text("compiled", "preview goes here")
        else
          text("placeholder", "Press Save to compile")
        end
      end
    end

    def toolbar
      row("toolbar", padding: [8, 4], spacing: 8) do
        button("save", "Save")
      end
    end
  end
end
```

Run it:

```bash
bundle exec bin/plushie_pad
```

A dark window opens with an editable pane on the left, a centred
"Press Save to compile" message on the right, and a Save button
at the bottom. Typing into the editor updates the buffer. The
Save button does nothing yet. The preview never changes.

## Walking through the code

### include Plushie::App

`include Plushie::App` mixes three things into `App`:

- `Plushie::UI`, the block DSL (`window`, `column`, `row`,
  `container`, `text_editor`, `button`, `text`, and the rest of
  the [Built-in Widgets](../reference/built-in-widgets.md) catalog).
- Default no-op implementations of the optional lifecycle hooks
  (`subscribe`, `settings`, `window_config`, `handle_renderer_exit`).
- Top-level constant aliases, so `Event` inside the class body
  resolves to `Plushie::Event`. We rely on that alias in the
  `case/in` arm below.

See the [DSL reference](../reference/dsl.md) for the mechanics.

### Model.define

```ruby
Model = Plushie::Model.define(:source, :preview)
```

`Plushie::Model.define` is a thin wrapper around Ruby's
`Data.define` that mixes in a `#with` method for partial updates.
Instances are frozen; attempting to mutate raises `FrozenError`.
The canonical idiom throughout the lifecycle is to return a new
model from `#with`:

```ruby
model.with(source: new_source)
```

Forgetting to return the result is a silent no-op: `with` builds
a new instance but doesn't touch the original.

### init

```ruby
def init(_opts)
  Model.new(
    source: "# Write some Ruby here. Save to render.\n",
    preview: nil
  )
end
```

`init` runs once at startup and returns the initial model. The
argument is an options hash the runtime passes through; we don't
need it yet, so we prefix the parameter with an underscore to
signal intent.

`preview` stays `nil` for the whole chapter. In chapter 4 we'll
have it hold a `Plushie::Node` (the compiled experiment tree) or
stay `nil` when compilation hasn't happened yet.

### update

```ruby
def update(model, event)
  case event
  in Event::Widget[type: :input, id: "editor", value: source]
    model.with(source: source)
  else
    model
  end
end
```

`update` receives the current model and an event, returning the
next model. We pattern-match using Ruby's `case/in` syntax
against the event classes documented in the
[Events reference](../reference/events.md). The `text_editor`
widget emits `Event::Widget` with `type: :input` on every
keystroke, carrying the full buffer in `value`. We pull it out
and return a new model with the updated source.

The `else model` branch is mandatory. Without it, Ruby raises
`NoMatchingPatternError` on any event you don't explicitly
handle. The runtime rescues the error and logs a helpful hint,
but the noise is avoidable: always include the catch-all.

### view

```ruby
def view(model)
  window("main", title: "Plushie Pad", theme: :dark) do
    column("root", width: :fill, height: :fill) do
      row("split", width: :fill, height: :fill) do
        editor_pane(model)
        preview_pane(model)
      end
      toolbar
    end
  end
end
```

`view` returns a widget tree. A Plushie view must be a `window`
node (or an array of window nodes for multi-window apps).
Returning a bare `column` or `text` raises at the top level.

The structure is a vertical split: a full-width `row` holding the
editor and preview panes, with a `toolbar` row stacked below. The
outer `column` fills the window. `width: :fill` and
`height: :fill` say "take all the available space"; we cover
sizing in depth in [chapter 7](07-layout.md).

Inside the blocks, `self` is still the `App` instance, so helper
methods like `editor_pane(model)` and `preview_pane(model)` work
the way you expect. Block-based DSLs in Ruby often use
`instance_eval`, which would change `self` inside the block;
Plushie's DSL deliberately does not, so your private helpers
remain callable.

### text_editor

```ruby
text_editor("editor", model.source,
  width: [:fill_portion, 1],
  height: :fill,
  highlight_syntax: "ruby",
  font: :monospace)
```

`text_editor` is a multi-line editable area with syntax
highlighting. The positional arguments are the widget ID and the
initial content. Subsequent edits arrive as `Event::Widget`
values with `type: :input` and the new content as `value`.

`highlight_syntax: "ruby"` turns on Ruby syntax highlighting.
Other values (`"markdown"`, `"rust"`, `"js"`) pick other
languages.

`[:fill_portion, 1]` gives the editor a proportional slice of
its parent's width. The preview pane uses the same portion, so
the split is 50/50. Change one side to `[:fill_portion, 2]` and
it takes twice as much space.

`text_editor` is one of the stateful widgets (cursor position,
scroll offset, text selection live in the renderer). It needs an
explicit string ID so the renderer can match it to its state
across renders. Other stateful widgets: `text_input`,
`combo_box`, `scrollable`, `pane_grid`. If their ID changes, the
state resets. Layout widgets like `column` and `row` are
stateless, so auto-generated IDs would work fine there. We still
pass explicit IDs in this chapter because stable IDs make the
event log easier to read once we add it.

### container and the preview placeholder

```ruby
container("preview",
  width: [:fill_portion, 1],
  height: :fill,
  padding: 16) do
  if model.preview
    text("compiled", "preview goes here")
  else
    text("placeholder", "Press Save to compile")
  end
end
```

`container` is a single-child wrapper. Here it gives the preview
area a width, height, and padding independent of whatever the
preview itself wants. The `"preview"` ID will matter in a later
chapter when we need to distinguish events emitted by preview
widgets from events emitted by the pad's own chrome.

The `if / else` inside the block selects a child to render. Ruby
if-expressions return their last value, and the DSL pushes each
rendered `text(...)` call onto the current container's child
list. Whichever branch runs, exactly one `text` child ends up
under `"preview"`.

### button

```ruby
button("save", "Save")
```

Button takes an ID and a label. It emits `Event::Widget` with
`type: :click` when pressed. We don't handle the click yet: the
`else` arm of `update` swallows it. Chapter 4 is where Save
starts doing something.

## The pad, running

Start the pad (`bundle exec bin/plushie_pad`) and verify:

- Typing into the left pane updates the buffer. The content
  follows your cursor live.
- The right pane shows `Press Save to compile` centred in its
  padded area.
- The Save button is visible at the bottom and clickable, though
  it does nothing.

If the renderer can't start, check that `PLUSHIE_BINARY_PATH`
points at a working renderer build, or set
`PLUSHIE_RUST_SOURCE_PATH` to your `plushie-rust` checkout and
run `rake plushie:build` in the `plushie-ruby` gem to produce
one. The [Configuration reference](../reference/configuration.md)
covers the full set of environment variables.

## The teaching arc

Each of the remaining guide chapters grows the pad by one
capability. After each chapter the pad does a little more:

- **Chapter 4: The Development Loop.** Hot reload for the pad's
  own source, plus the first version of `Compile.compile_and_render`.
  The Save button now evaluates the editor buffer inside a fresh
  anonymous module and renders whatever `Experiment.view`
  returns. Compile errors land in the preview pane as red text.
- **Chapter 5: Events.** The full event taxonomy, pattern
  matching, and the event log. By the end of this chapter the
  pad has a scrolling event log at the bottom showing every
  event the preview emits.
- **Chapter 6: Lists and Inputs.** The sidebar arrives: a list
  of experiment filenames, click to switch, a delete button per
  row, and a "new experiment name" input in the toolbar.
- **Chapter 7: Layout.** Sizing, padding, alignment, the grid
  widget. The pad's three-pane layout gets cleaner constraints
  and a resize-friendly toolbar.
- **Chapter 8: Styling.** Colours, themes, and the `StyleMap`.
  The sidebar highlights the active file; the error banner
  becomes distinct; the Save button gets a primary style.
- **Chapter 9: Animation.** Transitions on the error banner and
  a subtle fade on preview swaps.
- **Chapter 10: Subscriptions.** Global keyboard subscriptions.
  Ctrl+S saves, Ctrl+Z undoes, Ctrl+Shift+Z redoes, Escape
  clears errors.
- **Chapter 11: Async and Effects.** Auto-save as a periodic
  timer, file I/O as side effects with typed results.
- **Chapter 14: State Management.** Undo / redo around the
  editor buffer using `Plushie::Undo` with coalesced keystrokes.
- **Chapter 15: Testing.** Tests for the pad using
  `Plushie::Test::Case`, covering the layout, compilation, and
  keyboard shortcuts.

Each chapter ends with a short "the pad now does X" recap so
you can stop reading, run the code, and see the new feature
working before moving on.

## See also

- [App Lifecycle reference](../reference/app-lifecycle.md),
  callbacks, startup, error recovery, renderer restart
- [Built-in Widgets reference](../reference/built-in-widgets.md),
  the full widget catalog with props for `text_editor`, `container`,
  `button`, and everything else
- [DSL reference](../reference/dsl.md), how `Plushie::App` mixes
  in the DSL, the context stack, auto-IDs, and the typed builder
  alternative

## Next chapter

[The Development Loop](04-the-development-loop.md)
