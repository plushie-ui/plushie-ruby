# Custom Widgets

Plushie has two kinds of custom widgets: **pure Ruby** (compose
existing widgets, draw with canvas, or hold per-instance state) and
**native** (Rust-backed, for custom GPU rendering or specialised
input). Both go through the same DSL in `Plushie::Widget`, with two
entry points: `Widget.define(:name) { ... }` for declarative leaf and
container widgets, and `include Plushie::Widget` for classes that need
their own methods, `view`, `handle_event`, or `state`.

Pure Ruby is the default. Reach for a native widget only when drawing
or input behaviour that the built-in widgets and canvas can't express.

## Two entry points

`Plushie::Widget.define(type_name) { ... }` returns a fully formed
class, mirroring the `Data.define` convention. Use it for leaf widgets
and containers that are just a prop-to-wire mapping.

```ruby
Button = Plushie::Widget.define(:button) do
  children :none
  positional :label, default: nil
  prop :label, :width, :height, :padding, :style, :disabled
  default_a11y role: :button, label_from: :label
end
```

Every built-in widget in `Plushie::Widget::*` is declared this way.

`include Plushie::Widget` opens the same DSL on an ordinary class. Use
it when you need class methods, `view`, `handle_event`, `state`, or
`subscribe`:

```ruby
class StarRating
  include Plushie::Widget

  widget :star_rating
  prop :rating, :number, default: 0
  state :hover, default: nil
  event :select

  def self.init = { hover: nil }
  def self.view(id, props, state) = ...
  def self.handle_event(event, state) = ...
end
```

Both paths share the same generated constructor, setters, `build`
method, and runtime integration. The only difference is where the
declarations live.

## The widget DSL

The following declarations are available inside a `Widget.define` block
or inside a class that includes `Plushie::Widget`.

### `widget(type_name, **opts)`

Declares the wire type name. Required. The type name appears on every
node produced by the widget and, for widgets that declare events, in
the `type:` field of their events as `[widget_type, event_name]`.

| Option | Type | Description |
|---|---|---|
| `:kind` | `:widget` or `:native_widget` | Defaults to `:widget`. Set to `:native_widget` for Rust-backed widgets. |
| `:container` | `true`, `:none`, `:single`, `:many`, `Integer` | Shorthand for `children(...)`. `true` is equivalent to `:many`. |

For `Widget.define`, the first argument is the type name:
`Widget.define(:my_widget) { ... }` sets it implicitly.

### `children(mode)`

Declares how many children the widget accepts.

| Mode | Meaning |
|---|---|
| `:none` | Leaf widget, no children |
| `:single` | Exactly one child; raises at build if the caller passes more |
| `:many` | Any number of children |
| `Integer` | Exactly `N` children; raises at build if the count differs |

Container widgets auto-generate a `push(child)` setter alongside the
other `set_*` methods.

### `positional(name, default: ...)`

Declares a constructor argument that follows `id`. Call order
determines argument order. Omitting `default:` makes the argument
required; passing `default: nil` (or any other value) makes it
optional. Every positional name must also be declared as a `prop`.

```ruby
Button = Plushie::Widget.define(:button) do
  positional :label, default: nil
  prop :label, :style
end

Button.new("save", "Save")                # label comes from positional
Button.new("save", label: "Save")         # label comes from keyword
Button.new("save", "Save", style: :primary)
```

### `prop`

Declares one or more properties. Three forms:

```ruby
prop :label, :width, :height            # simple: name list only
prop :value, :number, default: 0        # typed: name + known type + default
prop :label, type: :string, doc: "..."  # rich: explicit keyword metadata
```

Known type symbols: `:number`, `:string`, `:boolean`, `:color`,
`:length`, `:padding`, `:alignment`, `:style`, `:font`, `:atom`,
`:map`, `:any`. Types in the simple form are informational and are
used by the generated setter to validate values at assignment time.

Structural names (`:id`, `:type`, `:children`) are reserved and raise.
Auto-wired names (`:a11y`, `:event_rate`) are accepted as no-op
declarations for discoverability; they are wired on every widget
regardless.

### `event(name, fields: nil)`

Declares an event the widget can emit. A declaration is what makes the
widget opaque to the surrounding app: events it declares are
translated to `Event::Widget` values with `type: [widget_type, name]`;
events the widget does not declare pass through unchanged.

```ruby
event :click                                    # no payload
event :change, fields: { hue: Numeric,          # required fields
                         saturation: Numeric }
event :change, fields: {
  hue: Numeric,
  modifier: { type: String, required: false }   # optional field
}
```

Fields are validated at emit time. Missing required fields raise, as
does a value whose class does not match the declared class. Emit a
scalar (single-value event) by returning `[:emit, :name, scalar_value]`
from `handle_event`; the runtime wraps it as `{ value: scalar_value }`
before validation.

### `state(name, default: ...)`

Declares an internal state field. Declaring any state field makes the
widget stateful: the runtime manages a per-instance state hash in its
registry, threads it through each render, and routes events through
`handle_event` before the app sees them.

Multiple `state` calls are additive. Each field has its own default.
The auto-generated `init` method returns a hash built from the declared
fields and defaults, which callers can override by defining
`self.init`.

### `cache_key(proc)`

Declares a cache key function for view-level caching. When the proc
returns the same value as the previous render, the widget's view is
skipped and the previous normalised output is reused.

```ruby
cache_key ->(props, state) { [props[:version], state[:zoom]] }
```

The proc receives `(props, state)`. Return any value; equality
(`==`) is used for the comparison.

### `default_a11y(role:, label_from:)`

Declares a default accessibility role for the widget and, optionally,
a prop name to derive the accessible label from. These defaults are
merged into the widget's `a11y` prop at build time; any `a11y`
explicitly passed by the caller wins per field.

```ruby
Plushie::Widget.define(:button) do
  positional :label
  prop :label
  default_a11y role: :button, label_from: :label
end
```

See the [Accessibility reference](accessibility.md) for the full
`a11y` schema.

## Widget tiers

The same DSL covers a spectrum. The runtime picks behaviour from
what's declared:

| Tier | Declarations | Behaviour |
|---|---|---|
| Leaf | `widget`, `prop` (no state, no events, no view) | Emits a plain wire node. |
| Container | `children :single` \| `:many` \| `N` | Leaf plus validation and a `push` setter. |
| Stateless composite | `def self.view(id, props)` | View returns a node tree built from other widgets. Events pass through. |
| Stateful | `state` or `event` or `handle_event` or `init` | Runtime owns per-instance state; events route through `handle_event` first. |
| Full lifecycle | `subscribe(props, state)` too | Stateful plus widget-scoped subscriptions. |

A widget is treated as stateful if it declares any state field, any
event, or defines `init` or `handle_event`. Stateful widgets must also
define `self.view(id, props, state)`; the DSL raises at finalisation
otherwise.

## Declarative example

A leaf widget with a positional argument, a typed prop, and a default
accessibility role:

```ruby
Badge = Plushie::Widget.define(:badge) do
  children :none
  positional :label
  prop :label, :string
  prop :tone, type: :string, doc: "One of :info, :warn, :error."
  default_a11y role: :status, label_from: :label
end

# Usage:
Badge.new("status", "All systems go", tone: "info")
```

Declaring a prop with a `:string` type validates inputs at
construction: passing a non-string raises `ArgumentError`.

## Behavioral example

A stateful widget that owns hover state, renders itself with canvas
shapes, and emits a typed event:

```ruby
class StarRating
  include Plushie::Widget

  widget :star_rating
  prop :rating, :number, default: 0
  prop :readonly, :boolean, default: false
  state :hover, default: nil
  event :select

  STAR_COUNT = 5

  def self.init = { hover: nil }

  def self.view(id, props, state)
    include Plushie::UI

    rating = props[:rating] || 0
    display = state[:hover] || rating

    canvas(id, width: 150, height: 30, alt: "Star rating") do
      layer("stars") do
        STAR_COUNT.times do |i|
          canvas_group("star-#{i}",
            x: i * 30 + 15, y: 15,
            on_click: true, on_hover: true,
            a11y: { role: :radio, selected: rating >= i + 1 }) do
            canvas_path(STAR_PATH,
              fill: (i < display) ? "#f59e0b" : "#e5e7eb")
          end
        end
      end
    end
  end

  def self.handle_event(event, state)
    case event
    in Event::Widget[type: :canvas_element_click, data:]
      n = star_index(data)
      n ? [:emit, :select, n + 1] : [:consumed, state]

    in Event::Widget[type: :canvas_element_enter, data:]
      n = star_index(data)
      n ? [:update_state, { hover: n + 1 }] : [:consumed, state]

    in Event::Widget[type: :canvas_element_leave]
      [:update_state, { hover: nil }]

    else
      [:consumed, state]
    end
  end

  def self.star_index(data)
    id = data && (data[:element_id] || data["element_id"])
    id&.start_with?("star-") ? id.delete_prefix("star-").to_i : nil
  end
end
```

The app places this widget like any built-in:

```ruby
def view(model)
  window("main", title: "Rate") do
    StarRating.new("rating", rating: model.rating).build
  end
end

def update(model, event)
  case event
  in Event::Widget[type: [:star_rating, :select], value: n]
    model.with(rating: n)
  else
    model
  end
end
```

## handle_event action tuples

`self.handle_event(event, state)` receives every event whose scope
chain includes the widget, before the app's `update` sees it. The
return value tells the runtime what to do:

| Return | Effect |
|---|---|
| `[:ignored, state]` | Pass the event through to the next handler in the scope chain, then to the app |
| `[:consumed, state]` | Suppress the event entirely |
| `[:update_state, state]` | Update state; suppress the event |
| `[:emit, kind, data]` | Replace the event with `Event::Widget[type: [widget_type, kind], value: data]` and continue down the chain; state unchanged |
| `[:emit, kind, data, state]` | Same, plus update state |

When the widget declares events, omitting `handle_event` makes every
incoming event `:consumed` by default. When no events are declared,
the default is `:ignored`. Either default can be overridden by
defining `handle_event` explicitly.

Scalar `data` values are wrapped automatically: returning
`[:emit, :select, 3]` produces an event with `value: { value: 3 }`.
Return a hash directly to keep field names: `[:emit, :change,
{ hue: h, saturation: s }]` produces `value: { hue: h, saturation: s }`.

If the widget declared `event :name, fields: {...}`, the hash is
validated against the declared fields before dispatch. Missing
required fields and type mismatches raise at emit time.

## Event type matching

Declared events carry their widget's type in a two-element form:

```ruby
case event
in Event::Widget[type: [:star_rating, :select], value: rating]
  model.with(rating: rating)

in Event::Widget[type: [:color_picker_widget, :change], value: { hue:, saturation:, value: v }]
  model.with(color: Color.hsv(hue, saturation, v))
end
```

Built-in widget events (`:click`, `:input`, etc.) use a bare symbol
for `type:` so they don't collide with custom widgets. See the
[Events reference](events.md) for the full matrix.

## State lifecycle

State follows tree presence:

- **First appearance:** state is initialised from `self.init` (or the
  default hash derived from declared `state` fields).
- **Update:** `[:update_state, new_state]` or `[:emit, kind, data,
  new_state]` from `handle_event` replaces the state.
- **Re-render:** the runtime calls `self.view(id, props, state)` with
  the current state on each update cycle, so views are pure functions
  of props and state.
- **Disappearance:** when the widget leaves the tree, its state is
  cleaned up from the registry.

State is keyed by the widget's full scoped ID (`window_id#path`).
Moving a widget between containers changes its scoped ID and resets
its state, same as the built-in stateful widgets.

There is no mount or unmount callback. Emit events or return commands
through the app's update cycle for any side effect that crosses
the widget boundary.

## Widget-scoped subscriptions

A widget can declare `self.subscribe(props, state)` to run
subscriptions while it is mounted:

```ruby
def self.subscribe(_props, state)
  if state[:progress] != state[:target]
    [Plushie::Subscription.every(16, :animate)]
  else
    []
  end
end

def self.handle_event(event, state)
  case event
  in Event::Timer[tag: :animate]
    [:update_state, state.merge(progress: approach(state[:progress], state[:target]))]
  ...
  end
end
```

Each subscription's tag is namespaced per widget instance before
being sent to the renderer, so two instances of the same widget never
collide. When a timer fires, the runtime strips the namespace, finds
the widget by scoped ID, and dispatches the timer event through
`handle_event` with the original inner tag (`:animate` in the example).
The timer never reaches the app's `update`.

The subscription list is diffed against the previous render: starting
to return a subscription starts it; returning `[]` cancels it. See
the [Subscriptions reference](subscriptions.md) for the diffing
lifecycle.

## Canvas widgets

`Plushie::CanvasWidget` is a separate mixin for widgets that render as
canvas shapes and participate in canvas-specific event dispatch. It
predates the unified `Widget` DSL; new code can render canvas shapes
from any stateful `Widget` (the `StarRating` example above does
exactly that). `CanvasWidget` remains supported for the same behaviour
with a canvas-flavoured entry point.

```ruby
class ToggleSwitch
  include Plushie::CanvasWidget

  canvas_widget :toggle_switch

  def self.init = { hover: false }

  def self.view(id, props, state)
    include Plushie::UI

    on = props[:on] || false
    canvas(id, width: 64, height: 32) do
      layer("track") do
        canvas_interactive("toggle",
          on_click: true, cursor: "pointer",
          a11y: { role: :switch, toggled: on }) do
          canvas_rect(0, 0, 64, 32, fill: on ? "#3b82f6" : "#d1d5db", radius: 16)
          canvas_circle(on ? 44 : 20, 16, 12, fill: "#ffffff")
        end
      end
    end
  end

  def self.handle_event(event, state)
    case event
    in Event::Widget[type: :click, id: "toggle"]
      [:emit, :toggle, !state[:hover], state]
    else
      [:ignored, state]
    end
  end
end
```

### Class methods

| Method | Signature | Required? |
|---|---|---|
| `canvas_widget(type_name)` | `Symbol` | Yes |
| `init` | `-> Hash` | No, defaults to `{}` |
| `view(id, props, state)` | `String, Hash, Hash -> Node` | Yes |
| `handle_event(event, state)` | `Event, Hash -> action` | No |
| `subscribe(props, state)` | `Hash, Hash -> [Subscription]` | No |

Action tuples returned from `handle_event` use the same shape as the
unified DSL: `[:ignored, state]`, `[:consumed, state]`,
`[:update_state, state]`, `[:emit, kind, data]`, and
`[:emit, kind, data, state]`.

### Placement

A canvas widget must be rendered inside a window. Placing one outside
any window raises during normalisation. Within a window, widget state
is keyed by the full scoped ID (`window_id#path`); moving a widget
between containers discards its state.

## WidgetSet overrides

`Plushie::WidgetSet.create` builds a module that re-exports
`Plushie::UI` but replaces named DSL methods with custom widget
classes. Use it when an app wants a material-flavoured button
everywhere without rewriting every call site.

```ruby
MaterialButton = Plushie::Widget.define(:button) do
  children :none
  positional :label, default: nil
  prop :label, :style, :disabled, :ripple_color
  default_a11y role: :button, label_from: :label
end

MaterialUI = Plushie::WidgetSet.create(
  button: MaterialButton
)

class MyApp
  include Plushie::App
  include MaterialUI  # overrides `button(...)` in the app's view block

  def view(_model)
    window("main") do
      button("save", "Save", ripple_color: "#1d4ed8")
    end
  end
end
```

Override classes must expose the same constructor shape as the
built-in widgets (`new(id, *args, **opts)`) and a `#build` method
returning a `Plushie::Node`. `Widget.define` satisfies both. Invalid
overrides (naming a method that `Plushie::UI` does not define) raise
at creation time.

Block-form DSLs (`button("save") do ... end`) work on overrides that
support children: the generated `push` setter is picked up
automatically. Widgets declared with `children :none` raise when
invoked with a block.

## Native widgets

A native widget is a Rust crate that implements drawing, layout, and
event handling inside the renderer. The Ruby side declares the
widget's interface (type, props, commands) and delegates rendering to
the Rust crate. The build pipeline wires the crate into the renderer
binary.

Use native widgets when you need:

- Custom GPU rendering beyond what `canvas` can express
- Platform-specific input (IME composition, tablet pressure, MIDI)
- Heavy per-frame computation that would be slow in Ruby

### Ruby side

```ruby
class Sparkline
  include Plushie::Widget

  widget :sparkline, kind: :native_widget

  rust_crate       "native/sparkline"
  rust_constructor "sparkline::SparklineExt::new()"

  prop :data,  :any, default: []
  prop :color, :color, default: :blue

  event :point_clicked, fields: { index: Integer, value: Numeric }

  command :reset
  command :set_range, min: :float, max: :float
end
```

`rust_crate` is the path to the crate relative to the project root.
`rust_constructor` is a Rust expression that the build tooling embeds
in the generated renderer binary. `command` declarations are
informational on the Ruby side; payloads are sent via
`Plushie::Command.widget_command(id, family, value)` (see the
[Commands reference](commands.md#widget-commands)).

The `Widget.define` form accepts the same declarations:

```ruby
Sparkline = Plushie::Widget.define(:sparkline, kind: :native_widget) do
  rust_crate       "native/sparkline"
  rust_constructor "sparkline::SparklineExt::new()"
  prop :data,  :any, default: []
  prop :color, :color, default: :blue
end
```

### Registration

The build pipeline finds native widget classes through
`Plushie.configuration.widgets` or the `PLUSHIE_WIDGETS` env var.

```ruby
Plushie.configure do |config|
  config.widgets    = [Sparkline, Chart]
  config.build_name = "my-dashboard-plushie"
end
```

Non-native classes in the list are skipped with a warning, so a mixed
list is safe. The env var is a comma-separated list of fully qualified
class names, resolved with `Object.const_get`:

```bash
PLUSHIE_WIDGETS=Sparkline,MyApp::Chart rake plushie:build
```

See the [Configuration reference](configuration.md) for the full set
of configurable attributes.

### Crate metadata

Every native widget crate must declare a metadata table in its own
`Cargo.toml`:

```toml
[package.metadata.plushie.widget]
type_name   = "sparkline"
constructor = "sparkline::SparklineExt::new()"
```

The build pipeline treats the crate as the source of truth for widget
metadata. `cargo plushie new-widget` scaffolds this correctly. The
Ruby side's `rust_crate` and `rust_constructor` still drive the
generated virtual app crate, but cargo-plushie cross-checks them
against the metadata table before the build proceeds; a mismatch aborts
the build.

### Build pipeline

`rake plushie:build` runs the pipeline:

1. Resolves configured widget classes and filters to the native ones.
2. Refuses any `rust_crate` path that escapes the project root.
3. Writes a virtual app crate under `_build/plushie-renderer-spec/`
   with each native crate listed as a path dependency.
4. Shells out to `cargo plushie build`, which generates the renderer
   workspace, runs `cargo build`, and locates the built binary.
5. Installs the binary to `_build/plushie/bin/`.

See the [Rake Tasks reference](rake-tasks.md) for build and download
task options. The renderer discovery chain then picks up the custom
binary from `_build/plushie/bin/` on the next `Plushie.run`.

### Sending commands

`Plushie::Command.widget_command(id, family, value)` delivers an
operation to a native widget on the renderer side, keyed by the
widget's scoped ID and a family name the crate recognises. Use
`Plushie::Command.widget_batch(commands)` to apply a group
atomically.

```ruby
def update(model, event)
  case event
  in Event::Widget[type: :click, id: "reset"]
    [model, Plushie::Command.widget_command("spark", :reset)]
  end
end
```

See the [Commands reference](commands.md#widget-commands) for the full
signature.

## Pure Ruby vs native

| Concern | Pure Ruby | Native |
|---|---|---|
| Language | Ruby only | Rust (widget) plus Ruby (binding) |
| Build tooling | None | `rake plushie:build` plus Rust toolchain |
| Works under WASM | Yes | No (WASM builds use built-in widgets only) |
| Event handling | `self.handle_event` in Ruby | In the Rust crate |
| Drawing primitives | Built-in widgets plus canvas | Arbitrary Rust rendering |
| Performance for heavy rendering | Limited by Ruby plus canvas | Native GPU throughput |
| Iteration speed | Fast; hot reload friendly | Requires a full renderer rebuild |

Start pure Ruby. Only reach for native when a profiler or a genuinely
uncoverable use case forces the move.

## See also

- [Built-in Widgets reference](built-in-widgets.md) - the standard
  catalog and the DSL that custom widgets slot into
- [Canvas reference](canvas.md) - the primary drawing surface for
  pure Ruby custom widgets
- [Events reference](events.md) - the `Event::Widget` type shape,
  including `[widget_type, event_name]` matching for custom widgets
- [Commands reference](commands.md) - `widget_command` and
  `widget_batch` for driving native widgets from the app
- [Configuration reference](configuration.md) - `config.widgets`,
  `build_name`, and the rest of the build configuration surface
