# Events

The pad now compiles and previews experiments, but every click, keystroke,
and widget interaction that isn't the Save button falls through unhandled.
In this chapter we turn the pad into a teaching tool: a scrolling event
log that shows what the preview emits, plus keyboard shortcuts for the
things we keep reaching for (save, undo, redo, clear error).

Along the way we cover the full `Plushie::Event` family, Ruby's `case/in`
pattern matching against `Data` structs, scoped IDs for events from
dynamic list items, and the platform-aware `:command` modifier that lets
one shortcut work on Linux, Windows, and macOS.

## The lifecycle of an event

An event starts its journey in the renderer. A mouse click hits a button,
the renderer encodes the interaction as a wire message and sends it back
over the pipe. On the Ruby side:

    renderer -> bridge -> runtime -> update

1. `Plushie::Bridge` receives the frame and decodes it through
   `Plushie::Protocol::Decode` into an `Event::Widget`, `Event::Key`, or
   whichever family matches.
2. `Plushie::Runtime` checks for any custom widget `handle_event`
   callbacks in the scope chain (covered in the
   [Custom widgets guide](13-custom-widgets.md)). Handlers can consume,
   transform, or pass the event through.
3. The runtime invokes your `update(model, event)`.
4. Whatever you return becomes the next model, and the view re-renders.

Events you don't match fall through to `update`'s catch-all branch.
The pad's log feature exploits this: every unhandled event gets printed,
so we learn the shape of new events by interacting with the UI.

## The Event class family

All event classes are frozen `Data` structs under `Plushie::Event`.
`include Plushie::App` aliases the module, so inside the pad's `App`
class they're reachable as `Event::Widget`, `Event::Key`, and so on.

| Class | Delivered by |
|---|---|
| `Event::Widget` | Widget interactions and pointer input |
| `Event::Key` | Keyboard subscriptions |
| `Event::Modifiers` | Modifier-state-change subscriptions |
| `Event::Ime` | Input method editor subscriptions |
| `Event::Window` | Window lifecycle (open, close, resize, move) |
| `Event::System` | Theme changes, animation frames |
| `Event::Timer` | `Plushie::Subscription.every` ticks |
| `Event::Async` | `Plushie::Command.task` results |
| `Event::Stream` | `Plushie::Command.stream` values |
| `Event::Effect` | File dialogs, clipboard, notifications |
| `Event::CommandError` | Renderer-side command failures |
| `Event::SessionError` | Multiplexed session errors |
| `Event::SessionClosed` | Session exit |

`Event::Widget` is the one you meet first and reach for most. It covers
every standard widget event (`:click`, `:input`, `:toggle`, `:submit`,
`:select`, `:slide`, ...), pointer events from `pointer_area` and
sensor widgets, focus events, drag events, pane grid events, and
custom widget events.

The [Events reference](../reference/events.md) has the full field list
for every class. This chapter walks through the ones the pad uses.

## Pattern matching with `case/in`

Ruby's `case/in` pattern matching destructures `Data` structs by field
name. The canonical shape across Plushie docs is:

```ruby
case event
in Event::Widget[type: :click, id: "save"]
  # save was clicked, no payload
in Event::Widget[type: :input, id: "editor", value: source]
  # editor text changed, source holds the new buffer
in Event::Key[type: :press, key: "s", modifiers: {command: true}]
  # Ctrl+S on Linux / Windows, Cmd+S on macOS
end
```

Things to know:

- Square brackets on a `Data` class destructure its fields by name. Only
  the fields you mention are matched; the rest are ignored.
- Symbols match symbols. Event type fields are always symbols
  (`:click`, not `"click"`).
- A bare name like `value: source` binds the field to a local variable.
  `value:` with no binding still requires the field to be present but
  discards it.
- Hash patterns are permissive: `modifiers: {command: true}` matches
  any modifier hash where `command` is `true`, even when other keys
  are also set. No `**_rest` needed.
- Array patterns bind with `*`: `scope: [file, *]` matches any scope
  whose first element is bound to `file`.

Forgetting a catch-all branch raises `NoMatchingPatternError`. We cover
recovery at the end of the chapter.

## Widget event type symbols

`Event::Widget` collapses every widget interaction into one class, keyed
by the `type:` symbol. The common ones:

| Symbol | Payload carrier | Typical source |
|---|---|---|
| `:click` | none | Button |
| `:input` | `value` (String) | Text input, text editor |
| `:submit` | `value` (String) | Text input with `on_submit: true` |
| `:toggle` | `value` (Boolean) | Checkbox, toggler |
| `:select` | `value` | Pick list, combo box |
| `:slide` | `value` (Float) | Slider being dragged |
| `:slide_release` | `value` (Float) | Slider released |
| `:paste` | `value` (String) | Text input or text editor paste |
| `:open`, `:close` | none | Expandable |
| `:link_click` | `value` (String) | Markdown link, rich text |
| `:sort` | `value` (String) | Table column |

Pointer events (`:press`, `:release`, `:move`, `:scroll`, `:enter`,
`:exit`, `:double_click`) also arrive as `Event::Widget`. Their `value:`
is a symbol-keyed hash carrying coordinates and modifier state. See the
[Events reference](../reference/events.md) for the full tables.

Custom widgets (Chapter 13) emit a two-element `type:` array of the form
`[widget_type, event_name]`. Pattern match with the same `case/in`
shape:

```ruby
in Event::Widget[type: [:color_picker, :change], value: {hue:}]
  model.with(hue: hue)
```

## Scoped event IDs

Every widget in a container gets its local ID prefixed by its ancestors.
A button with ID `"delete"` inside a container with ID `"hello.rb"`
inside the `"sidebar"` scrollable produces:

```ruby
Event::Widget[
  type: :click,
  id: "delete",
  scope: ["hello.rb", "sidebar", "main"],
  window_id: "main"
]
```

`scope:` lists ancestors from nearest parent outward. The window ID
appears at the tail. The local `id:` is still `"delete"`: scopes
disambiguate widgets that share an ID across list items.

Match the head of the scope with `*` to recover the dynamic row ID:

```ruby
in Event::Widget[type: :click, id: "delete", scope: [file, *]]
  delete_file(model, file)
```

That single arm handles "delete" clicks for every file row the sidebar
renders, binding `file` to the filename each time. We use this pattern
twice in the pad, once for `"select"` and once for `"delete"`, and
we'll use it again in [chapter 6](06-lists-and-inputs.md) when we
flesh the sidebar out.

`Plushie::Event.target(event)` reconstructs the forward-order path as
a string when you want the full ID for logging or debugging:

```ruby
Plushie::Event.target(event)  # => "sidebar/hello.rb/delete"
```

The [Scoped IDs reference](../reference/scoped-ids.md) covers the rules
in depth.

## Keyboard events and the `:command` modifier

Keyboard input arrives as `Event::Key`. It comes from a subscription,
not a widget, so the pad has to subscribe before the runtime delivers
any:

```ruby
def subscribe(_model)
  [Plushie::Subscription.on_key_press]
end
```

Subscriptions get their own chapter ([chapter 10](10-subscriptions.md)).
For now, `on_key_press` listens for key presses on whichever window is
focused and delivers an `Event::Key` with `type: :press` each time.

The `modifiers:` field is a symbol-keyed hash with boolean flags:

| Key | Meaning |
|---|---|
| `:ctrl` | Control key |
| `:shift` | Shift key |
| `:alt` | Alt key (Option on macOS) |
| `:logo` | Logo / Super key (Windows key, Command symbol on macOS) |
| `:command` | Ctrl on Linux and Windows, Cmd on macOS |

`:command` is the key to reach for. Match `{command: true}` once and
your shortcut works on every platform.

```ruby
in Event::Key[type: :press, key: "s", modifiers: {command: true}]
  save_and_render(model)
```

Ruby's hash patterns are permissive. The arm above matches whenever
`command` is `true`, regardless of what other modifiers are set. If
you need a more specific match (for example, Ctrl+Z without Shift and
Ctrl+Shift+Z as separate shortcuts), spell both flags out:

```ruby
in Event::Key[type: :press, key: "z", modifiers: {command: true, shift: false}]
  do_undo(model)

in Event::Key[type: :press, key: "z", modifiers: {command: true, shift: true}]
  do_redo(model)
```

Arm order matters: Ruby tries arms top-to-bottom and takes the first
match. Put the more specific one first when it matters, though here
both are mutually exclusive because `shift` is pinned.

Non-modified keys use plain strings or symbols:

```ruby
in Event::Key[type: :press, key: "Escape"]
  model.with(error: nil)
```

See `lib/plushie/event.rb` for the `Key` attribute list
(`modified_key`, `physical_key`, `location`, `repeat`, `captured`),
all of which are available in the pattern when you need them.

## Adding keyboard shortcuts to the pad

The pad has a Save button already. Let's add a subscription and four
shortcuts:

- **Ctrl+S** (or Cmd+S on macOS): save and re-render.
- **Ctrl+Z**: undo the last edit.
- **Ctrl+Shift+Z**: redo.
- **Escape**: dismiss the error banner.

Add `subscribe` to the `App` class:

```ruby
def subscribe(_model)
  [Plushie::Subscription.on_key_press]
end
```

And extend `update` with the key handlers. The undo machinery uses
`Plushie::Undo`, which we cover fully in
[chapter 14](14-state-management.md); for now treat it as a stack that
records edits. The pad already initialises `model.undo_stack` in `init`.

```ruby
def update(model, event)
  case event
  in Event::Widget[type: :input, id: "editor", value: source]
    stack = Plushie::Undo.push(
      model.undo_stack,
      {
        apply: ->(_s) { source },
        undo: ->(_s) { model.source },
        label: "typing",
        coalesce: :typing,
        coalesce_window_ms: 500
      }
    )
    model.with(source: source, dirty: true, undo_stack: stack)

  in Event::Widget[type: :click, id: "save"]
    save_and_render(model)

  in Event::Key[type: :press, key: "z", modifiers: {command: true, shift: false}]
    do_undo(model)

  in Event::Key[type: :press, key: "z", modifiers: {command: true, shift: true}]
    do_redo(model)

  in Event::Key[type: :press, key: "s", modifiers: {command: true}]
    save_and_render(model)

  in Event::Key[type: :press, key: "Escape"]
    model.with(error: nil)

  else
    log_event(model, event)
  end
end
```

`do_undo` and `do_redo` wrap `Plushie::Undo`:

```ruby
def do_undo(model)
  return model unless Plushie::Undo.can_undo?(model.undo_stack)
  stack = Plushie::Undo.undo(model.undo_stack)
  model.with(source: Plushie::Undo.current(stack), undo_stack: stack)
end

def do_redo(model)
  return model unless Plushie::Undo.can_redo?(model.undo_stack)
  stack = Plushie::Undo.redo(model.undo_stack)
  model.with(source: Plushie::Undo.current(stack), undo_stack: stack)
end
```

Run the pad, type into the editor, and:

- Press **Ctrl+S**: the Save button fires, preview recompiles.
- Press **Ctrl+Z**: the last batch of keystrokes reverts.
- Press **Ctrl+Shift+Z**: the revert undoes itself.
- Trigger an error (break the syntax and Save), then press **Escape**:
  the error banner clears.

The Save button still works the same way because its `update` arm is
unchanged. Both paths call `save_and_render(model)`. A keyboard shortcut
is just another way of dispatching the same update.

## The event log pane

The pad's catch-all branch currently returns `model` unchanged. Let's
have it record every unhandled event instead. Over an interactive
session, the log becomes a running ledger of "things the pad saw" and
a reference for what you can pattern match on.

Extend the model with an `event_log` field, initialised to `[]`:

```ruby
Model = Plushie::Model.define(
  :source,
  :preview,
  :error,
  :event_log,
  # ... other fields from previous chapters
  :undo_stack
)

def init(_opts)
  # ... existing init ...
  Model.new(
    source: source,
    preview: preview,
    error: error,
    event_log: [],
    # ...
    undo_stack: Plushie::Undo.new(source)
  )
end
```

Replace the catch-all branch with a call to `log_event`:

```ruby
else
  log_event(model, event)
end
```

The helper formats each event with `Object#inspect` (which prints
`Data` structs with their class name and fields), trims long entries,
and caps the log at twenty recent events:

```ruby
def log_event(model, event)
  entry = event.inspect
  entry = entry[0, 77] + "..." if entry.length > 80
  model.with(event_log: ([entry] + model.event_log).first(20))
end
```

Prepending the new entry and calling `first(20)` keeps the most recent
at index 0 and drops the tail. Rendering the log in reverse-chronological
order matches the way we read log output: newest at the top.

Render the log as a scrollable column below the toolbar:

```ruby
def event_log_pane(model)
  scrollable("event-log", height: 120) do
    column("log-lines", spacing: 2, padding: 4) do
      model.event_log.each_with_index do |entry, i|
        text("line-#{i}", entry, size: 11, font: :monospace)
      end
    end
  end
end
```

And drop the pane into the root column under the existing split row and
toolbar:

```ruby
def view(model)
  window("main", title: "Plushie Pad", theme: :dark) do
    column("root", width: :fill, height: :fill) do
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

Each `text` line gets an index-based ID (`"line-0"`, `"line-1"`, ...)
so the diff engine can match lines across renders even when the content
changes. Stable IDs matter here: without them every render treats the
entire log as fresh text, and scroll position would reset on every
interaction.

Monospace font and a small size keep long entries legible. Twelve entries
is a rough fit for the 120-pixel tall pane at typical DPI; resize it
freely. [Chapter 15](15-testing.md) shows how to write a test that
clicks a preview widget and asserts the log picked it up.

## The pad, talking to itself

Start the pad (`bundle exec bin/plushie_pad`) and interact with it.
Click the Save button and watch the log stay empty: Save has a specific
`update` arm, so it never falls through. Now click anywhere in the
empty preview area and you'll see nothing either, because
non-interactive containers don't emit events.

Load a gallery experiment and the log comes alive. Replace the editor
contents with:

```ruby
module Experiment
  def self.view
    Plushie::Widget::Column.new("root", padding: 16, spacing: 12)
      .push(Plushie::Widget::Text.new("title", "Widget Gallery", size: 20))
      .push(Plushie::Widget::Button.new("btn", "Click me"))
      .push(Plushie::Widget::Checkbox.new("check", "Check me", false))
      .push(Plushie::Widget::TextInput.new("input", "", placeholder: "Type here..."))
      .push(Plushie::Widget::Slider.new("slide", 0.0..100.0, 50.0))
      .push(Plushie::Widget::Toggler.new("toggle", "Switch", false))
      .build
  end
end
```

Save, then interact with the rendered gallery:

- Click the button: the log shows
  `#<data Plushie::Event::Widget type=:click, id="btn", ...>`.
- Toggle the checkbox: `type=:toggle, value=true` then `value=false`.
- Type into the input: a stream of `:input` entries, each with the
  full current text.
- Drag the slider: a stream of `:slide` entries with the numeric
  position, then a final `:slide_release`.

Each entry is valid Ruby destructuring territory. Copy the fields you
care about into a `case/in` arm and you have a handler.

## Recovering from `NoMatchingPatternError`

Without a catch-all branch, Ruby raises `NoMatchingPatternError` the
first time an unhandled event arrives. The runtime treats an unhandled
update error the same way it treats any other exception in `update`:

- The exception is rescued.
- The previous model is kept (no partial mutations reach the view).
- The error and its backtrace are logged to stderr.
- The cycle continues.

The pad keeps running. But the error is not free: the event that
triggered it is effectively dropped, a noisy backtrace lands in the
log every time you move the mouse, and nothing visible in the UI
explains what's happening. Always end your `case/in` with `else`:

```ruby
case event
in # ... specific arms ...
else
  model                     # no-op
  # or
  log_event(model, event)   # record for debugging
end
```

Returning `model` unchanged is the quiet choice. Logging the event is
more work but pays for itself the first time a widget emits an event
you didn't expect. The pad takes the noisy option deliberately, because
its purpose is to show you what events look like.

## Exercise: add a new keyboard shortcut

The pad's toolbar has a "new_name.rb" text input for creating experiments.
Typing a name and pressing Enter submits it (`Event::Widget` with
`type: :submit, id: "new-name"`). Adding a keyboard shortcut for a blank
new experiment is a one-arm change.

Add **Ctrl+N** to create a new scratch experiment and focus the
new-name input so the user can type a name right away. Two arms to
write:

1. The key handler. Match `Event::Key[type: :press, key: "n",
   modifiers: {command: true}]` and return the model with
   `new_name: "scratch.rb"`, paired with
   `Plushie::Command.focus("new-name")` so the input is ready for
   editing.
2. (Optional) A submit handler on a second key. Match
   `Event::Key[type: :press, key: "Enter", modifiers: {command: true}]`
   inside the same case to commit the new experiment from the keyboard.

Remember that `update` can return `[model, command]` or
`[model, [commands]]` to run effects; see the
[Commands reference](../reference/commands.md). When you're stuck on
which event arrives, check the log.

Things worth trying:

- Test the shortcut on a pointer device that sends extra modifiers
  (e.g. Caps Lock on). Because hash patterns are permissive,
  `{command: true}` still matches.
- Remove the `modifiers:` clause entirely and observe every `n` keystroke
  triggering the shortcut, including the ones you type into the editor.
  This is why you match `{command: true}` rather than just `key: "n"`:
  shortcuts should not steal plain text input.
- Reorder your arms: put a generic `Event::Key[type: :press]` arm before
  the shortcut and watch the shortcut stop firing. First-match wins.

## See also

- [Events reference](../reference/events.md), the complete class and
  symbol catalogue
- [Subscriptions reference](../reference/subscriptions.md), keyboard,
  pointer, timer, and modifier subscriptions
- [Commands reference](../reference/commands.md), focus, async, and
  effect commands triggered from event handlers
- [Scoped IDs reference](../reference/scoped-ids.md), how container
  scoping composes into the `scope:` field
- [Custom widgets reference](../reference/custom-widgets.md), declaring
  custom `type:` tuples and handling events before they reach `update`

## Next chapter

[Lists and Inputs](06-lists-and-inputs.md)
