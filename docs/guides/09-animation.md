# Animation and Transitions

Your widgets are styled. Now make them move. Elements that fade,
slide, and spring give the user feedback that the interface is
reacting to their actions.

Plushie's animation system is built around a key insight: the
renderer is closer to the screen than your Ruby code. By
declaring animation *intent* in `view` and letting the renderer
handle interpolation, you get smooth animation with zero wire
traffic during the animation itself. One descriptor on the way
out, one completion event on the way back (if you asked for it).

Plushie offers two layers. **Renderer-side descriptors**
(`Transition`, `Spring`, `Sequence`) encode intent into a prop
value and let the renderer interpolate locally. **SDK-side
tweens** (`Animation::Tween`) run inside your Ruby model, driven
by the `on_animation_frame` subscription, for cases where the
animating value has to live in your state. Prefer descriptors
for anything visual.

All the animation types live under `Plushie::Animation`.

## Renderer-side descriptors

A descriptor is an immutable `Data` struct you pass as the value
of any animatable keyword arg. The DSL does the rest:

```ruby
container("panel",
  max_width: Plushie::Animation::Transition.build(300, to: 200, easing: :ease_out)) do
  text("content", "Hello")
end
```

The descriptor crosses the wire once, inside the patch that
introduced it. The renderer interpolates frame-by-frame locally.
No subscription, no model state, no update cycles while it runs.
When `to:` changes on a later render, the renderer starts a new
animation from the current interpolated value, not from the
beginning. Drop the descriptor (pass a raw `200` instead) and
the renderer snaps to that value, cancelling any in-flight
animation.

## Transitions

`Plushie::Animation::Transition` animates a numeric prop from
its current value toward a target over a fixed duration.

```ruby
# Positional duration, keyword target
Plushie::Animation::Transition.build(300, to: 200)

# Easing, delay, and completion tag
Plushie::Animation::Transition.build(300,
  to: 0.0, easing: :ease_out, delay: 100, on_complete: :faded_out)

# Enter animation: fade in from transparent on first appearance
Plushie::Animation::Transition.build(200, to: 1.0, from: 0.0)
```

The options, verified against `Transition#initialize`:

| Option | Type | Default | Description |
|---|---|---|---|
| `to:` | number | required | Target value |
| `duration` | Integer (positional) | required | Duration in milliseconds |
| `easing:` | symbol | `:ease_in_out` | Easing curve |
| `delay:` | Integer | `0` | Milliseconds before start |
| `from:` | number | `nil` | Starting value, applied on first appearance only |
| `repeat:` | Integer or `:forever` | `nil` | Repeat count |
| `auto_reverse:` | boolean | `false` | Reverse direction each cycle |
| `on_complete:` | symbol | `nil` | Tag delivered as `:transition_complete` |

`build` raises `ArgumentError` when `duration` is not an Integer
or `to:` is missing.

### The from / to lifecycle

- `to:` is the target and is always required.
- `from:` applies only on **first appearance**. When a widget
  enters the tree, the renderer starts at `from:` and animates
  to `to:`. On later renders with the same widget ID, `from:`
  is ignored.
- When `to:` changes between renders, the renderer animates
  from the current interpolated value to the new target. No
  restart, no jump.
- When `to:` is unchanged, nothing happens. Returning the same
  descriptor every render is free.

## Looping

`Transition.loop` is sugar for a repeating transition. It sets
`repeat: :forever` and `auto_reverse: true` by default, so you
need to pair `to:` with a `from:` to define a cycle range:

```ruby
# Pulse forever between 1.0 and 0.4
Plushie::Animation::Transition.loop(800, to: 0.4, from: 1.0)

# Three cycles, one-way (a spinner rotation)
Plushie::Animation::Transition.loop(1000,
  to: 360, from: 0, cycles: 3, reverse: false)
```

| Option | Type | Default | Description |
|---|---|---|---|
| `cycles:` | Integer or `nil` | `nil` (forever) | Number of cycles |
| `reverse:` | boolean | `true` | Auto-reverse each cycle |

## Springs

`Plushie::Animation::Spring` animates using a damped harmonic
oscillator simulation. No fixed duration: the spring settles
naturally once displacement and velocity both approach zero.
Interruption preserves velocity, which is why springs feel
responsive under rapid input (hover flicker, drag, scroll).

```ruby
# Named preset
Plushie::Animation::Spring.build(to: 1.05, preset: :bouncy)

# Explicit parameters
Plushie::Animation::Spring.build(to: 200, stiffness: 200, damping: 20)
```

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

Presets expand to `stiffness` and `damping` pairs. Any keyword
passed alongside `preset:` overrides the preset's value.

| Preset | Stiffness | Damping | Feel |
|---|---|---|---|
| `:gentle` | 120 | 14 | Slow, smooth, no overshoot |
| `:snappy` | 200 | 20 | Quick, minimal overshoot |
| `:bouncy` | 300 | 10 | Quick with visible overshoot |
| `:stiff` | 400 | 30 | Very quick, crisp stop |
| `:molasses` | 60 | 12 | Slow, heavy, deliberate |

`Spring.build` raises `ArgumentError` on an unknown preset
symbol or when `to:` is missing.

## Easing curves

`easing:` takes a symbol. The standard catalogue covers the CSS
named curves:

| Easing | Feel |
|---|---|
| `:linear` | Constant velocity |
| `:ease_in` | Gentle acceleration |
| `:ease_out` | Gentle deceleration |
| `:ease_in_out` | Smooth both ends (default) |

Plus power, exponential, circular, and overshoot families:
`:ease_in_quad` / `:ease_out_quad` / `:ease_in_out_quad`, the
same for `cubic`, `quart`, `quint`, `expo`, `circ`, `back`,
`elastic`, and `bounce`. The
[animation reference](../reference/animation.md) has the full
catalogue plus guidance on when to reach for each one.

Useful rules of thumb:

- `:ease_out` for things *appearing*: decelerate into place.
- `:ease_in` for things *disappearing*: accelerate away.
- `:ease_in_out` for things *moving within the UI*.
- `:linear` for continuous motion (progress bars, spinners).

## Animatable props

Numeric props the renderer knows how to interpolate accept
descriptors. The ones you will reach for most in the pad:

| Prop | Widgets | Purpose |
|---|---|---|
| `opacity` | Most widgets | Fade between `0.0` and `1.0` |
| `scale` | Most widgets | Grow and shrink |
| `max_width` | `column`, `row`, `container` | Expand and collapse width |
| `max_height` | `container` | Expand and collapse height |
| `rotation` | `text`, `rich_text`, `image` | Rotate in degrees |
| `translate_x`, `translate_y` | `floating` | Slide offsets |

Layout `Length` values (`:fill`, `:shrink`,
`[:fill_portion, n]`) cannot be animated: they are layout
directives, not numbers. Use `max_width` and `max_height` for
size transitions instead.

## Completion events

A descriptor with `on_complete:` set emits a widget event when
the renderer finishes interpolation. Both `Transition` and
`Spring` carry this keyword. The event arrives in `update` as
an `Event::Widget` with `type: :transition_complete`:

```ruby
case event
in Event::Widget[type: :transition_complete, id: "preview", value: {tag: :preview_faded_in, prop:}]
  model.with(preview_ready: true)
end
```

The `tag` is the symbol you passed to `on_complete:`. `prop` is
the wire name of the animated prop as a string. Use this to
chain phases: start a fade, remove the widget from the tree
once the fade finishes.

Interrupted animations do not fire completion; only the
descriptor that replaced them can fire (if it too carries an
`on_complete:`).

## Fading in the preview pane

The pad's preview pane pops in abruptly every time you save.
Worse, when a compile fails the stale preview stays on screen
with no hint that the text no longer matches the source. Fade
opacity with the compile state so the preview visually commits
only when there's something fresh to show.

The pane already carries the rendered subtree. Wrap it in a
container whose `opacity:` follows `model.error`:

```ruby
def preview_pane(model)
  opacity = if model.error
    0.3
  elsif model.preview
    1.0
  else
    0.6
  end

  container("preview",
    width: [:fill_portion, 2],
    height: :fill,
    padding: 16,
    opacity: Plushie::Animation::Transition.build(200,
      to: opacity,
      from: 0.0,
      easing: :ease_out,
      on_complete: :preview_faded_in)) do
    if model.error
      text("error", model.error, color: "#ef4444", size: 14)
    elsif model.preview
      Plushie::UI::Context.current&.push(model.preview) || model.preview
    else
      text("placeholder", "Press Save to compile")
    end
  end
end
```

`from: 0.0` applies only on first render so the pane fades in
when the pad starts. Subsequent Save clicks just change `to:`
and the renderer transitions smoothly from wherever the current
opacity happens to be. A failed compile dims the pane to `0.3`;
a successful one returns it to `1.0`.

Handle the completion tag in `update` if you want to react when
the initial fade finishes:

```ruby
in Event::Widget[type: :transition_complete, id: "preview", value: {tag: :preview_faded_in}]
  model.with(preview_ready: true)
```

You can ignore the event entirely and the animation still
works. Completion tags are opt-in.

## A "Saved!" toast

The pad saves on Ctrl+S and on the Save button, but nothing
visible confirms the action. A toast that fades in, holds for a
beat, then fades back out is a short detour through the model.

Add a timestamp to the model:

```ruby
Model = Plushie::Model.define(
  :source, :preview, :error, :event_log,
  :files, :active_file, :new_name, :auto_save, :dirty,
  :saved_at,
  :undo_stack
)
```

Initialise it to `nil` in `init`. Bump it every time
`save_and_render` succeeds:

```ruby
def save_and_render(model)
  preview, error = render(model.source)
  Experiments.save(model.active_file, model.source) if model.active_file && error.nil?
  model.with(
    preview: preview,
    error: error,
    dirty: error ? model.dirty : false,
    saved_at: error.nil? ? Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond) : model.saved_at
  )
end
```

Render the toast near the top of the root column. Its opacity
follows whether `saved_at` is set, and the descriptor fires a
completion event so the model can clear `saved_at` once the
toast fully fades out:

```ruby
def saved_toast(model)
  visible = !model.saved_at.nil?

  container("saved-toast",
    padding: [6, 12],
    background: "#22c55e",
    opacity: Plushie::Animation::Sequence.build([
      Plushie::Animation::Transition.build(150, to: 1.0, from: 0.0, easing: :ease_out),
      Plushie::Animation::Transition.build(1200, to: 1.0),
      Plushie::Animation::Transition.build(300, to: 0.0, easing: :ease_in)
    ], on_complete: :toast_hidden)) do
    text("saved-label", "Saved!", color: "#ffffff", size: 14)
  end if visible
end
```

`Sequence.build` chains descriptors on the same prop. Each
step's starting value defaults to the previous step's final
value, so the middle step holds at `1.0` without needing an
explicit `from:`. Only the sequence-level `on_complete:` fires;
step-level tags inside a sequence are ignored.

Clear `saved_at` when the toast finishes fading:

```ruby
in Event::Widget[type: :transition_complete, id: "saved-toast", value: {tag: :toast_hidden}]
  model.with(saved_at: nil)
```

Drop `saved_toast(model)` into `view`:

```ruby
def view(model)
  window("main", title: "Plushie Pad", theme: :dark) do
    column("root", width: :fill, height: :fill) do
      saved_toast(model)
      row("main-row", width: :fill, height: :fill) do
        sidebar(model)
        editor_pane(model)
        preview_pane(model)
      end
      toolbar(model)
      event_log_pane(model)
    end
  end
end
```

Save twice in a row and each fire-and-forget save triggers a
fresh sequence because `saved_at` moved and the descriptor's
`to:` on the entrance step (`1.0`) stays the same but the widget
re-mounts. Because the toast is created conditionally with an
`if visible` postfix, removing the widget from the tree and
bringing it back counts as a first appearance: the `from: 0.0`
on the entrance step applies every time.

## SDK-side tweens

`Plushie::Animation::Tween` is the escape hatch for values that
must live in the model: a canvas shape whose coordinates drive
collision logic, a progress counter consumed elsewhere in
`update`, or any value the renderer cannot interpolate for you.

`Tween` exposes pure functions over a small `State` struct. The
same state value passes through `new`, `start`, and `advance`:

```ruby
anim = Plushie::Animation::Tween.new(0.0, 1.0, 300, easing: :ease_out)
anim = Plushie::Animation::Tween.start(anim, timestamp)
value, anim = Plushie::Animation::Tween.advance(anim, next_timestamp)
```

`advance` returns a two-element array. While the tween is in
flight, the second element is the next `State`. Once it
finishes, the second element is the symbol `:finished`:

```ruby
case Plushie::Animation::Tween.advance(anim, ts)
in [value, :finished]
  # final value, stop driving the tween
in [value, next_state]
  # in progress, keep going
end
```

Drive it from the `on_animation_frame` subscription. The
renderer delivers an `Event::System[type: :animation_frame]`
tick every vsync frame while the subscription is active:

```ruby
def subscribe(model)
  subs = [Plushie::Subscription.on_key_press]
  if model.anim && !Plushie::Animation::Tween.finished?(model.anim)
    subs << Plushie::Subscription.on_animation_frame
  end
  subs
end

def update(model, event)
  case event
  in Event::System[type: :animation_frame, value: timestamp]
    value, state = Plushie::Animation::Tween.advance(model.anim, timestamp)
    next_anim = (state == :finished) ? nil : state
    model.with(anim: next_anim, progress: value)
  # ... other arms ...
  end
end
```

When the tween finishes, `subscribe` stops including
`on_animation_frame` and the runtime tears the subscription
down. No manual start/stop logic; the model drives
subscription lifetime.

The SDK-side interpolator ships a smaller easing set than the
renderer: `:linear`, `:ease_in`, `:ease_out`, `:ease_in_out`
(all cubic), the quadratic variants, and `:spring` (a decaying
sine overshoot). You can also pass a `Proc` that takes `t` in
`0.0..1.0` and returns the eased value for a fully custom curve.

Renderer-side transitions cost nothing on the Ruby side while
running. SDK-side tweens drive an `update`, a `view`, a diff,
and a patch each frame. Pick accordingly.

## Verify it

Animations resolve to their target values in mock mode, so
tests assert on the settled state without waiting for real
frames:

```ruby
class AnimatedPadTest < Plushie::Test::Case
  def test_save_triggers_toast
    click("#save")
    skip_transitions
    assert_exists("#saved-toast")
    assert_text("#saved-toast/saved-label", "Saved!")
  end
end
```

`Plushie::Test::Helpers` also exposes `advance_frame(timestamp)`
for deterministic control over the renderer's animation clock:

```ruby
click("#save")
advance_frame(150)
assert_in_delta 1.0, find!("#preview").props[:opacity], 0.01
```

`skip_transitions` advances far enough to complete any
reasonable animation and fires every pending
`:transition_complete` event.

## Exercise: spring-scaled sidebar buttons

The file list in the sidebar does not respond to hover. Add a
subtle grow-on-hover with a spring on the select button's
`scale` prop.

- Add a `hovered_file:` field to the model, default `nil`.
- Wrap each file row's select button in a `pointer_area` (see
  Chapter 5). Match `on_enter: true` and `on_exit: true` and
  record the file name on the model.
- Pass a `Spring.build` descriptor as the button's `scale:`
  prop. Target `1.04` when the file is the hovered one, `1.0`
  otherwise. Use `preset: :snappy` for a crisp feel.
- Resist the temptation to reach for a `Transition`: springs
  preserve velocity on interruption, which matters when the
  user sweeps the pointer across the list and every row gets
  two rapid enter/exit events.

Things worth trying once the hover scale works:

- Swap `:snappy` for `:bouncy` and watch the buttons overshoot.
- Add a second spring on `opacity` that dims unhovered rows to
  `0.85`. Because springs settle naturally, the two props stay
  visually coupled without matching durations.
- Add an `on_complete:` tag to the hovered spring and watch
  the toast fire repeatedly as you sweep. Descriptors fire
  every time they settle, even when the "settle" is a move
  toward a new hover target.

## See also

- [Animation reference](../reference/animation.md), the full
  easing catalogue, every descriptor option, and the complete
  prop compatibility table
- [Subscriptions reference](../reference/subscriptions.md),
  `on_animation_frame` and the other renderer subscriptions
- [Events reference](../reference/events.md), the
  `:transition_complete` and `:animation_frame` event shapes
- [Built-in Widgets reference](../reference/built-in-widgets.md),
  per-widget animatable prop tables
- [Testing reference](../reference/testing.md), `advance_frame`
  and `skip_transitions`

## Next chapter

[Subscriptions](10-subscriptions.md)
