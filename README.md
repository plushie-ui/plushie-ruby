# plushie

Build native desktop apps in Ruby. **Pre-1.0**

Plushie is a desktop GUI framework that allows you to write your entire
application in Ruby -- state, events, UI -- and get native windows
on Linux, macOS, and Windows. Rendering is powered by
[iced](https://github.com/iced-rs/iced), a cross-platform GUI library
for Rust, which plushie drives as a precompiled binary behind the scenes.

```ruby
class Counter
  include Plushie::App

  Model = Plushie::Model.define(:count)

  def init(_opts) = Model.new(count: 0)

  def update(model, event)
    case event
    in Event::Widget[type: :click, id: "inc"]
      model.with(count: model.count + 1)
    in Event::Widget[type: :click, id: "dec"]
      model.with(count: model.count - 1)
    else
      model
    end
  end

  def view(model)
    window("main", title: "Counter") do
      column(padding: 16, spacing: 8) do
        text("count", "Count: #{model.count}")
        row(spacing: 8) do
          button("inc", "+")
          button("dec", "-")
        end
      end
    end
  end
end

Plushie.run(Counter)
```

This is one of [8 examples](examples/) included in the repo, from a
minimal counter to a full widget catalog. For complete project demos,
including native Rust extensions, see the
[plushie-demos](https://github.com/plushie-ui/plushie-demos/tree/main/ruby)
repository.

## Getting started

Add plushie to your Gemfile:

```ruby
gem "plushie", "== 0.1.0"
```

Then:

```bash
bundle install
rake plushie:download   # download precompiled renderer binary
```

Requires Ruby 3.2+. The precompiled binary requires no Rust toolchain.

### Your first app

Create `lib/counter.rb`:

```ruby
require "plushie"

class Counter
  include Plushie::App

  Model = Plushie::Model.define(:count)

  def init(_opts) = Model.new(count: 0)

  def update(model, event)
    case event
    in Event::Widget[type: :click, id: "increment"]
      model.with(count: model.count + 1)
    in Event::Widget[type: :click, id: "decrement"]
      model.with(count: model.count - 1)
    else
      model
    end
  end

  def view(model)
    window("main", title: "Counter") do
      column(padding: 16, spacing: 8) do
        text("count", "Count: #{model.count}", size: 20)
        row(spacing: 8) do
          button("increment", "+")
          button("decrement", "-")
        end
      end
    end
  end
end

Plushie.run(Counter)
```

Run it:

```bash
ruby lib/counter.rb
```

## The Elm architecture

Plushie follows the Elm architecture. Your app implements four callbacks:

- **`init(opts)`** -- returns the initial model (any Ruby object, ideally
  immutable via `Plushie::Model.define`).
- **`update(model, event)`** -- receives the current model and an event,
  returns the new model. Pure function. Return `[model, command]` for
  side effects.
- **`view(model)`** -- receives the model, returns a `window(...)`
  node or an array of window nodes using the block DSL. The runtime
  diffs trees and sends patches to the renderer.
- **`subscribe(model)`** (optional) -- returns active subscriptions
  (timers, keyboard/mouse events).

## Features

- **39 built-in widget types** -- buttons, text inputs, sliders, tables,
  markdown, canvas, pane grids, and more.
- **22 built-in themes** -- light, dark, dracula, nord, catppuccin,
  tokyo night, kanagawa, and more.
- **Multi-window** -- declare window nodes in your widget tree; the
  framework manages them automatically.
- **Platform effects** -- native file dialogs, clipboard, OS
  notifications.
- **Accessibility** -- screen reader support via accesskit.
- **Live reload** -- `Plushie.run(MyApp, dev: true)` watches lib/ and
  reloads on file changes. Model state is preserved.
- **Remote rendering** -- native desktop UI for server-side Ruby apps
  over SSH. Your init/update/view code doesn't change.
- **Custom widgets** -- pure Ruby composites, stateful widgets with
  event handling, or native Rust-backed widgets via `include Plushie::Widget`.
- **Configuration system** -- `Plushie.configure` for binary paths,
  widgets, test backends, and widget runtime config.
- **WASM renderer** -- `rake plushie:download[wasm]` downloads a WASM
  build of the renderer for browser targets.

## Documentation

**Guides:**

- [Getting started](docs/getting-started.md) -- setup, first app, rake tasks, dev mode
- [Tutorial: building a todo app](docs/tutorial.md) -- step-by-step walkthrough
- [App behaviour](docs/app-behaviour.md) -- init, update, view, subscribe callbacks
- [Layout](docs/layout.md) -- column, row, container, spacing, alignment
- [Events](docs/events.md) -- widget, keyboard, mouse, window, canvas events
- [Commands](docs/commands.md) -- async, timers, widget ops, effects, batching
- [Effects](docs/effects.md) -- file dialogs, clipboard, notifications
- [Scoped IDs](docs/scoped-ids.md) -- how container nesting scopes widget IDs

**Advanced:**

- [Running](docs/running.md) -- transports, remote rendering, WASM
- [Theming](docs/theming.md) -- built-in themes and custom styling
- [Testing](docs/testing.md) -- mock, headless, and windowed backends
- [Composition patterns](docs/composition-patterns.md) -- tabs, modals, forms, lists
- [Accessibility](docs/accessibility.md) -- screen reader support, roles, labels
- [Widgets](docs/widgets.md) -- Ruby composites and native Rust widgets
- [DSL internals](docs/dsl-internals.md) -- how the UI builder works under the hood

**API reference:** [rubydoc.info/gems/plushie](https://www.rubydoc.info/gems/plushie)

## Testing

All testing goes through the renderer binary. No Ruby-side mocks.
The mock backend runs at millisecond speed.

Add `require "plushie/test"` to your test helper:

```ruby
# test/test_helper.rb
require "plushie"
require "plushie/test"
require "minitest/autorun"
```

Then write tests:

```ruby
class CounterTest < Plushie::Test::Case
  app Counter

  def test_clicking_increment_updates_counter
    click("#increment")
    assert_text "#count", "Count: 1"
  end
end
```

Three interchangeable backends:

- **Mock** (`PLUSHIE_TEST_BACKEND=mock`) -- millisecond tests, no display.
  Default.
- **Headless** (`PLUSHIE_TEST_BACKEND=headless`) -- real rendering via
  tiny-skia, no display server. Pixel screenshots.
- **Windowed** (`PLUSHIE_TEST_BACKEND=windowed`) -- real windows with GPU.
  Needs display server (Xvfb in CI).

## How it works

Under the hood, a renderer built on iced handles window drawing and
platform integration. Your Ruby code sends widget trees to the
renderer over stdin; the renderer draws native windows and sends user
events back over stdout.

You don't need Rust to use plushie. The renderer is a precompiled
binary, similar to how your app talks to a database without you
writing C. If you need custom native rendering, the extension system
lets you write Rust for just those parts.

The same protocol works over a local pipe, an SSH connection, or any
bidirectional byte stream.

## State helpers

Plushie ships optional state management utilities:

- **`Plushie::Animation`** -- easing functions and interpolation
- **`Plushie::Route`** -- navigation stack for multi-view apps
- **`Plushie::Selection`** -- single, multi, and range selection
- **`Plushie::Undo`** -- undo/redo stacks with coalescing
- **`Plushie::DataQuery`** -- filter, search, sort, paginate collections
- **`Plushie::State`** -- path-based state with revision tracking

## Development

```bash
bundle exec rake              # tests + linter + type check
bundle exec rake test         # tests only
bundle exec rake standard     # linter only
bundle exec rake steep        # type check only
bundle exec rake yard         # generate API docs to doc/
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full development guide.

Rake tasks (add `require "plushie/rake"` to your Rakefile):

```bash
rake plushie:download          # download precompiled binary
rake plushie:download[wasm]    # download WASM renderer
rake plushie:build             # build from Rust source (with extensions if configured)
rake plushie:run[Counter]      # run an app
rake plushie:connect[Counter]  # connect to renderer via stdio
rake plushie:inspect[Counter]  # print UI tree as JSON
rake plushie:script            # run .plushie test scripts
rake plushie:replay[path]      # replay a script with real windows
rake plushie:preflight         # run all CI checks
```

Configure the SDK programmatically:

```ruby
Plushie.configure do |config|
  config.binary_path = "/opt/plushie/bin/plushie"
  config.extensions = [MyGauge]
  config.test_backend = :headless
end
```

## System requirements

The precompiled binary has no additional dependencies. To build from
source, install a Rust toolchain via [rustup](https://rustup.rs/) and
the platform-specific libraries:

- **Linux (Debian/Ubuntu):**
  `sudo apt-get install libxkbcommon-dev libwayland-dev libx11-dev cmake fontconfig pkg-config`
- **Linux (Arch):**
  `sudo pacman -S libxkbcommon wayland libx11 cmake fontconfig pkgconf`
- **macOS:** `xcode-select --install`
- **Windows:**
  [Visual Studio Build Tools](https://visualstudio.microsoft.com/visual-cpp-build-tools/)
  with "Desktop development with C++"

## Links

| | |
|---|---|
| Ruby SDK | [github.com/plushie-ui/plushie-ruby](https://github.com/plushie-ui/plushie-ruby) |
| Elixir SDK | [github.com/plushie-ui/plushie-elixir](https://github.com/plushie-ui/plushie-elixir) |
| Renderer | [github.com/plushie-ui/plushie](https://github.com/plushie-ui/plushie) |

## License

MIT
