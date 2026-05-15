# Native Extensions

A Plushie Ruby app runs in two processes: the Ruby process holds the
model, the view function, and the event loop; the Rust
`plushie-renderer` subprocess owns the GPU, the window, and every
widget implementation. A native extension is a Rust crate that
implements one or more widgets and is compiled into a custom renderer
binary that the Ruby gem drives. The Ruby side declares the widget's
interface via `include Plushie::Widget` with `kind: :native_widget`;
the Rust side implements the `PlushieWidget` trait from
`plushie-widget-sdk` and declares its metadata in `Cargo.toml`.

This page walks the full path: when to reach for a native widget,
what each side must declare, how `rake plushie:build` stitches them
together, how commands and events flow across the wire, and how a
native widget is shipped inside a gem.

For the smaller picture (custom widgets in pure Ruby, plus the
declaration shape), see the [Custom Widgets reference](custom-widgets.md).

## Why a separate process

The renderer is a separate binary because iced (the GUI toolkit
Plushie wraps) needs direct access to the GPU, the windowing system,
and a native event loop. Ruby can't host those APIs sanely across
every supported platform, and the GIL would serialise work that
needs to parallelise per frame.

Consequences worth naming:

- Custom rendering is **Rust code**, not Ruby C extensions. The
  Ruby gem has no `ext/` directory, no `rake compile`, no
  `rb-sys`. Ruby talks to the Rust renderer over a
  stdin/stdout pipe.
- A native widget ships in two halves: a Rust crate (the
  implementation) and a Ruby class (the declaration). Neither half
  is useful without the other.
- The WASM renderer is compiled from the same Rust source, but the
  build pipeline for WASM does not currently include user-supplied
  native widgets. Apps that must run under WASM have to get by
  with the built-in widgets and [canvas](canvas.md).

## When to build a native widget

Reach for a native widget when:

- The widget needs drawing primitives beyond what [`canvas`](canvas.md)
  can express (iced `Program` access, shaders, custom layouts).
- Per-frame work in Ruby would be too slow (tens of thousands of
  points per frame, live streaming plots, dense geometry).
- Platform integration has to happen renderer-side (IME composition,
  tablet pressure, MIDI, native file previews).
- An existing Rust crate already implements the thing you want, and
  you'd rather glue it in than reimplement it.

Stay in Ruby when the widget is composition-heavy (stacking built-in
widgets and canvas layers), needs no custom drawing, or benefits from
rapid iteration. Pure-Ruby widgets hot-reload; native widgets require
a full renderer rebuild.

## The two halves

Every native widget has exactly one Ruby class and one Rust crate.
They are wired together by shared metadata: a symbol type name on
the Ruby side matches a string type name on the Rust side, and a
Rust constructor expression the Ruby declaration quotes appears as
real code inside the widget crate.

| Side | Declares | File |
|---|---|---|
| Ruby | type, props, events, commands, Rust crate path | `lib/<widget>_extension.rb` (by convention) |
| Rust | trait impl, rendering, event emission | `native/<widget>/src/lib.rs` |
| Rust | crate metadata | `native/<widget>/Cargo.toml` |

The mismatch between the Ruby `rust_constructor` string and the
Rust `[package.metadata.plushie.widget]` table is caught at build
time: `cargo plushie build` aborts before compiling when the two
don't agree.

## Rust side

A native widget crate is a plain Rust library that depends on
[`plushie-widget-sdk`](https://docs.rs/plushie-widget-sdk) and
implements the `PlushieWidget` trait. The trait is deliberately
small: name the widget, render an `iced::Element` from the tree
node's props, and produce a fresh per-session instance. Optional
hooks cover state init, per-frame preparation, widget command
dispatch, and cleanup.

### Cargo.toml

```toml
[package]
name    = "sparkline"
version = "0.1.0"
edition = "2024"

[package.metadata.plushie.widget]
type_name   = "sparkline"
constructor = "sparkline::SparklineExtension::new()"

[dependencies]
plushie-widget-sdk = "0.6"
```

The `[package.metadata.plushie.widget]` table is the source of
truth. `type_name` is the symbol that also appears in the Ruby
`widget :sparkline, kind: :native_widget` declaration; `constructor`
is the Rust expression `cargo plushie build` emits when it
generates the real renderer binary's main entry point.

The crate must declare `plushie-widget-sdk` directly. Pull in
`plushie-core` alongside it if the widget uses any of the derive
macros (`#[derive(PlushieWidget)]`, `#[derive(WidgetEvent)]`,
`#[derive(WidgetCommand)]`, `#[derive(WidgetProps)]`); the generated
code references `::plushie_core::*` paths.

### lib.rs

The minimal shape of a widget, in skeleton form:

```rust
use plushie_widget_sdk::prelude::*;

pub struct SparklineExtension;

impl SparklineExtension {
    pub fn new() -> Self {
        Self
    }
}

impl<R: PlushieRenderer> PlushieWidget<R> for SparklineExtension {
    fn type_names(&self) -> &[&str] {
        &["sparkline"]
    }

    fn namespace(&self) -> &str {
        "sparkline"
    }

    fn fresh_for_session(&self) -> Box<dyn PlushieWidget<R>> {
        Box::new(SparklineExtension::new())
    }

    fn render<'a>(
        &'a self,
        node: &'a TreeNode,
        ctx: &RenderCtx<'a, R>,
    ) -> Element<'a, Message, Theme, R> {
        // Read props from `node.props`, build an iced Element, return it.
        todo!()
    }
}
```

Key methods:

| Method | Purpose |
|---|---|
| `type_names` | Widget types this crate handles. Usually one; multiple when a single crate ships a small family (e.g. `sparkline` plus `sparkline_group`). |
| `namespace` | Namespace for per-widget runtime config (keyed under `settings.widget_config` on the Ruby side). |
| `fresh_for_session` | Returns a fresh widget instance for a new renderer session. The test session pool hangs if this isn't implemented, because it reuses one renderer process across tests and relies on widgets rehydrating on each session reset. |
| `render` | Builds the iced element from the incoming tree node. Called on every render after prop diffs. |

Optional hooks cover initialisation, per-frame preparation,
receiving commands (`handle_widget_op`), and cleanup. See the
[plushie-widget-sdk docs](https://docs.rs/plushie-widget-sdk) for
the full trait surface.

For iced types, prefer the `plushie_widget_sdk::prelude` and the
`iced_convert` helpers over depending on `iced` directly: the SDK
re-exports a pinned iced version and conversions from Plushie types
(`Color`, `Length`, `Padding`) into their iced equivalents.

## Ruby side

The Ruby declaration names the widget, its props, its events, and
the path to the Rust crate. It produces a class whose `.new(id,
**opts).build` returns a placeholder node the runtime sends over
the wire; all real rendering happens on the renderer side.

```ruby
require "plushie"

class SparklineExtension
  include Plushie::Widget

  widget :sparkline, kind: :native_widget

  rust_crate       "native/sparkline"
  rust_constructor "sparkline::SparklineExtension::new()"

  prop :data,         :any,     default: []
  prop :color,        :color,   default: "#4CAF50"
  prop :stroke_width, :number,  default: 2.0
  prop :fill,         :boolean, default: false
  prop :height,       :number,  default: 60.0
end
```

| Declaration | Purpose |
|---|---|
| `widget :name, kind: :native_widget` | Wire type name, plus the flag that marks this class for the native build pipeline |
| `rust_crate "path"` | Relative path from the project root to the Rust crate directory |
| `rust_constructor "expr"` | Rust expression used in the generated renderer's main function. Must match the crate's `[package.metadata.plushie.widget].constructor` |
| `prop :name, :type, default:` | Typed prop, validated at construction. Known types: `:number`, `:string`, `:boolean`, `:color`, `:length`, `:padding`, `:alignment`, `:style`, `:font`, `:atom`, `:map`, `:any` |
| `event :name, fields: {...}` | Event the widget emits back to Ruby, with optional typed field validation |
| `command :name, key: type` | Informational declaration of a command the widget accepts. Payloads are sent via `Plushie::Command.widget_command` |

The `Widget.define` form accepts the same declarations when a full
class isn't needed:

```ruby
Sparkline = Plushie::Widget.define(:sparkline, kind: :native_widget) do
  rust_crate       "native/sparkline"
  rust_constructor "sparkline::SparklineExtension::new()"
  prop :data, :any, default: []
end
```

### Placing the widget

A native widget is placed in `view` the same way a built-in widget
is, and props are passed as keyword args. Because the declaration
is a plain class, the widget is not a first-class method on
`Plushie::UI`; call its constructor explicitly and chain `#build` so
the DSL context attaches it to its parent:

```ruby
def view(model)
  window("main", title: "Dashboard") do
    column("root", padding: 20, spacing: 16) do
      SparklineExtension.new("cpu_spark",
        data: model.cpu_samples,
        color: "#4CAF50",
        fill: true).build
    end
  end
end
```

Wrapping frequently placed widgets in a `Plushie::WidgetSet` override
or a small app-level helper method cleans up the call sites (see
[Composition Patterns](composition-patterns.md#widget-set-overrides)).

### Registration

The build pipeline needs to know which classes are native widgets
and where their crates live. Register them via the configure block:

```ruby
require_relative "sparkline_extension"

Plushie.configure do |config|
  config.widgets    = [SparklineExtension]
  config.build_name = "dashboard-plushie"
end
```

For CI, the `PLUSHIE_WIDGETS` env var accepts a comma-separated
list of fully qualified class names:

```bash
PLUSHIE_WIDGETS=SparklineExtension,MyApp::Chart \
  bundle exec rake plushie:build
```

Non-native classes in the list are skipped with a warning, so a
mixed widget list is safe. See the
[Configuration reference](configuration.md) for the full set of
configurable attributes.

## Building the renderer

`rake plushie:build` is the one command that glues the two halves
together:

```bash
bundle exec rake plushie:build               # debug
bundle exec rake 'plushie:build[release]'    # optimised
```

The task, in order:

1. Resolves `Plushie.configuration.widgets` (or `PLUSHIE_WIDGETS`)
   and filters to the native ones.
2. Refuses any `rust_crate` path that resolves outside the project
   root.
3. Verifies every widget crate declares
   `[package.metadata.plushie.widget]` with `type_name` and
   `constructor`.
4. Writes a virtual app crate under `_build/plushie-renderer-spec/`
   that lists each widget crate as a path dependency and carries
   the final binary name in `[package.metadata.plushie]`.
5. Shells out to `cargo plushie build`, which generates the real
   renderer workspace (with `[patch.crates-io]` entries for every
   plushie crate), runs `cargo build`, and locates the produced
   binary.
6. Copies the binary to `bin/plushie-renderer` so
   `Plushie::Binary.path!` finds it.

`cargo-plushie` itself is resolved in priority order:

1. `PLUSHIE_RUST_SOURCE_PATH` set (or
   `Plushie.configuration.source_path`): invoked as
   `cargo run -p cargo-plushie` against the checkout. Always
   matches the source, no install required.
2. `cargo-plushie` on `PATH` at the version pinned by
   `Plushie::PLUSHIE_RUST_VERSION`.
3. Fails with install hints. No auto-install.

See the [Rake Tasks reference](rake-tasks.md#plushiebuild) for the
full task surface and the [Versioning reference](versioning.md) for
how the gem version pins `PLUSHIE_RUST_VERSION`.

### Iterating on the Rust side

For day-to-day work inside a plushie-rust checkout, point at it so
every rebuild picks up local changes to both the widget SDK and
`cargo-plushie`:

```bash
git clone https://github.com/plushie-ui/plushie-rust ../plushie-rust
export PLUSHIE_RUST_SOURCE_PATH=../plushie-rust

bundle exec rake 'plushie:build[release]'
bundle exec rake 'plushie:run[Dashboard]'
```

Without a source path, builds pull the pinned renderer and widget
SDK versions from crates.io.

## Sending commands to a widget

`Plushie::Command.widget_command(id, family, value)` delivers an
operation to a widget on the renderer side, keyed by the widget's
scoped ID and a family name the Rust crate recognises. Declare
commands on the Ruby class for discoverability and emit them from
`update`:

```ruby
class SparklineExtension
  include Plushie::Widget

  widget :sparkline, kind: :native_widget

  command :reset
  command :set_range, min: :float, max: :float
end

class Dashboard
  include Plushie::App

  def update(model, event)
    case event
    in Event::Widget[type: :click, id: "clear"]
      [model.with(cpu_samples: []),
       Plushie::Command.widget_command("cpu_spark", "reset")]

    in Event::Widget[type: :click, id: "set_range"]
      [model,
       Plushie::Command.widget_command("cpu_spark", "set_range",
         {min: 0.0, max: 100.0})]
    end
  end
end
```

Use `Plushie::Command.widget_batch(commands)` for a group of
commands that must apply in a single cycle before any resulting
events fire.

On the Rust side, the command arrives at the widget's optional
`handle_widget_op(node_id, op, payload)` hook. The widget inspects
`op` (the family string) and `payload` (a value decoded from
MessagePack or JSON) and returns an updated state plus any iced
messages. See the `PlushieWidget` trait docs for the precise
signature.

See the [Commands reference](commands.md#widget-commands) for the
full `widget_command` and `widget_batch` surface.

## Events from the widget

Events flow the other way through the same pipe. When the widget
emits an event on the renderer side, the renderer serialises it as
a widget event frame, the Ruby runtime decodes it into an
`Event::Widget` with the declared widget type, and it arrives in
`update` like any other event:

```ruby
class SparklineExtension
  include Plushie::Widget

  widget :sparkline, kind: :native_widget
  event  :point_clicked, fields: { index: Integer, value: Numeric }
end

def update(model, event)
  case event
  in Event::Widget[type: [:sparkline, :point_clicked],
                   id: id,
                   value: { index:, value: }]
    model.with(selected: { chart: id, index:, value: })
  end
end
```

The `type:` field of a declared widget event is the two-element form
`[widget_type, event_name]`, matching the convention used by custom
widgets in general. Fields declared with `event :name, fields: {...}`
are validated on the Ruby side against the declared classes; a
missing required field raises.

Events the widget does not declare can still arrive, but there's no
field validation and the `type:` shape mirrors whatever the renderer
produced. Declaring events is what makes the widget's public contract
explicit and machine-checkable.

## Settings and per-widget config

The app-level `settings` callback may carry a `widget_config` hash
whose keys are widget namespaces (the string returned from the
Rust widget's `namespace` method). Values pass through to the
widget on the renderer side unchanged:

```ruby
def settings
  {
    widget_config: {
      "sparkline" => { "max_samples" => 1000 }
    }
  }
end
```

Setting `Plushie.configuration.widget_config` does the same thing
globally. When both are set, the `settings` callback's value wins.

Add `required_widgets: ["sparkline"]` to the settings hash to turn a
missing widget from a silent fallback into a loud diagnostic:
`Plushie::Error` is raised during the handshake if the renderer
doesn't advertise every required namespace.

## Testing a native widget

`Plushie::Test::Case` runs against the real renderer binary, so a
widget under test is the same widget that ships in production.
Three things to watch:

- **`fresh_for_session` is mandatory.** The session pool
  multiplexes multiple tests through a single renderer process and
  asks each widget for a fresh instance between sessions. A widget
  without `fresh_for_session` implemented hangs the pool.
- **Backend selection.** `:mock` (default) exercises the wire
  protocol and handshake but skips rendering; `:headless` runs the
  full software renderer; `:windowed` needs a display server. Pick
  the lightest backend that verifies what the test is actually
  checking. See the [Testing reference](testing.md) for the full
  backend matrix.
- **Register before building.** Tests that load an app class without
  calling `Plushie.configure { config.widgets = [...] }` start the
  stock renderer, not a custom one; the widget's `type_name` will
  be rejected on the wire. The demo projects set this up in their
  `Rakefile` and test helper so every test path picks it up.

Once the widget is registered, a test looks the same as any other
Plushie test:

```ruby
require "test_helper"
require "plushie/test"

class SparklineTest < Plushie::Test::Case
  def test_renders_with_data
    with_app(Dashboard) do |app|
      node = app.find_by_type("sparkline")
      assert_equal [1.0, 2.0, 3.0], node.props[:data]
    end
  end
end
```

See the [Testing reference](testing.md) for helpers, backend
selection, and the `.plushie` script format.

## Distribution

A native widget is most naturally packaged as a gem that contains
both the Ruby side and the Rust source. Consumers depend on the
gem, run `rake plushie:build` once, and get a custom renderer.

### Directory layout

```
my_sparkline/
  my_sparkline.gemspec
  Gemfile
  Rakefile
  lib/
    my_sparkline.rb
    my_sparkline/
      version.rb
      extension.rb
  native/
    sparkline/
      Cargo.toml
      src/
        lib.rs
  test/
    test_helper.rb
    extension_test.rb
  README.md
```

The Ruby side lives under `lib/` like any other gem. The Rust crate
lives under `native/<name>/` with its `Cargo.toml` and source. The
gemspec lists both trees in `files` so `gem install` pulls the Rust
source onto the consumer's machine where `rake plushie:build` can
reach it.

### Gemspec

```ruby
Gem::Specification.new do |spec|
  spec.name    = "my_sparkline"
  spec.version = MySparkline::VERSION
  spec.files   = Dir[
    "lib/**/*.rb",
    "native/sparkline/Cargo.toml",
    "native/sparkline/src/**/*.rs",
    "README.md"
  ]

  spec.required_ruby_version = ">= 3.2"
  spec.add_dependency "plushie", "~> 0.6"
end
```

No `extensions` entry and no build-time hook: compilation is the
consumer's responsibility via `rake plushie:build`. That keeps
`gem install` fast and side-effect-free, and avoids shipping a
prebuilt `.so` that would have to match every consumer's platform.

### Consumer wiring

The downstream app wires the gem into its own build configuration:

```ruby
# Rakefile
require "plushie"
require "my_sparkline"

Plushie.configure do |config|
  config.widgets    = [MySparkline::Extension]
  config.build_name = "my-app-plushie"
end

require "plushie/rake"

task default: :test
```

The widget's `rust_crate` path is relative to the consumer's project
root, so the gem publishes a helper that resolves it against the
gem's load path:

```ruby
module MySparkline
  class Extension
    include Plushie::Widget

    widget :sparkline, kind: :native_widget
    rust_crate File.expand_path("../../../native/sparkline", __FILE__)
    rust_constructor "sparkline::Extension::new()"

    prop :data, :any, default: []
  end
end
```

`rake plushie:build` then picks up the crate from the gem's install
location and builds a renderer binary that includes it.

### Prebuilt renderers

An app with a native widget does not have to build from source on
every developer's machine. Publishing a prebuilt renderer binary to
GitHub releases lets consumers skip cargo entirely:

```bash
bundle exec rake plushie:download            # missing only
bundle exec rake 'plushie:download[force]'   # re-download
```

`plushie:download` verifies a `.sha256` sidecar before installing
the binary. The release name and version are pinned in the
consuming app's gemspec via the plushie dependency. See the
[Rake Tasks reference](rake-tasks.md#plushiedownload) for the full
download surface and the [Versioning reference](versioning.md) for
how renderer versions are pinned.

Either path works:

- **Build from source on install** for apps under active Rust
  development or with many contributors running `cargo` already.
- **Publish a binary per release** for apps whose users don't have a
  Rust toolchain, at the cost of managing a release pipeline for
  every supported platform.

## A complete worked example

The `sparkline-dashboard` project in `plushie-demos/ruby/` is the
canonical end-to-end example: it ships a native sparkline widget
alongside a dashboard app that drives it with a timer subscription.
The layout mirrors the gem pattern above, with the widget crate
under `native/sparkline/` and the Ruby declaration in
`lib/sparkline_extension.rb`. `rake plushie:build` compiles a
custom renderer binary; `ruby lib/dashboard.rb` runs the app
against it.

## See also

- [Custom Widgets reference](custom-widgets.md) - the shared DSL
  covering pure-Ruby widgets and the Ruby half of native widgets
- [Configuration reference](configuration.md) - `config.widgets`,
  `build_name`, `widget_config`, and the rest of the build and
  runtime surface
- [Rake Tasks reference](rake-tasks.md) - `plushie:build`,
  `plushie:download`, and `cargo-plushie` resolution
- [Wire Protocol reference](wire-protocol.md) - the message frames
  that carry widget props, commands, and events between Ruby and
  the renderer
- [Versioning reference](versioning.md) - how the gem version pins
  `PLUSHIE_RUST_VERSION` and the widget SDK
