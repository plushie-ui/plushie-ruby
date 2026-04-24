# App Lifecycle

A Plushie app implements the [Elm architecture](https://guide.elm-lang.org/architecture/):
`init` produces a model, `update` handles events, `view` returns a
window tree. The runtime drives the loop, `Plushie::Bridge` manages
the renderer process, and `Plushie.run` or `Plushie.start` wire the
pieces together.

The callback contract lives in `Plushie::App`. The event loop lives
in `Plushie::Runtime`. This page covers the callbacks, startup and
update cycles, return-value validation, error recovery, and renderer
restart behavior.

## The App class

A Plushie app is a plain Ruby class that mixes in `Plushie::App`:

```ruby
class Counter
  include Plushie::App

  Model = Plushie::Model.define(:count)

  def init(_opts)
    Model.new(count: 0)
  end

  def update(model, event)
    case event
    in Event::Widget[type: :click, id: "increment"]
      model.with(count: model.count + 1)
    else
      model
    end
  end

  def view(model)
    window("main", title: "Counter") do
      column(padding: 16, spacing: 8) do
        text("count", "Count: #{model.count}")
        button("increment", "+")
      end
    end
  end
end
```

Including `Plushie::App` mixes in three things:

- `Plushie::UI`, the block DSL for widgets (`column`, `button`,
  `text`, `window`, and the rest of the [Built-in Widgets](built-in-widgets.md)
  catalog).
- Default no-op implementations of the optional callbacks.
- Top-level constant aliases so `Event`, `Command`, and
  `Subscription` inside the class body resolve to `Plushie::Event`,
  `Plushie::Command`, and `Plushie::Subscription`. Reference prose
  on this page uses the fully-qualified names; examples inside an
  `App` class use the aliases.

The class must respond to `init`, `update`, and `view`. The runtime
checks this at construction and raises `ArgumentError` if any of
them are missing.

## Callbacks

| Callback | Signature | Default |
|---|---|---|
| `init(app_opts)` | required | |
| `update(model, event)` | required | |
| `view(model)` | required | |
| `subscribe(model)` | optional | `[]` |
| `settings` | optional | `{}` |
| `window_config(model)` | optional | `{}` |
| `handle_renderer_exit(model, exit)` | optional | returns `model` |

### init

`init(app_opts)` runs once at startup. It receives a hash and
returns the initial model, optionally paired with commands to
execute after the first render.

```ruby
def init(_opts)
  Model.new(count: 0, history: [])
end

def init(_opts)
  [Model.new(count: 0), Plushie::Command.task(-> { load_state }, :loaded)]
end
```

The runtime currently passes an empty hash to `init`. The parameter
name is `app_opts` to match the other SDKs and to leave room for
future forwarding of keyword arguments from `Plushie.run`, but
today's implementation does not propagate runtime options into
`init`. Treat it as a placeholder.

Commands returned from `init` run **after** the initial snapshot is
sent to the renderer, so the first paint is never blocked by
command execution. Async commands from `init` queue their results
for subsequent update cycles.

### update

`update(model, event)` runs for every event. It receives the current
model and returns the next one, optionally paired with commands.

```ruby
def update(model, event)
  case event
  in Event::Widget[type: :click, id: "save"]
    [model.with(dirty: false), Plushie::Command.focus("editor")]
  in Event::Key[type: :press, key: "s", modifiers: { command: true }]
    [model, Plushie::Effect.file_save(:export)]
  else
    model
  end
end
```

Include a catch-all `else` arm. Without one, Ruby raises
`NoMatchingPatternError` on any unhandled event. The runtime
catches the exception, reverts the model to its pre-dispatch value,
and logs a hint suggesting the missing `else` clause, but the noise
is avoidable.

### view

`view(model)` runs after every successful `update`. It returns a
single `window(...)` node or an array of window nodes:

```ruby
def view(model)
  window("main", title: "Notes") do
    column { text("title", model.title) }
  end
end

def view(model)
  [
    window("main", title: "Main"),
    window("prefs", title: "Preferences", width: 480)
  ]
end
```

Widgets do not live at the top level. Returning a bare `column` or
`text` raises `ArgumentError` with the message "view must return a
window node or an array of window nodes." Returning `nil` is a
special case: the runtime treats it as "no UI" and sends an empty
root to the renderer, useful for transition or loading states.

`view` runs unconditionally after a successful update, even when
the model is structurally unchanged. Wire traffic is avoided at the
diff stage: if the normalised tree is identical to the previous
one, no patch is sent. When `update` or `view` raises, the previous
tree is preserved.

### subscribe

`subscribe(model)` runs after each update cycle and returns a list
of active subscription specs. The runtime diffs the list against
the currently active set, starting new subscriptions and stopping
removed ones.

```ruby
def subscribe(model)
  subs = [Plushie::Subscription.on_key_press]
  subs << Plushie::Subscription.every(1000, :tick) if model.auto_save
  subs
end
```

Default: `[]`. See the [Subscriptions reference](subscriptions.md)
for the full constructor catalog and rate-limiting rules.

### settings

`settings` runs once on startup and again after every renderer
restart. The returned hash is merged with `Plushie.configuration`
overrides and sent to the renderer before any snapshot.

```ruby
def settings
  {
    default_text_size:  16,
    theme:              :dark,
    fonts:              ["assets/fonts/inter.ttf"],
    default_event_rate: 60
  }
end
```

If the `settings` callback raises, the runtime logs a warning and
falls back to `{}`. See the
[Configuration reference](configuration.md#app-settings-callback)
for the full key table.

### window_config

`window_config(model)` runs for each window node detected in the
view tree. It returns a hash of per-window defaults merged with the
per-window props declared on `window(...)` nodes in `view`; the
node's own props win on conflict.

```ruby
def window_config(_model)
  { width: 1024, height: 768, decorations: true, theme: :dark }
end
```

Default: `{}`. See the
[Configuration reference](configuration.md#window-configuration-callback)
for the recognised keys and the
[Windows and Layout reference](windows-and-layout.md) for per-window
props.

### handle_renderer_exit

`handle_renderer_exit(model, exit)` runs when the renderer process
exits, before the runtime attempts a restart. The handler receives
the current model and a `Plushie::RendererExit` value:

| Field | Type | Description |
|---|---|---|
| `type` | Symbol | `:crash`, `:connection_lost`, `:shutdown`, or `:heartbeat_timeout` |
| `message` | String | Human-readable description |
| `details` | Object, nil | Exception, exit status, or raw reason, when available |

Pattern match on the exit type to adjust the model before the
restart:

```ruby
def handle_renderer_exit(model, exit)
  case exit
  in Plushie::RendererExit[type: :heartbeat_timeout]
    model.with(status: :unresponsive, active_stream: nil)
  in Plushie::RendererExit[type: :crash]
    model.with(active_stream: nil)
  else
    model
  end
end
```

Default: returns `model` unchanged. If the handler itself raises,
the runtime logs the error and dispatches an `Event::System` with
`type: :recovery_failed` through `update` so the app can react
(show a banner, reset to a safe state).

## Model.define

`Plushie::Model.define(*fields)` wraps `Data.define` and mixes in a
`#with` method for partial updates:

```ruby
Model = Plushie::Model.define(:count, :history)

m = Model.new(count: 0, history: [])
m.with(count: 1)               # => Model(count: 1, history: [])
m.with(history: m.history + [1]) # new frozen instance
```

Instances inherit `Data`'s frozen-by-default behavior. Attempts to
mutate raise `FrozenError`. The canonical idiom throughout the
lifecycle is "return a new model from `#with`"; never mutate in
place.

One common mistake: `with` returns a new instance rather than
mutating, so forgetting to reassign it is a silent no-op.

```ruby
# Bug: result is discarded, model is unchanged.
model.with(count: model.count + 1)

# Correct: return the new model from update.
model.with(count: model.count + 1)
```

If your `update` method calls `with` in a branch but doesn't return
the result, the model stays where it was and the next render shows
the same UI.

## Starting an app

`Plushie.run(app_class, **opts)` instantiates the app, builds a
`Plushie::Runtime`, and blocks the calling thread until the runtime
exits.

```ruby
Plushie.run(Counter)
Plushie.run(Counter, format: :msgpack, log_level: :debug)
```

`Plushie.start(app_class, **opts)` starts the runtime on a
background thread and returns the handle:

```ruby
handle = Plushie.start(Counter)
# ... do other work ...
handle.stop
```

The handle is the `Plushie::Runtime` instance itself; useful
methods include `stop`, `register_effect_stub`, and the query
helpers documented in [Testing](testing.md).

Both entry points forward keyword arguments to `Plushie::Runtime.new`.
See the [Configuration reference](configuration.md#runtime-options)
for the option table (`transport`, `format`, `daemon`, `binary`,
`log_level`, `token`, `dev`, `dev_dirs`).

## Startup sequence

Once `Plushie.run` or `Plushie.start` fires, the runtime executes a
fixed sequence:

1. The bridge opens the renderer port (or attaches to the
   configured transport), performs the protocol handshake, and
   validates the renderer's advertised version.
2. `settings` runs; the merged settings hash (callback result plus
   `Plushie.configuration.widget_config` plus `validate_props`) is
   sent to the renderer.
3. `init(app_opts)` runs. The result is validated and unpacked
   into `(model, commands)`.
4. `view(model)` runs, the tree is normalised and diffed against
   `nil`, and the initial full snapshot is sent to the renderer.
5. Window ops for every window node detected in the tree are sent,
   with `window_config(model)` merged under the per-window props.
6. Init commands execute.
7. `subscribe(model)` runs and subscriptions are synced to the
   renderer.

A crashing `settings` callback is caught and an empty settings hash
is sent instead. A crashing `init` propagates (there is nothing to
revert to); fix it before shipping.

## Update cycle

For each inbound event:

1. **Coalesce.** High-frequency widget events (`:move`, `:scroll`,
   `:scrolled`, `:resize`) collapse on `(window_id, id, type)` into
   a single latest-value entry. The buffer flushes before the next
   non-coalescable event. Scroll events accumulate their deltas
   rather than dropping them.
2. **Widget handlers.** Canvas-widget handlers registered from the
   tree get the first chance to consume, transform, or pass the
   event through.
3. **`update(model, event)`** produces the next model and commands.
4. **`view(model)`** runs, produces a tree, and the runtime diffs
   it against the previous one. If the trees differ a patch is
   sent; if they match no wire traffic is produced.
5. **Commands execute.** Synchronous commands run immediately;
   async and stream commands spawn tagged tasks; effect commands
   and window / system commands go to the renderer. See the
   [Commands reference](commands.md).
6. **`subscribe(model)`** runs. The runtime diffs the new list
   against the active set and starts or stops subscriptions.
7. **Windows sync.** New, removed, or changed windows produce
   open, close, or update operations on the renderer.

The entire cycle is synchronous inside the runtime thread. Events
are serialised through a thread-safe queue, so concurrent event
sources (renderer messages, timers, async results) are processed
in arrival order.

## Return value validation

`init` and `update` must return one of three shapes. Anything else
raises `ArgumentError` immediately, at the call site.

| Return | Meaning |
|---|---|
| `model` | Bare model, no commands |
| `[model, Plushie::Command::Cmd]` | Model plus a single command |
| `[model, [cmd, cmd, ...]]` | Model plus an array of commands (wrapped in `Command.batch`) |

The validator rejects two-element arrays where the second element
is not a `Command::Cmd` or an array of `Command::Cmd` values:

```
Invalid return from update/init: second element must be a Command or Array of Commands.
Got: [Counter::Model, Symbol]

Valid return shapes:
  model                        # bare model, no commands
  [model, Command.task(...)]  # model + single command
  [model, [cmd1, cmd2]]        # model + command list
```

The validator runs on every `update` call; the cost is negligible,
the payoff is that typos like `[model, :ok]` fail loudly at the
branch that produced them, rather than silently corrupting state
several cycles later.

## Error recovery

### update exceptions

If `update` raises, the model reverts to its pre-dispatch value.
The UI stays on the previous successful render. `NoMatchingPatternError`
gets a dedicated log line with a hint suggesting a missing `else`
arm; other `StandardError` subclasses log class, message, and a
short backtrace.

A consecutive error counter escalates log behaviour to prevent log
flooding:

| Consecutive errors | Log behaviour |
|---|---|
| 1 to 100 | `:error` level with class, message, and first backtrace lines |
| 101 and beyond | suppressed |
| multiples of 1000 | `:error` reminder `N consecutive errors in update (suppressing)` |

The counter resets to zero on the next successful `update`. Only
`StandardError` subclasses are caught; signals and other
non-StandardError exceptions propagate and take the runtime down.

### view exceptions

If `view` raises, the previous tree is preserved (no patch sent).
The same consecutive-error counter tracks view failures. On the
fifth consecutive failure the runtime logs a warning (`view has
failed 5 consecutive times; UI is stale`) and injects a red
overlay bar at the top of the existing tree warning the user that
the UI is frozen. The counter resets on the next successful render,
and the overlay disappears with the next diff.

Query the view desync state from a test or debugger via
`runtime.view_error?`, which returns `true` whenever the consecutive
view error counter is non-zero.

## Renderer restart

`Plushie::Bridge` handles renderer restart on `:spawn` transport.
When the renderer crashes, drops the connection, or misses its
heartbeat, the bridge reconnects with exponential backoff:
`min(100ms * 2^(attempt - 1), 5000ms)` up to five attempts. On a
successful reconnect the counter resets. On exhaustion the bridge
gives up and the runtime stops.

`:stdio` and `[:iostream, adapter]` transports do not restart; they
exit with the renderer.

On each successful restart the runtime:

1. Fails any in-flight effects with
   `Event::Effect::Result::RendererRestarted`, letting the app
   react through `update`.
2. Fails pending `interact` and effect-stub acks with
   `renderer_restarted` so synchronous callers unblock.
3. Clears canvas widget registries, widget statuses, and focus
   tracking.
4. Calls `handle_renderer_exit(model, exit)` (if defined),
   producing a potentially adjusted model.
5. Sends `settings` (via a fresh call to the callback) to the new
   renderer.
6. Re-renders `view(model)` with a fresh diff baseline, producing
   a full snapshot rather than a patch.
7. Re-opens every detected window via `window_config` plus
   per-window tree props.
8. Re-syncs subscriptions against the fresh renderer. Timer
   subscriptions keep ticking locally; renderer subscriptions are
   re-sent so the new renderer learns about them.

App-side state (the model, pending async tasks, timer schedulers)
is preserved. Renderer-side state (scroll positions, text editor
cursors, registered images, renderer-owned animation timelines)
resets because the new renderer process has no memory of the old
one.

A clean renderer exit (status 0, `type: :shutdown`) does not
trigger a restart; the runtime stops and returns control to the
caller of `Plushie.run`.

## Daemon mode

`Plushie.start(MyApp, daemon: true)` keeps the runtime alive after
the last window closes. In both normal and daemon mode, closing
the last window delivers `Event::System[type: :all_windows_closed]`
to `update`. The difference is what happens next:

| Mode | After last window closes |
|---|---|
| Normal (default) | `update` runs, then the runtime shuts down |
| Daemon | `update` runs, the runtime continues. Open new windows by returning them from `view` on a later update. |

Daemon mode is useful for tray-style apps, menu-bar utilities, and
background services that re-open windows based on external events.

## See also

- [Commands reference](commands.md), the command constructors
  returned from `init` and `update`, and the full return-value
  rules
- [Subscriptions reference](subscriptions.md), declarative event
  sources returned from `subscribe`
- [Events reference](events.md), the event classes delivered to
  `update`, including `Event::Effect::Result` variants
- [Configuration reference](configuration.md), environment
  variables, runtime options, and the `settings` key table
- [Testing reference](testing.md), `Plushie::Test::Case`, effect
  stubs, and frame advancement
