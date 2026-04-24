# Subscriptions

So far every event in the pad has come from direct widget interaction: a
button click, a text input keystroke, a slider drag. But some events arrive
from outside the widget tree: keyboard shortcuts, timers, window resizes,
pointer motion. These are delivered through **subscriptions**.

In this chapter we wire up the pad's auto-save feature, which is the
canonical use of `Plushie::Subscription.every`. Along the way we catalogue
the renderer subscriptions (keyboard, pointer, window lifecycle, IME,
theme, animation frames), cover rate limiting, and show how conditional
subscriptions let the runtime start and stop event sources automatically
as the model changes.

## What a subscription is

A subscription is a declarative event source. Your `App` class defines a
`subscribe(model)` method that returns an array of specs. The runtime
calls it after every update cycle, diffs the new list against the active
subscriptions, and starts or stops event sources to match. You never
manage timers or event listeners yourself.

```ruby
def subscribe(model)
  [Plushie::Subscription.on_key_press]
end
```

Subscribe is a function of the model. The same list every cycle means no
work. A different list triggers precise start/stop operations for only
the specs that changed.

All constructors live in `Plushie::Subscription`. Timer subscriptions
take an interval and a tag. Renderer subscriptions (everything else) take
optional `max_rate:` and `window:` keyword arguments.

## Timer subscriptions

`Plushie::Subscription.every(interval_ms, tag)` fires on a recurring
interval. Ticks arrive as `Event::Timer` values carrying the tag you
supplied:

```ruby
def subscribe(_model)
  [Plushie::Subscription.every(1000, :tick)]
end

def update(model, event)
  case event
  in Event::Timer[tag: :tick]
    model.with(seconds: model.seconds + 1)
  else
    model
  end
end
```

Timer subscriptions run inside the runtime's timer scheduler. Each tick
re-arms the timer for the next interval. The `tag` is any symbol: it
distinguishes timers when more than one is active and is required at
construction time. Renderer subscriptions take no tag because their
identity is already the `(kind, window)` pair.

If the interval changes between cycles, for example from
`every(1000, :tick)` to `every(500, :tick)`, the runtime cancels the old
timer and starts a new one automatically. A different interval is a
different subscription key.

## Conditional subscriptions and the pad's auto-save

The pad has an auto-save checkbox in the toolbar. When it's enabled, the
pad should save the current experiment once a second, but only while the
editor holds unsaved edits. Wiring this up is where the declarative
approach pays off: the logic lives in `subscribe`, not in a timer the
checkbox manually starts and stops.

The pad tracks two relevant fields on its model:

```ruby
Model = Plushie::Model.define(
  :source,
  :preview,
  :error,
  :event_log,
  :files,
  :active_file,
  :new_name,
  :auto_save,
  :dirty,
  :undo_stack
)
```

`auto_save` flips when the user toggles the checkbox. `dirty` flips to
`true` whenever the editor buffer changes, and back to `false` when a save
succeeds. With those two flags in place, `subscribe` is a one-liner:

```ruby
def subscribe(model)
  subs = [Plushie::Subscription.on_key_press]
  if model.auto_save && model.dirty
    subs << Plushie::Subscription.every(1000, :auto_save)
  end
  subs
end
```

The keyboard subscription is always on (we need it for Ctrl+S, Ctrl+Z,
Escape). The timer only joins the list when both flags are true.

The toggle handler sets `auto_save`:

```ruby
in Event::Widget[type: :toggle, id: "auto-save", value: on]
  model.with(auto_save: on)
```

The editor input handler sets `dirty`:

```ruby
in Event::Widget[type: :input, id: "editor", value: source]
  stack = Plushie::Undo.push(model.undo_stack, ...)
  model.with(source: source, dirty: true, undo_stack: stack)
```

And the timer tick handler saves and (on success) clears `dirty`:

```ruby
in Event::Timer[tag: :auto_save]
  save_and_render(model)
```

`save_and_render` compiles the preview, writes the file if compilation
succeeded, and returns a model with `dirty: false` on success, or
`dirty: model.dirty` preserved on failure so the next tick retries:

```ruby
def save_and_render(model)
  preview, error = render(model.source)
  Experiments.save(model.active_file, model.source) if model.active_file && error.nil?
  model.with(preview: preview, error: error, dirty: error ? model.dirty : false)
end
```

The result is a self-managing feedback loop. Type into the editor:
`dirty` flips true, the timer joins the subscription list, and the
runtime starts it. After a successful tick: `dirty` flips false, the
timer leaves the list, and the runtime stops it. Toggle auto-save off:
the timer disappears immediately regardless of dirty state. There is no
`start_timer` or `stop_timer` anywhere in the pad, because there doesn't
need to be.

## Keyboard subscriptions

Keyboard input arrives through a subscription, not a widget. The pad
subscribes to `on_key_press` unconditionally:

```ruby
Plushie::Subscription.on_key_press
```

Each press delivers an `Event::Key` with `type: :press`. The key field
is a `Symbol` for named keys (`:escape`, `:enter`, `:tab`, `:arrow_up`)
and a `String` for characters (`"s"`, `"a"`, `"1"`). The pad's existing
shortcuts all live in `update`:

```ruby
in Event::Key[type: :press, key: "z", modifiers: {command: true, shift: false}]
  do_undo(model)

in Event::Key[type: :press, key: "z", modifiers: {command: true, shift: true}]
  do_redo(model)

in Event::Key[type: :press, key: "s", modifiers: {command: true}]
  save_and_render(model)

in Event::Key[type: :press, key: "Escape"]
  model.with(error: nil)
```

The `modifiers` hash is symbol-keyed with boolean flags for `:ctrl`,
`:shift`, `:alt`, `:logo`, and `:command`. `:command` is the one to
reach for in shortcuts: it's Ctrl on Linux and Windows, Cmd on macOS.
Match on `{ command: true }` once and the shortcut works everywhere.

Hash patterns are permissive in Ruby. `{ command: true }` matches
whenever `command` is `true`, even when other modifiers are also set.
When two shortcuts differ only by Shift (Ctrl+Z vs Ctrl+Shift+Z), pin
both flags explicitly as above: first-match wins, and leaving Shift
out would make the plain Ctrl+Z arm swallow the redo combination.

`on_key_release` delivers `Event::Key` with `type: :release` for key-up
events.

`on_modifiers_changed` tracks transitions of the modifier state itself,
without a regular key press. It delivers `Event::Modifiers` values
whenever the held set changes:

```ruby
def subscribe(_model)
  [
    Plushie::Subscription.on_key_press,
    Plushie::Subscription.on_modifiers_changed
  ]
end

# In update:
in Event::Modifiers[modifiers: {shift: held}]
  model.with(shift_held: held)
```

Useful for UI that changes appearance based on held modifiers, for
example showing alternate button labels when Shift is down.

## Window lifecycle subscriptions

Window events arrive through dedicated constructors, one per lifecycle
kind:

| Method | Event delivered |
|---|---|
| `on_window_open(max_rate:, window:)` | `Event::Window[type: :opened]` |
| `on_window_close(max_rate:, window:)` | `Event::Window[type: :close_requested]` |
| `on_window_resize(max_rate:, window:)` | `Event::Window[type: :resized]` |
| `on_window_focus(max_rate:, window:)` | `Event::Window[type: :focused]` |
| `on_window_unfocus(max_rate:, window:)` | `Event::Window[type: :unfocused]` |
| `on_window_move(max_rate:, window:)` | `Event::Window[type: :moved]` |

Each constructor delivers only its named event type. Combine multiple
subscriptions when you want more than one:

```ruby
def subscribe(_model)
  [
    Plushie::Subscription.on_window_resize,
    Plushie::Subscription.on_window_close
  ]
end

def update(model, event)
  case event
  in Event::Window[type: :resized, width:, height:]
    model.with(width: width, height: height)

  in Event::Window[type: :close_requested, window_id:]
    model.with(closing: window_id)
  else
    model
  end
end
```

Without a window-close subscription, the renderer closes the window on
its own when the user hits the close button. Subscribing lets you
intercept first, for example to prompt the user about unsaved changes.

`on_file_drop` delivers `Event::Window` with `type: :file_hovered` or
`:file_dropped`, carrying a `path` field. Useful for a drag-and-drop
import hook.

## Pointer subscriptions

Pointer subscriptions are global: they fire on any pointer activity in
the app window rather than being tied to a specific widget.

| Method | Event delivered |
|---|---|
| `on_pointer_move(max_rate:, window:)` | `Event::Widget[type: :move]` |
| `on_pointer_button(max_rate:, window:)` | `Event::Widget[type: :press, :release]` |
| `on_pointer_scroll(max_rate:, window:)` | `Event::Widget[type: :scroll]` |
| `on_pointer_touch(max_rate:, window:)` | `Event::Widget[type: :press, :move, :release]` |

The events arrive as `Event::Widget` with `id` set to the source window's
ID and `scope` set to `[]`. The `value` hash carries coordinates,
buttons, and a `pointer:` field (`:mouse`, `:touch`, or `:pen`):

```ruby
def subscribe(_model)
  [Plushie::Subscription.on_pointer_move(max_rate: 30)]
end

def update(model, event)
  case event
  in Event::Widget[type: :move, value: {x:, y:, pointer: :mouse}]
    model.with(cursor_x: x, cursor_y: y)
  else
    model
  end
end
```

For widget-local pointer handling (drawing on a canvas, dragging inside
a specific area), wrap the target in a `pointer_area` widget instead. A
global `on_pointer_move` fires for movement anywhere, which is rarely
what you want outside of debugging.

## IME, theme, animation, catch-all

The remaining renderer subscriptions:

| Method | Event delivered |
|---|---|
| `on_ime(max_rate:, window:)` | `Event::Ime` |
| `on_theme_change(max_rate:, window:)` | `Event::System[type: :theme_changed]` |
| `on_animation_frame(max_rate:, window:)` | `Event::System[type: :animation_frame]` |
| `on_event(max_rate:, window:)` | any renderer event |

`on_ime` surfaces input-method-editor composition events for CJK and
other multi-keystroke input sequences: `:opened`, `:preedit`, `:commit`,
`:closed`. Text input widgets handle IME correctly on their own; use
this subscription when you need to drive IME flow directly.

`on_theme_change` fires when the OS switches between light and dark
mode. The `value` field carries the new theme name as a string. Useful
when your app is following the system theme and needs to redraw custom
chrome.

`on_animation_frame` delivers vsync-rate ticks for SDK-side animations
through `Plushie::Animation::Tween`. Renderer-side transitions and
springs run independently inside the renderer and do not need this
subscription.

`on_event` is the catch-all: every widget, keyboard, pointer, window,
and system event is delivered. Useful for debugging or wholesale
logging. Not appropriate as a primary event source; the traffic is high
and the handler becomes a sprawling `case/in`.

## Rate limiting

Pointer motion, window resize, and other continuous event sources fire
at the renderer's native rate, which can be hundreds of events per
second. Processing every frame wastes work when you only need, say, 30
samples per second to update a preview. `max_rate:` throttles delivery:

```ruby
Plushie::Subscription.on_pointer_move(max_rate: 30)
```

Or chained on an existing spec:

```ruby
Plushie::Subscription.on_pointer_move.with_max_rate(30)
```

The renderer coalesces intermediate events and delivers only the latest
state at each interval. `with_max_rate` returns a new subscription
value: specs are frozen `Data` structs, not mutated in place.

A rate of `0` means "capture but never emit." The subscription is
active (the renderer tracks the state) but no events reach `update`.
Useful when an invariant requires the capture to be live for some other
reason, without paying the dispatch cost.

Rate limiting applies at three levels, from most to least specific:

1. **Per-widget**: an `event_rate:` prop on widgets that emit
   high-frequency events (`pointer_area`, `sensor`, `slider`).
2. **Per-subscription**: `max_rate:` on the subscription spec.
3. **Global**: `default_event_rate` in app settings.

More specific settings override less specific ones. `max_rate:` only
applies to renderer subscriptions. Timer subscriptions control their
frequency through the interval argument.

## Window-scoped subscriptions

Every renderer subscription constructor takes an optional `window:`
keyword that scopes the subscription to a single window. In multi-window
apps, that keeps an "inspector" panel's keyboard shortcuts from firing
when the main window is focused, and vice versa:

```ruby
Plushie::Subscription.on_key_press(window: "inspector")
```

`Plushie::Subscription.for_window` is the batch form. It takes a window
ID and an array of specs, returning a new array with each spec rewritten
to carry that window scope:

```ruby
def subscribe(_model)
  Plushie::Subscription.for_window("settings", [
    Plushie::Subscription.on_key_press,
    Plushie::Subscription.on_pointer_move(max_rate: 60)
  ])
end
```

Without a window scope, events from every window arrive through the
subscription.

## How diffing works

The runtime maintains an active set keyed by `Sub#key`:

- Timer subscriptions: `[:every, interval, tag]`
- Renderer subscriptions: `[type, window_id]`

After each update, the runtime computes the new key set from
`subscribe(model)`, sorts it, and compares against the previous cycle's
sorted keys. When the sets are identical, only `max_rate` changes on
existing subscriptions are applied. When they differ, each key in the
symmetric difference triggers a start or stop; keys that appear in both
cycles are kept in place, and any `max_rate` change is forwarded to the
renderer.

Returning the same list every cycle is nearly free. Returning a list
that only changes when the relevant model fields change, as in the pad's
auto-save, means the runtime does precise work and only when it
actually needs to.

## Exercise: a periodic timestamp in the event log

The pad's event log records incoming events as they arrive. Let's add a
heartbeat that appends the current timestamp once every five seconds so
you can see at a glance when the pad was last active.

Two changes to make:

1. Add a timer subscription, tagged `:heartbeat`, to `subscribe`. Gate
   it on a new `model.show_heartbeat` boolean if you want a toggle, or
   leave it unconditional for a simpler version.

   ```ruby
   def subscribe(model)
     subs = [Plushie::Subscription.on_key_press]
     subs << Plushie::Subscription.every(1000, :auto_save) if model.auto_save && model.dirty
     subs << Plushie::Subscription.every(5000, :heartbeat)
     subs
   end
   ```

2. Handle the tick by prepending a formatted entry to `event_log`:

   ```ruby
   in Event::Timer[tag: :heartbeat]
     stamp = Time.now.strftime("%H:%M:%S")
     model.with(event_log: (["-- heartbeat #{stamp}"] + model.event_log).first(20))
   ```

Run the pad and watch the log. Every five seconds a new `-- heartbeat`
line appears at the top. Toggle auto-save off: the other timer
disappears, but the heartbeat keeps ticking. This is diffing at work:
two timers with different keys, managed independently by the runtime.

Things worth trying:

- Add the heartbeat's tag to the log entry so you can see which timer
  fired when. A fast heartbeat next to a slow auto-save is a useful way
  to feel the diffing behaviour.
- Change the heartbeat interval between cycles (hook it to a slider).
  The runtime will cancel the 5000ms timer and start the new one on the
  next model change, because the interval is part of the subscription
  key.
- Subscribe to `on_window_resize` and watch the log fill with
  `Event::Window[type: :resized, ...]` entries as you drag a window
  edge. Then add `max_rate: 10` and watch the traffic drop to one
  update per 100ms.

## See also

- [Subscriptions reference](../reference/subscriptions.md)
- [Events reference](../reference/events.md)
- [Commands reference](../reference/commands.md)
- [Configuration reference](../reference/configuration.md)
- [Windows and layout reference](../reference/windows-and-layout.md)

## Next chapter

[Async and Effects](11-async-and-effects.md)
