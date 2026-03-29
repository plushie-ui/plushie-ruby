# Getting started

Build native desktop GUIs from Ruby. Plushie handles rendering via
iced (Rust) while you own state, logic, and UI trees in pure Ruby.

## Prerequisites

- **Ruby** 3.2+ (install via [ruby-lang.org](https://www.ruby-lang.org)
  or a version manager like rbenv/mise)
- **Bundler** (ships with Ruby)
- **System libraries** for your platform (only needed if building from
  source):
  - Linux: a C compiler, `pkg-config`, and display server headers
    (e.g. `libxkbcommon-dev`, `libwayland-dev` on Debian/Ubuntu)
  - macOS: Xcode command-line tools (`xcode-select --install`)
  - Windows: Visual Studio C++ build tools

## Setup

### 1. Create a new project

```sh
mkdir my_app && cd my_app
bundle init
```

### 2. Add plushie as a dependency

```ruby
# Gemfile
gem "plushie", "== 0.1.0"
```

### 3. Install and download the renderer

```sh
bundle install
```

Add Rake tasks to your Rakefile so you can download the precompiled
renderer binary:

```ruby
# Rakefile
require "plushie/rake"
```

Then:

```sh
bundle exec rake plushie:download
```

The precompiled binary requires no Rust toolchain. To build from
source instead, install [rustup](https://rustup.rs/) and run
`bundle exec rake plushie:build`.

### 4. (Optional) Configure the SDK

If you need to override binary paths, set up extensions, or change
the test backend, use `Plushie.configure`:

```ruby
Plushie.configure do |config|
  config.binary_path = "/opt/plushie/bin/plushie"
  config.source_path = "~/projects/plushie"
  config.test_backend = :headless
end
```

See [Running](running.md) and [Widgets](widgets.md) for the
full list of configuration options.

## Your first app: a counter

Create `lib/counter.rb`:

<!-- test: getting_started_counter_init, getting_started_counter_increment, getting_started_counter_decrement, getting_started_counter_unknown_event, getting_started_counter_view, getting_started_counter_view_after_increments -- keep this code block in sync with the test -->
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

```sh
bundle exec ruby lib/counter.rb
```

A native window appears with the count and two buttons.

## The Elm architecture

Plushie follows the Elm architecture. Your app class includes
`Plushie::App` and implements these callbacks:

- **`init(opts)`** -- returns the initial model (any Ruby object).
- **`update(model, event)`** -- takes the current model and an event,
  returns the new model. Pure function. To run side effects, return
  `[model, command]` instead. See [Commands](commands.md).
- **`view(model)`** -- takes the model and returns a UI tree. Plushie
  diffs trees and sends only patches to the renderer.
- **`subscribe(model)`** (optional) -- returns a list of active
  subscriptions (timers, keyboard events).

See [App behaviour](app-behaviour.md) for the full callback API.

## Event types

Events are `Data.define` structs under `Plushie::Event`. Pattern
match in `update`:

| Event | Meaning |
|---|---|
| `Event::Widget[type: :click, id: id]` | Button click |
| `Event::Widget[type: :input, id: id, value: val]` | Text input change |
| `Event::Widget[type: :submit, id: id, value: val]` | Text input Enter |
| `Event::Widget[type: :toggle, id: id, value: val]` | Checkbox/toggler |
| `Event::Widget[type: :slide, id: id, value: val]` | Slider moved |
| `Event::Widget[type: :select, id: id, value: val]` | Pick list/radio |
| `Event::Timer[tag: tag, timestamp: ts]` | Timer fired |

See [Events](events.md) for the full taxonomy.

## Rake tasks

Add `require "plushie/rake"` to your Rakefile, then:

```bash
rake plushie:download              # download precompiled binary
rake plushie:download[wasm]        # download WASM renderer
rake plushie:build                 # build from Rust source (with extensions if configured)
rake plushie:run[Counter]          # run an app
rake plushie:run[Counter,dev]      # run an app with live reload
rake plushie:connect[Counter]      # connect to renderer via stdio (for plushie --exec)
rake plushie:inspect[Counter]      # print UI tree as JSON
rake plushie:script                # run .plushie test scripts
rake plushie:replay[path]          # replay a script with real windows
rake plushie:preflight             # run all CI checks
```

## Debugging

Use JSON wire format to see messages between Ruby and the renderer.
Pass `format: :json` to `Plushie.run`:

```ruby
Plushie.run(Counter, format: :json)
```

Enable verbose renderer logging:

```sh
RUST_LOG=plushie=debug bundle exec ruby lib/counter.rb
```

## Error handling

If `update` or `view` raises, the runtime catches the exception,
logs it, and continues with the previous state. The GUI does not
crash. Fix the code and the next event works normally.

## Dev mode

Live code reloading without losing application state. Add the
`listen` gem to your Gemfile:

```ruby
gem "listen", "~> 3.0", require: false
```

Then run with `dev: true`:

```ruby
Plushie.run(Counter, dev: true)
```

Edit any `.rb` file in `lib/`, save, and the GUI updates in place.
The model is preserved -- only `view` is re-evaluated with the new
code.

## Custom Widgets

Plushie supports custom widgets at three levels:

- **Render-only composites** -- compose existing widgets into reusable
  components. No Rust, no state management, no binary rebuild.
- **Stateful widgets** -- widgets with internal state and event
  handling. The runtime manages the state lifecycle and dispatches
  events through your `handle_event` callback.
- **Native widgets** -- Rust-backed widgets implementing the
  `WidgetExtension` trait from `plushie-ext`. The build system
  compiles a custom renderer binary that includes your widgets.

All three use `include Plushie::Widget`.

See [Writing custom widgets](widgets.md) for the full guide.

## Next steps

- [Tutorial: building a todo app](tutorial.md) -- step-by-step guide
- Browse the [examples](examples/) for patterns
- [App behaviour](app-behaviour.md) -- full callback API
- [Layout](layout.md) -- sizing and positioning widgets
- [Commands](commands.md) -- async work, file dialogs, effects
- [Events](events.md) -- complete event taxonomy
- [Testing](testing.md) -- writing tests against your UI
- [Theming](theming.md) -- custom themes and palettes
