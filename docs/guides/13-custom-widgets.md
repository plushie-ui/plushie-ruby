# Custom Widgets

As the pad has grown, the view has sprouted helpers: `sidebar`,
`editor_pane`, `preview_pane`, `toolbar`, `event_log_pane`. Private
methods are fine for view composition, but they cannot carry their
own state, emit semantic events back to the app, or be lifted out
into another app. For that you need **custom widgets**: reusable
bundles of view, state, and events.

Plushie Ruby ships one DSL for every flavour of custom widget. The
same declarations (`widget`, `prop`, `state`, `event`, `children`)
cover declarative leaf widgets, containers, stateful composites,
canvas-backed visuals, and native Rust-backed widgets. This
chapter walks through the pure Ruby side, then builds a small line
numbers widget into the pad. Native widgets get a brief section
with a pointer to the native extension reference.

Reach for a custom widget when the view fragment needs state,
emits events, or gets reused. A private method is still the right
call when none of those apply.

## Two entry points

Plushie offers two ways to declare a widget. Both use the same DSL
and produce the same runtime behaviour. Pick whichever suits the
widget's shape.

`Plushie::Widget.define(:type_name) { ... }` returns a fully formed
class. This is the factory form, analogous to `Data.define`. Use it
for leaf widgets and containers whose job is just a prop-to-wire
mapping:

```ruby
Badge = Plushie::Widget.define(:badge) do
  children :none
  positional :label
  prop :label, :string
  prop :tone, type: :string, doc: "One of :info, :warn, :error."
  default_a11y role: :status, label_from: :label
end

Badge.new("status", "All systems go", tone: "info")
```

`include Plushie::Widget` with a `widget :type_name` call opens the
same DSL on an ordinary class. Use it when the widget needs class
methods, a `view`, event handling, or internal state:

```ruby
class StarRating
  include Plushie::Widget

  widget :star_rating
  prop :rating, :number, default: 0
  state :hover, default: nil
  event :select

  def self.init = {hover: nil}
  def self.view(id, props, state) = ...
  def self.handle_event(event, state) = ...
end
```

Both forms generate the same constructor (`new(id, *positional,
**opts)`), the same chainable `set_*` setters, the same `#build`
method, and the same wire behaviour. The only difference is where
the declarations live.

## The widget DSL

The following declarations are available inside either entry point.

### `widget(type_name, **opts)`

Declares the wire type name. Required. The type name appears on
every node the widget produces and, for widgets that declare
events, in the `type:` field of their events as `[widget_type,
event_name]`.

Options:

| Option | Values | Description |
|---|---|---|
| `:kind` | `:widget`, `:native_widget` | Defaults to `:widget`. Set to `:native_widget` for Rust-backed widgets. |
| `:container` | `true`, `:none`, `:single`, `:many`, Integer | Shorthand for a `children(...)` call. `true` is equivalent to `:many`. |

For `Widget.define`, the first argument is the type name:
`Widget.define(:my_widget) { ... }`.

### `children(mode)`

Declares how many children the widget accepts.

| Mode | Meaning |
|---|---|
| `:none` | Leaf widget, no children. Block form raises. |
| `:single` | Exactly one child. More raises at build time. |
| `:many` | Any number of children. |
| Integer | Exactly `N` children. |

Container widgets auto-generate a `push(child)` setter, which is
what the block DSL uses to collect children inside the
`new("id") do ... end` form.

### `positional(name, default: ...)`

Declares a constructor argument that follows `id`. Call order
determines argument order. Omitting `default:` makes the argument
required. The positional name must also appear as a `prop`.

```ruby
Button = Plushie::Widget.define(:button) do
  positional :label, default: nil
  prop :label, :style
end

Button.new("save", "Save")                   # positional
Button.new("save", label: "Save")            # keyword
Button.new("save", "Save", style: :primary)  # both
```

### `prop`

Declares one or more properties. Three forms:

```ruby
prop :label, :width, :height                 # simple: names only
prop :value, :number, default: 0             # typed: name + type + default
prop :label, type: :string, doc: "..."       # rich: explicit metadata
```

Known type symbols: `:number`, `:string`, `:boolean`, `:color`,
`:length`, `:padding`, `:alignment`, `:style`, `:font`, `:atom`,
`:map`, `:any`. A typed prop validates inputs at construction; a
non-matching value raises `ArgumentError`.

`:id`, `:type`, and `:children` are reserved. `:a11y` and
`:event_rate` are auto-wired on every widget and may be listed as
no-op declarations for discoverability.

### `event(name, fields: nil)`

Declares an event the widget can emit. Declared events surface as
`Event::Widget` values with `type: [widget_type, name]`, and
declared field shapes are validated at emit time.

```ruby
event :click                                  # no payload
event :change, fields: {hue: Numeric,         # required fields
                        saturation: Numeric}
event :change, fields: {
  hue: Numeric,
  modifier: {type: String, required: false}   # optional field
}
```

Emitting a scalar (not a hash) wraps it as `{value: scalar}` before
validation.

### `state(name, default: ...)`

Declares an internal state field. Declaring any state field, any
event, or defining `self.init` or `self.handle_event` makes the
widget stateful: the runtime manages a per-instance state hash in
its registry, threads it through each render, and routes events
through `handle_event` before the app sees them.

Multiple `state` calls are additive. The auto-generated `init`
returns a hash built from the declared fields and defaults, which
you can override by defining `self.init` explicitly.

### `cache_key(proc)`

Declares a cache key function for view-level caching. When the proc
returns the same value as the previous render, the widget's `view`
is skipped and the previous normalised output is reused.

```ruby
cache_key ->(props, state) { [props[:version], state[:zoom]] }
```

The proc receives `(props, state)`; equality (`==`) drives the
comparison.

### `default_a11y(role:, label_from:)`

Declares a default accessibility role for the widget type and,
optionally, a prop name to derive the accessible label from. These
defaults merge into the widget's `a11y` prop at build time; any
`a11y` explicitly passed by the caller wins per field.

```ruby
default_a11y role: :button, label_from: :label
```

See the [Accessibility reference](../reference/accessibility.md)
for the full `a11y` schema.

## Widget tiers

The same DSL covers a spectrum. The runtime picks behaviour from
what's declared:

| Tier | Declarations | Behaviour |
|---|---|---|
| Leaf | `widget`, `prop` | Plain wire node |
| Container | `children :single`, `:many`, `N` | Leaf plus child validation and a `push` setter |
| Stateless composite | `def self.view(id, props)` | View returns a node tree; events pass through |
| Stateful | `state`, `event`, or `handle_event` | Runtime owns per-instance state; events route through `handle_event` first |
| Full lifecycle | `self.subscribe(props, state)` too | Stateful plus widget-scoped subscriptions |

Stateful widgets must define `self.view(id, props, state)`. The
DSL raises at finalisation otherwise.

## Declarative widgets

The smallest custom widget is a declarative leaf: a type name, a
positional argument, a prop or two, and a default accessibility
role. No `view`, no state, no events.

```ruby
Badge = Plushie::Widget.define(:badge) do
  children :none
  positional :label
  prop :label, :string
  prop :tone, type: :string, doc: "One of :info, :warn, :error."
  default_a11y role: :status, label_from: :label
end
```

`Badge.new("status", "All systems go", tone: "info").build` returns
a `Plushie::Node` with `type: "badge"` and the prop values attached.
The renderer-side badge widget takes over from there. This form is
how every built-in widget in `Plushie::Widget::*` is declared; they
are `Widget.define` calls with per-widget prop lists.

## Behavioral widgets

When the widget needs its own `view`, state, or event transformation,
include `Plushie::Widget` on a class and declare methods alongside
the DSL. The shipped `examples/widgets/star_rating.rb` is the
canonical shape:

```ruby
class StarRating
  include Plushie::Widget

  widget :star_rating
  prop :rating, :number, default: 0
  prop :readonly, :boolean, default: false
  state :hover, default: nil
  event :select

  STAR_COUNT = 5

  def self.init = {hover: nil}

  def self.view(id, props, state)
    include Plushie::UI
    rating = props[:rating] || 0
    display = state[:hover] || rating

    canvas(id, width: 150, height: 30, alt: "Star rating",
      role: "radiogroup") do
      layer("stars") do
        STAR_COUNT.times do |i|
          canvas_group("star-#{i}",
            x: i * 30 + 15, y: 15,
            on_click: true, on_hover: true,
            a11y: {role: :radio, selected: rating >= i + 1}) do
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
      n ? [:update_state, {hover: n + 1}] : [:consumed, state]

    in Event::Widget[type: :canvas_element_leave]
      [:update_state, {hover: nil}]

    else
      [:consumed, state]
    end
  end
end
```

The app places this widget the same as any built-in:

```ruby
def view(model)
  window("main", title: "Rate") do
    StarRating.new("rating", rating: model.rating).build
  end
end

def update(model, event)
  case event
  in Event::Widget[type: [:star_rating, :select], value: {value: n}]
    model.with(rating: n)
  else
    model
  end
end
```

A `Widget.new("id", ...).build` call inside a view block both
returns the node and pushes it onto the surrounding DSL context, so
the call site reads like any other widget. Outside a block,
`#build` just returns the node.

## `handle_event` action tuples

`self.handle_event(event, state)` receives every event whose scope
chain includes the widget, before the app's `update` sees it. The
return value tells the runtime what to do:

| Return | Effect |
|---|---|
| `[:ignored, state]` | Pass the event through to the next handler in the scope chain, then to the app |
| `[:consumed, state]` | Suppress the event entirely |
| `[:update_state, state]` | Update state; suppress the event |
| `[:emit, kind, data]` | Replace the event with `Event::Widget[type: [widget_type, kind], value: data]` and continue; state unchanged |
| `[:emit, kind, data, state]` | Same, plus update state |

When the widget declares events, omitting `handle_event` makes every
incoming event `:consumed` by default. When no events are declared,
the default is `:ignored`. Either default can be overridden by
defining `handle_event` explicitly.

Scalar `data` values are wrapped automatically: returning
`[:emit, :select, 3]` produces an event with `value: {value: 3}`.
Return a hash to keep field names:
`[:emit, :change, {hue: h, saturation: s}]` produces
`value: {hue: h, saturation: s}`.

If the widget declared `event :name, fields: {...}`, the hash is
validated against the declared fields before dispatch. Missing
required fields and class mismatches raise at emit time.

## Event type matching

Declared events carry their widget's type in a two-element form:

```ruby
case event
in Event::Widget[type: [:star_rating, :select], value: {value: rating}]
  model.with(rating: rating)

in Event::Widget[type: [:color_picker_widget, :change],
    value: {hue:, saturation:, value: v}]
  model.with(color: Color.hsv(hue, saturation, v))
end
```

Built-in widget events (`:click`, `:input`, ...) use a bare symbol
for `type:`, so they never collide with custom widget events. See
the [Events reference](../reference/events.md) for the full matrix.

## State lifecycle

State follows tree presence. On first appearance it is initialised
from `self.init` (or from the declared state defaults). Each
`[:update_state, new_state]` or
`[:emit, kind, data, new_state]` return replaces it. The runtime
calls `self.view(id, props, state)` with the current state each
render, so views are pure functions of props and state. When the
widget leaves the tree, its state is cleaned up.

State is keyed by the widget's full scoped ID
(`window_id#path/to/widget`). Moving a widget between containers
changes its scoped ID and resets its state. There is no mount or
unmount callback: emit events or return commands through the app's
update cycle for any side effect that crosses the widget boundary.

## Canvas-backed widgets

Any behavioral widget can return a canvas subtree from its `view`.
That gives you drawing primitives (paths, shapes, text, transforms),
per-shape interactivity, and accessibility through
`canvas_interactive` and `canvas_group`. `examples/widgets/` ships
three full implementations:

- `star_rating.rb`: five-star radio group, hover preview, keyboard
  selection, emits `:select` with the chosen value.
- `theme_toggle.rb`: animated switch with a rotating face on the
  thumb, driven by a widget-scoped 60 Hz timer subscription.
- `color_picker_widget.rb`: HSV ring and saturation/value square,
  pointer drag plus focusable cursors with arrow-key adjustment,
  emits `:change` with a typed hue/saturation/value payload.

The shape is always the same: `include Plushie::Widget`,
`widget :type_name`, declare props and state, return a
`canvas(id, width:, height:) do ... end` tree from `view`, match
canvas events in `handle_event`.

`Plushie::CanvasWidget` is a separate mixin that predates the
unified DSL. It remains supported (swap `include Plushie::Widget`
for `include Plushie::CanvasWidget` and `widget :name` for
`canvas_widget :name`) with the same action tuples and the same
lifecycle. New widgets can use either mixin. The unified
`Plushie::Widget` DSL covers the same ground and keeps the pure
Ruby and native paths in one place.

See the [Canvas guide](12-canvas.md) for the drawing DSL and the
[Canvas reference](../reference/canvas.md) for every shape, prop,
and interactive option.

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
    [:update_state,
      state.merge(progress: step_toward(state[:progress], state[:target]))]
  end
end
```

Each subscription's tag is namespaced per widget instance before
being sent to the renderer, so two instances of the same widget
never collide. When a timer fires, the runtime strips the
namespace, finds the widget by scoped ID, and dispatches the timer
event through `handle_event` with the original inner tag. The
timer never reaches the app's `update`.

The subscription list is recomputed each render and diffed against
the previous list. Returning a new list starts subscriptions;
returning `[]` cancels them. See the
[Subscriptions reference](../reference/subscriptions.md) for the
full diffing lifecycle.

## Registering widgets with the app

Declarative and behavioral widget classes work without any
registration step: `MyWidget.new("id", ...).build` inside a `view`
block is all that's needed. The `config.widgets` list exists
specifically for native (Rust-backed) widgets, where the build
pipeline needs to know which crates to compile into the renderer.

```ruby
Plushie.configure do |config|
  config.widgets = [Sparkline, Chart]
end
```

Non-native classes in the list are skipped with a warning, so a
mixed list is safe. The build tooling filters to the native ones.
See the [Configuration reference](../reference/configuration.md)
for the full set of configurable attributes.

For apps that want a house-styled version of a built-in widget
everywhere without rewriting every call site, wrap a widget class
in a `Plushie::WidgetSet`:

```ruby
MaterialButton = Plushie::Widget.define(:button) do
  children :none
  positional :label, default: nil
  prop :label, :style, :disabled, :ripple_color
  default_a11y role: :button, label_from: :label
end

MaterialUI = Plushie::WidgetSet.create(button: MaterialButton)

class MyApp
  include Plushie::App
  include MaterialUI  # overrides button(...) in this app's views
end
```

The override class must expose the same constructor shape as the
built-in and a `#build` method returning a node. `Widget.define`
satisfies both.

## Native widgets

When pure Ruby composition and canvas are not enough (custom GPU
rendering, platform-specific input like IME composition or tablet
pressure, heavy per-frame computation that would be slow in Ruby),
you can back a widget with a Rust crate. The Ruby side declares
the interface with `kind: :native_widget`, points at the crate
with `rust_crate` and `rust_constructor`, and lists props,
events, and commands; the Rust side implements rendering inside
the renderer:

```ruby
class Sparkline
  include Plushie::Widget

  widget :sparkline, kind: :native_widget

  rust_crate       "native/sparkline"
  rust_constructor "sparkline::SparklineExtension::new()"

  prop :data,  :any,   default: []
  prop :color, :color, default: :blue

  event :point_clicked, fields: {index: Integer, value: Numeric}
end
```

`rake plushie:build` picks up the widget class from
`config.widgets`, generates a virtual renderer workspace that
pulls the widget crate in as a path dependency, and produces a
custom renderer binary. Pure-Ruby widgets hot-reload; native
widgets require a full renderer rebuild. Start pure Ruby; reach
for native only when the widget genuinely cannot be expressed
with canvas and composition. The full story is in the
[Native Extensions reference](../reference/native-extension.md).

## Applying it: a LineNumbers widget for the pad

Back to the pad. The editor pane is a single `text_editor` that
fills the middle of the window. A common editor affordance is a
line-number gutter down the left edge. The numbers should:

- update as the source grows and shrinks,
- render in monospace so the digits line up with the editor,
- align to the right so the counts stack cleanly,
- not get in the way of the editor's events.

There is no `line_numbers` built-in. Good excuse to build one.

### Step 1: declare the widget

A single prop (`source`) and no state. The widget is stateless: it
does not emit events and it does not care about hovers or focus.
That means a plain stateless composite with `self.view(id, props)`.

Create `lib/plushie_pad/widgets/line_numbers.rb`:

```ruby
require "plushie"

class PlushiePad::LineNumbers
  include Plushie::Widget

  widget :line_numbers

  prop :source, :string, default: ""
  prop :width, :number, default: 40

  def self.view(id, props)
    include Plushie::UI

    source = props[:source] || ""
    count = source.lines.length
    count = 1 if count.zero?

    container(id,
      width: props[:width],
      height: :fill,
      padding: [8, 4]) do
      column("lines", spacing: 0) do
        count.times do |i|
          text("line-#{i}", (i + 1).to_s,
            size: 13,
            font: :monospace)
        end
      end
    end
  end
end
```

The widget has no state and no `handle_event`, so every event from
widgets inside it (none, in this case) would fall through to the
app. `self.view(id, props)` gets the widget's scoped ID as `id`;
the runtime takes care of applying it to the returned node.

### Step 2: wire it into the editor pane

In `app.rb`, require the widget file and swap the editor pane for a
row that pairs the gutter with the text editor:

```ruby
require_relative "widgets/line_numbers"

def editor_pane(model)
  row("editor-row",
    width: [:fill_portion, 2],
    height: :fill,
    spacing: 0) do
    PlushiePad::LineNumbers.new("line-numbers",
      source: model.source,
      width: 48).build
    text_editor("editor", model.source,
      width: :fill,
      height: :fill,
      highlight_syntax: "ruby",
      font: :monospace)
  end
end
```

The block DSL collects the widget's node and the text editor as
siblings in the row. The existing input handler for `"editor"`
keeps working untouched; the gutter is pure display.

### Step 3: right-align the digits

Restart the pad. The gutter appears, numbering lines from one and
updating as the editor's content changes. The minimal version
looks fine for short files, but single-digit numbers sit awkwardly
next to three-digit ones once the buffer grows. Right-align the
digits by adding `:align_x` and padding each number to the widest
expected width:

```ruby
def self.view(id, props)
  include Plushie::UI

  source = props[:source] || ""
  count = [source.lines.length, 1].max
  pad_width = count.to_s.length

  container(id,
    width: props[:width],
    height: :fill,
    padding: [8, 4]) do
    column("lines", spacing: 0, align_x: :end) do
      count.times do |i|
        text("line-#{i}", (i + 1).to_s.rjust(pad_width),
          size: 13,
          font: :monospace)
      end
    end
  end
end
```

`rjust` pads short numbers with spaces so the digits align under
the largest count. Monospace at a matched size keeps the rows
registered against the editor below. The widget is now a good fit
for lifting out of the pad into a diff viewer or a log reader.

## Exercise: a Toast widget

Build a `Toast` widget that animates itself off-screen after a
delay:

- `prop :message, :string` for the text.
- `prop :duration_ms, :number, default: 3000` for how long it
  stays up.
- `state :fade, default: 1.0` for the current opacity.
- `state :elapsed, default: 0` for the time spent on screen.
- `self.subscribe(_props, state)` returns
  `[Plushie::Subscription.every(16, :tick)]` while `state[:fade] > 0`,
  otherwise `[]`.
- `self.handle_event` advances `elapsed` on each `:tick`, computes
  `fade` as `1.0` during the hold window and a linear fade after,
  and returns `[:update_state, new_state]`.
- `self.view` renders a container with the message, using the
  current `fade` as an opacity override in the widget's `style:` prop
  so the toast dims out before disappearing.
- Declare `event :dismissed` and emit it once `fade` reaches zero,
  so the parent app knows to remove the toast from its model.

If the timer keeps running after fade reaches zero, the
subscription list did not update correctly: check that the
`self.subscribe` branch returns `[]` once the fade is done, and
that `handle_event` actually writes the new state.

## See also

- [Custom Widgets reference](../reference/custom-widgets.md), the
  full DSL surface, tier matrix, action tuple table, and
  `WidgetSet` override semantics
- [Native Extensions reference](../reference/native-extension.md),
  the Rust side of native widgets, `rake plushie:build`, and gem
  distribution
- [Canvas reference](../reference/canvas.md), the drawing DSL that
  canvas-backed widgets build on
- [Events reference](../reference/events.md), the `Event::Widget`
  shape including `[widget_type, event_name]` matching
- [Subscriptions reference](../reference/subscriptions.md), the
  per-instance subscription lifecycle used by widget-scoped timers

## Next chapter

[State Management](14-state-management.md)
