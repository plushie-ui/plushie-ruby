# Elm-architecture invariants

The contract between user apps and the runtime. These invariants
hold across every plushie-ruby app; the runtime enforces them
and the test framework relies on them. Other host SDKs implement
the same shape (modulo language idiom); plushie-elixir is the
canonical reference per `posture.md`.

## The three callbacks

A Plushie app `include`s `Plushie::App` and implements:

- `init(opts)` returns `model` or `[model, command]`. Called
  once at startup. Returns the initial model, optionally with
  commands to dispatch (load initial data, configure UI).
- `update(model, event)` returns `model` or `[model, command]`.
  Called for every event. Returns the next model, optionally
  with commands.
- `view(model)` returns a `window(...)` node or an array of
  `window(...)` nodes. Pure function of model.

Optional callbacks: `subscribe(model)`, `handle_renderer_exit(model, exit)`,
`window_config(model)`, `settings`. Defaults are provided by
`include Plushie::App`.

## Return-shape validation

`init` and `update` must return one of:

- A bare model (no side effects needed).
- `[model, Command::Cmd]` (single command).
- `[model, [Command::Cmd, ...]]` (list of commands).

`unwrap_result` in the runtime enforces this. Anything else
raises `ArgumentError` immediately:

- A two-element array where the second is neither a
  `Command::Cmd` nor an array of `Command::Cmd`s raises with
  the offending classes named.
- The error message lists the valid return shapes so the user
  can correct the call site without further investigation.

This is fail-fast on purpose. A misshapen return silently
corrupting state is harder to debug than an immediate raise.
A bare model is the no-change shape; there is no separate
"no change" return value.

## Commands are pure data

A command is a `Command::Cmd` (a frozen `Data.define` record
with `type:` and `payload:` fields). The runtime executes it;
user code never executes a command directly. This is what makes
`update` testable: the test asserts the command was returned;
the runtime is what would have run it.

Categories (`Plushie::Command`):

- Async work: `task`, `stream`, `cancel`, `dispatch`.
- Focus: `focus`, `focus_next`, `focus_previous`.
- Text editor (`Command::Text`): `select_all`, `move_cursor_to`,
  `select_range`, etc.
- Scroll (`Command::Scroll`): `scroll_to`, `snap_to`,
  `scroll_by`, etc.
- Window (`Command::Window`): `resize_window`, `close_window`,
  `focus_window`, etc.
- Window queries (`Command::WindowQuery`): `window_size`,
  `window_mode`, etc.
- Image (`Command::Image`): `create_image`, `update_image`,
  `delete_image`, etc.
- Lifecycle: `send_after`, `exit`, `batch`, `none`.
- Native widgets: `widget_command`.

A user dispatching a side effect that is not a command is a
design problem with the side effect, not a request for a new
escape hatch. If a needed side effect cannot be expressed as a
command, the missing command is the work.

## View is a pure function of model

`view(model)` returns the UI tree from the model. It does not
access process state, does not call out to other threads, does
not read external state, does not perform I/O. The runtime calls
`view` after every update; it must be deterministic from the
model alone.

Behavioral widgets defined via `include Plushie::Widget` that
take internal state (`state` declarations, `view(id, props,
state)`) are the exception, but the state is owned by the
runtime and threaded into the widget's `view` deterministically;
the widget body is still pure with respect to the inputs it
receives.

The top level of the view must be a window node or an array of
window nodes. `Tree.normalize` raises `ArgumentError` with
"view must return a window node or an array of window nodes"
when the top level is anything else; a bare `column` or `row`
at the top is a programming error.

## Subscriptions are declarative

`subscribe(model)` returns the list of active subscriptions
(`Subscription::Sub` records). The runtime diffs this list each
cycle, starts new subscriptions and stops removed ones. The
user does not start or stop subscriptions imperatively; they
return the list and the runtime reconciles.

Timer subscriptions run via the shared `TimerScheduler` (one
thread, deadline-based `IO.select`). Other subscriptions (key,
mouse, window events) are forwarded to the bridge as wire
messages. Subscription failures surface as events through the
normal dispatch path. When only `max_rate` changes between
diffs, the runtime short-circuits and updates the rate without
re-creating the subscription.

## Widget event flow

Events from the renderer arrive at the runtime, flow through
the widget handler scope chain, and reach `update`:

1. Event arrives via `Bridge` and is pushed to the runtime's
   event queue.
2. Runtime walks the registered widget handlers along the
   scoped-ID chain (innermost first).
3. Each handler returns one of:
   - `:ignored`: handler did not capture; continue to next.
   - `:consumed`: captured, no output; stop the chain.
   - `[:update_state, new_state]`: captured, persist widget
     state; stop.
   - `[:emit, family, data]`: captured, replace the event with
     the emitted one; continue with the new event up the
     chain.
   - `[:emit, family, data, new_state]`: emit and persist
     state.
4. If the chain returns an event (or the original was not
   captured), it reaches `update`.

Canvas-internal events that no handler captures are auto-
consumed by the runtime; they never reach `update`. View-only
widgets (no events, no state) are transparent; events pass
through.

## Scoped IDs

Wire IDs use the canonical format `window#scope/path/id`:

- `"main#form/email"`: widget `email` inside scope `form`
  inside window `main`.
- `"main"`: the window itself.

Events on the runtime side carry split fields: `id` (local),
`scope` (reversed ancestor chain, immediate parent first, with
`window_id` appended as the last element), `window_id`. User
pattern matching usually only cares about the head of the scope
(the immediate parent), so the trailing `window_id` does not
get in the way:

```ruby
case event
in Event::Widget[type: :click, id: "save", scope: ["form", *]]
  ...
in Event::Widget[type: :click, id: "done", scope: [item_id, *]]
  ...
end
```

Commands use forward-order path strings: `Command.focus("form/email")`.
`Plushie::Event.target(event)` reconstructs the full path from
an event when needed (the trailing `window_id` is stripped from
the scope list before joining).

Auto-ID containers (no explicit ID) do not create a scope; their
generated IDs (`"auto:..."`) are stripped during normalization.
Window nodes do not create a scope; they are the window
component of the wire ID. Both `"/"` and `"#"` are forbidden in
user-provided IDs (`/` is the scope separator; `#` is the
window separator).

## What these invariants buy

- **Tests can be written.** A pure `update` plus pure data
  commands plus a pure `view` is exercisable through the
  integration spine without elaborate setup. The user never
  needs to "wait for an effect" in their tests; they assert on
  what was returned.
- **The runtime can revert on exception.** Because `update` is
  a pure function that returns the new model, the runtime can
  keep the previous model and recover by reverting. Same for
  `view`: a previous tree is preserved and used as the
  fallback.
- **The bridge can re-sync after a renderer crash.** The
  current model is enough to regenerate the full tree and
  re-establish state. The renderer holds no app state the
  runtime cannot reconstruct.
- **Cross-SDK parity is meaningful.** "What does plushie-elixir
  do here" has a precise answer; plushie-ruby implements the
  same contract.
