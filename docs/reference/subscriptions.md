# Subscriptions

Subscriptions are declarative event sources. Your app's `subscribe`
method returns an array of subscription specs and the runtime
handles starting, stopping, and diffing them each cycle.
Subscriptions are a function of the model: when the model changes,
the active subscriptions change with it.

All subscription constructors live in `Plushie::Subscription`.

## Timer subscriptions

`Plushie::Subscription.every` fires on a recurring interval:

```ruby
def subscribe(model)
  subs = []
  subs << Plushie::Subscription.every(1000, :auto_save) if model.auto_save && model.dirty
  subs
end

def update(model, event)
  case event
  in Event::Timer[tag: :auto_save]
    save(model)
  end
end
```

Timer subscriptions run in the runtime's timer scheduler. After each
tick the timer is re-armed for the next interval. The `tag` is
embedded in `Event::Timer` so you match on it in `update`.

If the timer interval changes between cycles (e.g. switching from
`every(1000, :tick)` to `every(500, :tick)`), the runtime cancels
the old timer and starts a new one automatically.

## Renderer subscriptions

Renderer subscriptions are forwarded to the renderer binary via the
wire protocol. They do not take a tag argument. Lifecycle management
is keyed by `[kind, window_id]`, so only one subscription of each
kind per window (or globally, when unscoped) can be active.

### Keyboard

| Method | Event delivered |
|---|---|
| `on_key_press(max_rate:, window:)` | `Event::Key[type: :press, ...]` |
| `on_key_release(max_rate:, window:)` | `Event::Key[type: :release, ...]` |
| `on_modifiers_changed(max_rate:, window:)` | `Event::Modifiers` |

`Event::Key` includes `key` (Symbol for named keys like `:escape`,
`:enter`; String for characters), `modifiers` (a hash with
`:ctrl`, `:shift`, `:alt`, `:logo`, `:command` booleans), and
`type` (`:press` or `:release`).

The `:command` modifier is platform-aware: Ctrl on Linux and
Windows, Cmd on macOS. Match on `{ command: true }` for
cross-platform shortcuts.

### Pointer

| Method | Event delivered |
|---|---|
| `on_pointer_move(max_rate:, window:)` | `Event::Widget` (`:move`, `:enter`, `:exit`) |
| `on_pointer_button(max_rate:, window:)` | `Event::Widget` (`:press`, `:release`) |
| `on_pointer_scroll(max_rate:, window:)` | `Event::Widget` (`:scroll`) |
| `on_pointer_touch(max_rate:, window:)` | `Event::Widget` (`:press`, `:move`, `:release`) |

Pointer subscriptions are global. They deliver events as
`Event::Widget` with `id` set to the window ID and `scope` set to
`[]`. The `value` hash includes `pointer` (`:mouse`, `:touch`, or
`:pen`) and position or delta fields depending on the event type.
For widget-specific pointer handling, use `pointer_area` instead.

### Window lifecycle

| Method | Event delivered |
|---|---|
| `on_window_open(max_rate:, window:)` | `Event::Window` (`:opened`) |
| `on_window_close(max_rate:, window:)` | `Event::Window` (`:close_requested`) |
| `on_window_resize(max_rate:, window:)` | `Event::Window` (`:resized`) |
| `on_window_focus(max_rate:, window:)` | `Event::Window` (`:focused`) |
| `on_window_unfocus(max_rate:, window:)` | `Event::Window` (`:unfocused`) |
| `on_window_move(max_rate:, window:)` | `Event::Window` (`:moved`) |

Each window-lifecycle subscription delivers only the named event
type. Combine multiple subscriptions if you need more than one
lifecycle type.

### Other

| Method | Event delivered |
|---|---|
| `on_ime(max_rate:, window:)` | `Event::Ime` |
| `on_theme_change(max_rate:, window:)` | `Event::System` (`:theme_changed`) |
| `on_animation_frame(max_rate:, window:)` | `Event::System` (`:animation_frame`) |
| `on_file_drop(max_rate:, window:)` | `Event::Window` (`:file_dropped`, `:file_hovered`) |

`on_animation_frame` delivers vsync-rate ticks for SDK-side
animation via `Plushie::Animation::Tween`. Renderer-side transitions
and springs do not require this subscription; they run independently
inside the renderer. See the [Animation reference](animation.md).

### Catch-all

`on_event(max_rate:, window:)` subscribes to **all** renderer events:
every widget event, keyboard event, pointer event, window event,
and system event. Use it for debugging or logging, not as a primary
event source. It delivers a lot of traffic.

## All subscription constructors

Renderer subscriptions take optional `max_rate:` and `window:`
keyword arguments. Timer subscriptions take an interval and a tag:

```ruby
Plushie::Subscription.on_key_press
Plushie::Subscription.on_key_press(max_rate: 30)
Plushie::Subscription.on_pointer_move(max_rate: 60)
Plushie::Subscription.every(1000, :tick)
```

Renderer subscriptions are keyed by `[type, window_id]`. Only one
subscription of each kind per window (or globally when unscoped) is
active at a time.

## Rate limiting

The `max_rate:` keyword and the chainable `with_max_rate` method
throttle high-frequency renderer events. The renderer coalesces
intermediate events, delivering only the latest state at each
interval:

```ruby
Plushie::Subscription.on_pointer_move.with_max_rate(30)
```

Or inline:

```ruby
Plushie::Subscription.on_pointer_move(max_rate: 30)
```

`with_max_rate` returns a new `Sub` value. It works on renderer
subscriptions only. Timer subscriptions control their frequency via
the interval argument.

A rate of `0` means "capture but never emit." The subscription is
active (the renderer tracks the state) but no events are delivered.
Useful when you need capture tracking without event processing.

### Three-level hierarchy

Rate limiting applies at three levels, from most to least specific:

1. **Per-widget**: `event_rate:` prop on individual widgets
2. **Per-subscription**: `max_rate` on subscription specs
3. **Global**: `default_event_rate` in app settings

More specific settings override less specific ones. See the
[Configuration reference](configuration.md) for the global setting.

## Window scoping

Scope subscriptions to a specific window in multi-window apps:

```ruby
Plushie::Subscription.for_window("settings", [
  Plushie::Subscription.on_key_press
])
```

Without window scoping, events from any window are delivered.
`for_window` maps `with(window_id: ...)` across each subscription,
returning a new array.

## Conditional subscriptions

Because `subscribe` is a function of the model, you activate
subscriptions conditionally:

```ruby
def subscribe(model)
  subs = [Plushie::Subscription.on_key_press]

  if model.auto_save && model.dirty
    subs << Plushie::Subscription.every(1000, :auto_save)
  end

  subs
end
```

When `auto_save` becomes false or the dirty flag clears, the timer
disappears from the list. The runtime stops it. When the conditions
are met again, the timer starts. No manual start/stop logic needed.

**Performance:** returning the same list every cycle is nearly
free. The runtime generates a key for each subscription and
short-circuits if the key set hasn't changed. Only `max_rate`
changes are re-applied. When the list does change, the diff is
efficient: only added and removed subscriptions trigger work.

## Diffing lifecycle

The runtime calls `subscribe` after every update cycle and diffs
the result against active subscriptions:

1. Generate a key for each spec via `Sub#key`:
   - Timer: `[:every, interval, tag]`
   - Renderer: `[type, window_id]`
2. Sort and compare keys against the previous cycle's key set.
3. **Short-circuit**: if the sorted key set is unchanged, only
   check for `max_rate` changes on existing subscriptions.
4. **New keys**: start timers or send subscribe messages to the
   renderer.
5. **Removed keys**: cancel timers or send unsubscribe messages.
6. **Changed max_rate**: re-send the subscribe message with the
   new rate.

Subscriptions are idempotent. The same spec list produces no work.
Different lists trigger precise add/remove operations.

## Widget-scoped subscriptions

Custom widgets with a `subscribe` callback get namespaced
subscriptions. Timer tags are wrapped internally so they don't
collide with app subscriptions or other widget instances. The
widget sees only the inner tag in its `handle_event` callback.

Multiple instances of the same custom widget each get independent
subscriptions. See the [Custom widgets reference](custom-widgets.md)
for details.

## See also

- [Events reference](events.md) - the event classes delivered by
  subscriptions
- [Configuration reference](configuration.md) - `default_event_rate`
  and global settings
- [Animation reference](animation.md) - `on_animation_frame` for
  SDK-side tweens
- [Custom widgets reference](custom-widgets.md) - widget-scoped
  subscriptions
- [Subscriptions guide](../guides/10-subscriptions.md) - keyboard
  shortcuts, timers, and auto-save applied to the pad
