# Animation

Plushie has two animation layers. **Renderer-side descriptors**
(`Transition`, `Spring`, `Sequence`) are pure data placed directly
on animatable widget props. The renderer interpolates locally with
no wire traffic during the animation. **SDK-side tweens**
(`Animation::Tween`) interpolate in Ruby, driven by the
`on_animation_frame` subscription. Prefer renderer-side descriptors
for anything visual; reach for `Tween` only when the animating
value must live in your model.

All descriptors live in `Plushie::Animation`.

## Animating a widget prop

Renderer-side animation is declarative. Pass a descriptor as the
value of any animatable keyword arg and the renderer takes over:

```ruby
container("panel",
  max_width: Plushie::Animation::Transition.build(300, to: 200, easing: :ease_out)) do
  text("content", "Hello")
end
```

The descriptor crosses the wire once (inside the snapshot or patch
that introduced it), then the renderer handles frame-by-frame
interpolation. No subscription, no model state, no update cycles.
When `to:` changes on a subsequent render, the renderer starts a
new animation from the current interpolated value, not from the
beginning.

Drop the descriptor (pass a raw value instead) and the renderer
snaps to that value, cancelling any in-flight animation.

## Transitions

`Plushie::Animation::Transition`

Time-based animation toward a target value. Predictable and
coordinated: you know exactly when it finishes.

```ruby
# Positional duration, keyword target:
Plushie::Animation::Transition.build(300, to: 200)

# With easing and delay:
Plushie::Animation::Transition.build(300, to: 0.0, easing: :ease_out, delay: 100)

# Fade in from transparent on first appearance:
Plushie::Animation::Transition.build(200, to: 1.0, from: 0.0)

# Forever-looping pulse (see Looping below):
Plushie::Animation::Transition.loop(800, to: 0.4, from: 1.0)
```

### Options

| Option | Type | Default | Description |
|---|---|---|---|
| `to:` | number | required | Target value |
| `duration` | Integer (positional) | required | Duration in milliseconds |
| `easing:` | symbol | `:ease_in_out` | Easing curve (see catalogue) |
| `delay:` | Integer | `0` | Milliseconds before start |
| `from:` | number | `nil` | Starting value, applied on first appearance only |
| `repeat:` | Integer or `:forever` | `nil` | Repeat count |
| `auto_reverse:` | boolean | `false` | Reverse direction each cycle |
| `on_complete:` | symbol | `nil` | Tag delivered as `:transition_complete` |

`build` raises `ArgumentError` if `duration` is not an `Integer` or
if `to:` is missing.

### Looping

`Plushie::Animation::Transition.loop` is sugar for a repeating
transition. It sets `repeat: :forever` and `auto_reverse: true` by
default. Because a loop needs a cycle range, pass `from:` alongside
`to:`:

```ruby
# Pulse forever between 1.0 and 0.4:
Plushie::Animation::Transition.loop(800, to: 0.4, from: 1.0)

# Three cycles, one-way (spinner rotation):
Plushie::Animation::Transition.loop(1000, to: 360, from: 0, cycles: 3, reverse: false)
```

| Option | Type | Default | Description |
|---|---|---|---|
| `cycles:` | Integer or `nil` | `nil` (forever) | Number of cycles |
| `reverse:` | boolean | `true` | Auto-reverse each cycle |

### The from / to lifecycle

- `to:` is always required. It is the target value.
- `from:` applies only on **first appearance**. When a widget
  enters the tree, the renderer starts at `from:` and animates to
  `to:`. On subsequent renders with the same widget ID, `from:` is
  ignored.
- When `to:` changes between renders, the renderer animates from
  the current interpolated value to the new target. No restart.
- When `to:` stays the same, nothing happens. Returning the same
  descriptor every render is free.

## Springs

`Plushie::Animation::Spring`

Physics-based animation using a damped harmonic oscillator. No
fixed duration: the spring settles naturally when displacement and
velocity both approach zero. Interruption preserves velocity, which
is why springs feel responsive under rapid input (drag, scroll,
hover, target flicker).

```ruby
# Named preset:
Plushie::Animation::Spring.build(to: 1.05, preset: :bouncy)

# Explicit parameters:
Plushie::Animation::Spring.build(to: 200, stiffness: 200, damping: 20)
```

### Options

| Option | Type | Default | Description |
|---|---|---|---|
| `to:` | number | required | Target value |
| `from:` | number | `nil` | Starting value (first appearance only) |
| `stiffness:` | Numeric | `170` | How hard the spring pulls |
| `damping:` | Numeric | `26` | Friction (higher means less bounce) |
| `mass:` | Numeric | `1.0` | Inertia |
| `velocity:` | Numeric | `0.0` | Initial velocity |
| `preset:` | symbol | `nil` | Named parameter set, expanded before other opts |
| `on_complete:` | symbol | `nil` | Tag delivered as `:transition_complete` |

### Presets

Presets expand to `stiffness` and `damping` pairs. Any keyword
supplied alongside `preset:` overrides the preset's value.

| Preset | Stiffness | Damping | Feel |
|---|---|---|---|
| `:gentle` | 120 | 14 | Slow, smooth, no overshoot |
| `:snappy` | 200 | 20 | Quick, minimal overshoot |
| `:bouncy` | 300 | 10 | Quick with visible bounce |
| `:stiff` | 400 | 30 | Very quick, crisp stop |
| `:molasses` | 60 | 12 | Slow, heavy, deliberate |

`build` raises `ArgumentError` on an unknown preset symbol or when
`to:` is missing.

### Tuning by feel

- More stiffness: faster, snappier
- More damping: less bounce, more controlled
- More mass: slower to start and stop, more momentum
- High stiffness plus low damping: bouncy, like a rubber ball
- Low stiffness plus high damping: sluggish, like honey

## Sequences

`Plushie::Animation::Sequence`

Chains transitions and springs that run one after another on the
same prop. Each step's starting value defaults to the previous
step's final value:

```ruby
container("item",
  opacity: Plushie::Animation::Sequence.build([
    Plushie::Animation::Transition.build(200, to: 1.0, from: 0.0),
    Plushie::Animation::Transition.loop(800, to: 0.7, from: 1.0, cycles: 3),
    Plushie::Animation::Transition.build(300, to: 0.0)
  ], on_complete: :fade_cycle_done))
```

| Option | Type | Default | Description |
|---|---|---|---|
| `steps` | `Array<Transition, Spring>` | required | Animation steps, executed in order |
| `on_complete:` | symbol | `nil` | Tag fired when the sequence finishes |

Only the sequence-level `on_complete:` fires; individual step
completion tags inside a sequence are ignored. `build` raises
`ArgumentError` if `steps` is not an array of descriptors.

## Easing catalogue

Pass any of these symbols as `easing:`. The `:ease_in_out` default
is sine-based smooth-both-ends.

### Standard

| Easing | Feel |
|---|---|
| `:linear` | Constant velocity, mechanical |
| `:ease_in` | Gentle acceleration |
| `:ease_out` | Gentle deceleration |
| `:ease_in_out` | Smooth both ends (default) |

### Power curves

| Family | In | Out | In-out |
|---|---|---|---|
| Quadratic | `:ease_in_quad` | `:ease_out_quad` | `:ease_in_out_quad` |
| Cubic | `:ease_in_cubic` | `:ease_out_cubic` | `:ease_in_out_cubic` |
| Quartic | `:ease_in_quart` | `:ease_out_quart` | `:ease_in_out_quart` |
| Quintic | `:ease_in_quint` | `:ease_out_quint` | `:ease_in_out_quint` |

### Exponential and circular

| Family | In | Out | In-out |
|---|---|---|---|
| Exponential | `:ease_in_expo` | `:ease_out_expo` | `:ease_in_out_expo` |
| Circular | `:ease_in_circ` | `:ease_out_circ` | `:ease_in_out_circ` |

### Overshoot

| Family | In | Out | In-out |
|---|---|---|---|
| Back | `:ease_in_back` | `:ease_out_back` | `:ease_in_out_back` |
| Elastic | `:ease_in_elastic` | `:ease_out_elastic` | `:ease_in_out_elastic` |
| Bounce | `:ease_in_bounce` | `:ease_out_bounce` | `:ease_in_out_bounce` |

### Guidance

- `:ease_out` for **things appearing**: decelerate into place.
- `:ease_in` for **things disappearing**: accelerate away.
- `:ease_in_out` for **things moving within the UI** (panel
  slide, tab switch).
- `:linear` for **continuous motion** (progress bars, spinners).
- `:ease_out_back` for **playful entrances** (slight overshoot).
- `:ease_out_elastic` for **attention-grabbing** effects; use
  sparingly.
- `:ease_out_bounce` for **physics-like settling**.

The renderer also accepts a cubic bezier tuple for curves that no
preset covers. The surface is renderer-side; on the SDK side pass
the easing as a symbol.

## Animatable props

Numeric props that the renderer knows how to interpolate accept
descriptors. Commonly animated props include:

| Prop | Widgets | Purpose |
|---|---|---|
| `opacity` | Most widgets | Fade between `0.0` and `1.0` |
| `max_width` | `column`, `row`, `container` | Expand and collapse width |
| `max_height` | `container` | Expand and collapse height |
| `scale` | Most widgets | Grow and shrink |
| `rotation` | `text`, `rich_text`, `image` | Rotate in degrees |
| `translate_x`, `translate_y` | `floating` | Slide offsets |
| `x`, `y` | `pin` | Absolute position |
| `spacing` | `column`, `row` | Gap between children |
| `border_radius` | `image`, `text`, `rich_text` | Corner rounding |
| `value` | `progress_bar` | Smooth progress changes |
| `size`, `text_size` | `text`, `rich_text`, `markdown` | Font size |

Layout Length values (`:fill`, `:shrink`, `[:fill_portion, n]`)
cannot be animated; they are layout directives, not numbers. Use
`max_width` and `max_height` for size animation instead. Boolean
props snap immediately.

See the [Built-in Widgets reference](built-in-widgets.md) for each
widget's full prop table.

## Completion events

A descriptor with `on_complete:` set emits a widget event when the
renderer finishes interpolation:

```ruby
container("panel",
  max_width: Plushie::Animation::Transition.build(300, to: 0, on_complete: :collapsed))
```

The event arrives in `update` as `Event::Widget`:

```ruby
case event
in Event::Widget[type: :transition_complete, id: "panel", value: {tag: :collapsed, prop: "max_width"}]
  model.with(show_panel: false)
end
```

The `tag` is the symbol you passed to `on_complete:`. `prop` is the
wire name of the animated prop as a string. Use this to chain
phases: start the fade, remove the widget from the tree once the
fade completes.

Interrupted animations do not fire completion; only the descriptor
that replaced them can fire (if it too carries an `on_complete:`).

## SDK-side Tween

`Plushie::Animation::Tween`

Frame-based interpolation that lives in your model. Use when the
animating value drives logic the renderer cannot reach (canvas
shapes, physics simulations, or model state consumed elsewhere).

`Tween` uses Ruby modules of pure functions over a small `State`
struct rather than instance methods; the same state value passes
through `start`, `advance`, and `finished?`.

```ruby
# Create a tween (not yet started):
anim = Plushie::Animation::Tween.new(0.0, 1.0, 300, easing: :ease_out)

# Start on the next frame tick:
anim = Plushie::Animation::Tween.start(anim, timestamp)

# Advance returns [current_value, new_state_or_:finished]:
value, anim = Plushie::Animation::Tween.advance(anim, next_timestamp)
```

### Constructors and helpers

| Method | Signature | Description |
|---|---|---|
| `Tween.new` | `new(from, to, duration_ms, easing:, repeat:, auto_reverse:)` | Create a tween, not yet started |
| `Tween.looping` | `looping(from, to, duration_ms, **opts)` | Shortcut: `repeat: :forever, auto_reverse: true` |
| `Tween.start` | `start(anim, timestamp)` | Stamp the start time, reset the value |
| `Tween.advance` | `advance(anim, timestamp)` | Returns `[value, new_state]` or `[final, :finished]` |
| `Tween.value` | `value(anim)` | Read the current interpolated value |
| `Tween.finished?` | `finished?(anim)` | `true` once complete |
| `Tween.interpolate` | `interpolate(from, to, t, easing)` | Raw helper without a State |

`new` raises `ArgumentError` if `duration_ms` is not a positive
integer.

### Tween easings

The SDK-side interpolator ships a smaller set of easings than the
renderer:

- `:linear`, `:ease_in`, `:ease_out`, `:ease_in_out` (all cubic)
- `:ease_in_quad`, `:ease_out_quad`, `:ease_in_out_quad`
- `:spring` (decaying sine overshoot)

Pass any of these as the `easing:` keyword. You can also pass a
`Proc` that takes `t` in `0.0..1.0` and returns the eased value for
a fully custom curve.

### Driving a tween

Subscribe to the animation frame tick while the tween is active and
advance it in `update`:

```ruby
def subscribe(model)
  if model.anim && !Plushie::Animation::Tween.finished?(model.anim)
    [Plushie::Subscription.on_animation_frame]
  else
    []
  end
end

def update(model, event)
  case event
  in Event::System[type: :animation_frame, value: timestamp]
    value, state = Plushie::Animation::Tween.advance(model.anim, timestamp)
    next_anim = (state == :finished) ? nil : state
    model.with(anim: next_anim, progress: value)
  end
end
```

Drop the subscription once the tween finishes so the runtime stops
consuming frames. `Subscription.on_animation_frame` is described in
the [Subscriptions reference](subscriptions.md).

### Canvas animation

Canvas shapes are data inside prop values, not individual widgets,
so they cannot use renderer-side descriptors. Use `Tween` with
`on_animation_frame` to animate canvas content; read
`Tween.value(...)` inside the canvas block each render.

## Renderer-side vs SDK-side

| Concern | Renderer-side | SDK-side (Tween) |
|---|---|---|
| Wire traffic | Descriptor on start, completion event on finish | One frame event per tick |
| Interpolation location | Renderer | App model |
| Physics (springs) | Supported | No |
| Interruption | Automatic, velocity-preserving | Manual |
| Access to value mid-animation | Only through `on_complete` | Every frame |
| Use when | Animating a visual widget prop | Animating a model value that drives logic |

Renderer-side transitions cost nothing on the Ruby side while
running, and the render loop stays idle. SDK-side tweens drive an
update, a `view`, a diff, and a patch each frame. Pick accordingly.

## Testing

`Plushie::Test::Helpers` exposes two helpers for animation-aware
tests:

```ruby
include Plushie::Test::Helpers

def test_panel_collapses
  click("#toggle")
  advance_frame(150)           # step the renderer animation clock
  assert_equal 200, find!("#panel").props[:max_width]
  skip_transitions             # fast-forward any in-flight animations
  assert_equal 0, find!("#panel").props[:max_width]
end
```

- `advance_frame(timestamp)` sends `Plushie::Command.advance_frame`
  to the renderer so tests control time deterministically.
- `skip_transitions` calls `advance_frame(10_000)` under the hood,
  advancing far enough to complete any reasonable animation and
  triggering every pending `:transition_complete` event.

See the [Testing reference](testing.md) for broader test harness
usage.

## Examples

### Sidebar toggle

```ruby
container("sidebar",
  max_width: Plushie::Animation::Transition.build(250,
    to: model.sidebar_open ? 250 : 0, easing: :ease_in_out),
  opacity: Plushie::Animation::Transition.build(200,
    to: model.sidebar_open ? 1.0 : 0.0)) do
  column(padding: 16, spacing: 8) do
    model.nav_items.each do |item|
      button(item.id, item.label, width: :fill, style: :text)
    end
  end
end
```

### Hover scale with a spring

```ruby
pointer_area("card-hover", on_enter: true, on_exit: true, cursor: :pointer) do
  container("card",
    scale: Plushie::Animation::Spring.build(
      to: model.card_hovered ? 1.02 : 1.0, preset: :snappy)) do
    card_content(model)
  end
end
```

### Completion chaining

```ruby
container("panel",
  max_width: Plushie::Animation::Transition.build(300, to: 0, on_complete: :collapsed))

case event
in Event::Widget[type: :transition_complete, id: "panel", value: {tag: :collapsed}]
  model.with(show_panel: false)
end
```

### Progress bar

```ruby
progress_bar("upload", [0, 100],
  value: Plushie::Animation::Transition.build(300,
    to: model.upload_progress, easing: :ease_out))
```

## See also

- [Built-in Widgets reference](built-in-widgets.md) - widgets and
  their animatable props
- [Themes and styling reference](themes-and-styling.md) - style
  props and the styling surface
- [Subscriptions reference](subscriptions.md) -
  `on_animation_frame` for SDK-side tweens
- [Events reference](events.md) - the `:transition_complete` and
  `:animation_frame` event shapes
- [Testing reference](testing.md) - `advance_frame` and
  `skip_transitions`
