# Async and Effects

So far every side effect in the pad has been synchronous. Real apps
need more than that: fetching data from servers, opening native file
dialogs, reading the clipboard, showing desktop notifications. None of
that is synchronous, and none of it should block the Elm loop.

In this chapter we add async commands for background work, streaming
commands for progress updates, and platform effects for file dialogs,
clipboard, and notifications. By the end, the pad has an Import button
in the toolbar that opens a file dialog, reads the chosen `.rb` file,
and adds it to the experiments sidebar as a new entry.

## Why not just block in update?

The runtime serialises updates. While `update` is running, no other
events are processed, no view is rendered, and no commands execute.
That is deliberate: it makes the model trivially consistent. But it
also means that a slow call inside `update` freezes the UI.

Rule of thumb: if a call can take more than a few milliseconds
(reading a file, hitting a network, shelling out to a subprocess),
return a `Command` that schedules the work and let the result come
back as a future event. The rest of this chapter is about the tools
for doing that.

## Command.task

`Plushie::Command.task` runs a callable on a background thread and
delivers the return value as an `Event::Async`:

```ruby
def update(model, event)
  case event
  in Event::Widget[type: :click, id: "fetch"]
    [
      model.with(status: :loading),
      Plushie::Command.task(-> { fetch_experiments }, :data_loaded)
    ]
  end
end

def fetch_experiments
  sleep 0.5
  %w[counter clock notes todo]
end
```

The second argument, `:data_loaded`, is a **tag** that identifies the
task. The result arrives as `Event::Async` with the same tag:

```ruby
in Event::Async[tag: :data_loaded, result: experiments]
  model.with(status: :done, experiments: experiments)
```

The lambda runs in a thread named `plushie-async-<tag>`. Whatever it
returns becomes the `result` field of the `Event::Async`. There is no
wrapping, decoding, or serialisation: a hash is a hash, a string is a
string.

## Error handling

If the lambda raises, the runtime catches the exception and delivers
it as `result: [:error, exception]`. Match on that shape to show an
error state:

```ruby
in Event::Async[tag: :data_loaded, result: [:error, exception]]
  model.with(status: :failed, error: exception.message)
```

For more predictable matching, wrap the body in `begin/rescue` and
return tagged tuples yourself:

```ruby
Plushie::Command.task(
  -> {
    begin
      [:ok, fetch_experiments]
    rescue => e
      [:error, e.class.name, e.message]
    end
  },
  :data_loaded
)
```

Then the update arms read cleanly:

```ruby
in Event::Async[tag: :data_loaded, result: [:ok, experiments]]
  model.with(status: :done, experiments: experiments)

in Event::Async[tag: :data_loaded, result: [:error, klass, message]]
  model.with(status: :failed, error: "#{klass}: #{message}")
```

Either style works. Pick one per app and stick to it.

## One task per tag

Starting a new task with a tag that is already in flight cancels the
previous one. This is deliberate, and it prevents stale results from
a superseded request:

```ruby
in Event::Widget[type: :input, id: "search", value: query]
  [model.with(query: query), Plushie::Command.task(-> { search(query) }, :search)]
```

Every keystroke fires a new `:search` task, killing the previous one.
Only the most recent query's results ever reach `update`. Nonce-based
rejection makes this robust: each task gets a monotonic nonce at
launch, and late arrivals from killed threads carry a stale nonce and
are silently discarded.

For concurrent work, use unique tags:

```ruby
Plushie::Command.batch([
  Plushie::Command.task(-> { fetch_users }, :fetch_users),
  Plushie::Command.task(-> { fetch_posts }, :fetch_posts)
])
```

Both run in parallel. Results arrive as separate `Event::Async` events.

## Command.cancel

To cancel a running task before it finishes, use
`Plushie::Command.cancel` with the tag:

```ruby
in Event::Widget[type: :click, id: "cancel"]
  [model.with(status: :idle), Plushie::Command.cancel(:data_loaded)]
```

Cancellation is tag-based, not reference-based. There is no task
handle to pass around. Starting a new task with the same tag also
cancels the previous one, which is usually what you want for
search-as-you-type and similar patterns.

## Command.stream

For long-running work that produces intermediate results, use
`Plushie::Command.stream`. The callable receives an `emit` proc. Each
call delivers an `Event::Stream`. The callable's final return value
becomes the `Event::Async`:

```ruby
Plushie::Command.stream(
  ->(emit) {
    (0..10).each do |i|
      sleep 0.1
      emit.call(i * 10)
    end
    :done
  },
  :download
)
```

Handle the intermediate and final events side by side:

```ruby
in Event::Stream[tag: :download, value: progress]
  model.with(progress: progress)

in Event::Async[tag: :download, result: :done]
  model.with(progress: 100, status: :done)

in Event::Async[tag: :download, result: [:error, e]]
  model.with(status: :failed, error: e.message)
```

Bind `progress` to a `progress_bar` in the view and the bar fills as
the stream emits:

```ruby
progress_bar("dl", [0, 100], model.progress)
```

`stream` and `task` share the same tag namespace: starting a stream
with a tag that has a live task cancels the task, and vice versa.

## Command.send_after

For one-shot delayed events, use `Plushie::Command.send_after`. Pass a
delay in milliseconds and the event to deliver:

```ruby
in Event::Widget[type: :click, id: "flash-saved"]
  [
    model.with(flash: "Saved"),
    Plushie::Command.send_after(2000, Event::Widget.new(type: :click, id: "clear-flash"))
  ]

in Event::Widget[type: :click, id: "clear-flash"]
  model.with(flash: nil)
```

`send_after` is single-shot. For recurring timers, use
`Plushie::Subscription.every` instead. If a timer for the same event
is already pending, the old one is cancelled.

## Command.dispatch

`Plushie::Command.dispatch` lifts an already-resolved value back into
the event loop via a mapper function. The runtime calls
`mapper_fn.call(value)` and queues the result as the next event:

```ruby
Plushie::Command.dispatch(model.active_file, ->(file) {
  Event::Widget.new(type: :click, id: "reload", value: file)
})
```

Use it sparingly. The common cases are feeding an existing value back
through `update` without branching in place and composing helper
commands that want to emit a follow-up event without a real task.

## Platform effects

Effects are asynchronous requests to the renderer for native platform
operations: file dialogs, clipboard access, desktop notifications.
Unlike async commands (which run Ruby code), effects are handled by
the renderer binary and translated into OS-level calls.

All effect methods live in `Plushie::Effect`. Each takes a symbol
**tag** as its first argument. The tag identifies the effect in the
result event, so there is no need to store request IDs in your model.

Results arrive as `Event::Effect[tag:, result:]`. The `result` is a
typed `Event::Effect::Result` class, one per outcome. Match on the
class, not on tuple shape.

### File dialogs

```ruby
Plushie::Effect.file_open(:import,
  title: "Import Experiment",
  filters: [["Ruby", "*.rb"]])
```

Options: `title`, `filters` (array of `[label, pattern]` pairs),
`default_path`, `timeout`.

The result arrives as one of several `Event::Effect::Result` classes:

```ruby
in Event::Effect[tag: :import, result: Event::Effect::Result::FileOpened[path:]]
  load_experiment(model, path)

in Event::Effect[tag: :import, result: Event::Effect::Result::Cancelled[]]
  model

in Event::Effect[tag: :import, result: Event::Effect::Result::Error[message:]]
  model.with(error: message)

in Event::Effect[tag: :import, result: Event::Effect::Result::Timeout[]]
  model.with(error: "Import dialog timed out")
```

`Cancelled` is distinct from `Error`. A user dismissing a dialog is
expected behaviour, not a failure. Treat it as a normal outcome.

Other file dialog methods share the same shape: `file_open_multiple`
(delivers `FilesOpened[paths:]`), `file_save` (delivers
`FileSaved[path:]`), `directory_select`
(delivers `DirectorySelected[path:]`), `directory_select_multiple`
(delivers `DirectoriesSelected[paths:]`).

### Clipboard

```ruby
# Write text to the clipboard.
Plushie::Effect.clipboard_write(:copy, model.source)

# Read text from the clipboard.
Plushie::Effect.clipboard_read(:paste)
```

Write completion arrives as `Result::ClipboardWritten[]`. Reads arrive
as `Result::ClipboardText[text:]`:

```ruby
in Event::Effect[tag: :copy, result: Event::Effect::Result::ClipboardWritten[]]
  model.with(status: "Copied")

in Event::Effect[tag: :paste, result: Event::Effect::Result::ClipboardText[text:]]
  model.with(source: text)
```

Related: `clipboard_read_html`, `clipboard_write_html`,
`clipboard_clear`. On Linux, `clipboard_read_primary` and
`clipboard_write_primary` access the middle-click selection buffer.

### Notifications

```ruby
Plushie::Effect.notification(:saved, "Exported", "File saved to #{path}")
```

Options: `icon`, `timeout` (auto-dismiss ms), `urgency` (`:low`,
`:normal`, `:critical`), `sound`. Completion arrives as
`Result::NotificationShown[]`.

On macOS, notifications may require the app to be bundled (`.app`) or
to carry notification entitlements to display. On Linux, they route
through the active notification daemon (`notify-osd`, `dunst`, ...).

### Default timeouts

Effects have built-in timeouts: file dialogs get 120 seconds (the
user may browse for a while), clipboard and notifications get 5
seconds, anything else defaults to 30 seconds. If the renderer does
not respond in time, the result is `Result::Timeout[]`. Override per
call with the `timeout:` option.

## Applying it: the Import button

Time to wire a real effect into the pad. The goal: an Import button
next to Save that opens a native file dialog, reads the chosen Ruby
file, and adds it to the experiments sidebar as a new entry.

Add the button to the toolbar:

```ruby
def toolbar_bar(model)
  container("toolbar-wrap", padding: 0) do
    row("toolbar", padding: [8, 4], spacing: 8) do
      button("save", "Save", style: :primary)
      button("import", "Import")
      checkbox("auto-save", model.auto_save, label: "Auto-save")
      text_input("new-name", model.new_name,
        placeholder: "new_name.rb",
        on_submit: true)
    end
  end
end
```

Handle the click by firing the file dialog. A distinct tag per effect
makes the result arm a direct pattern match:

```ruby
in Event::Widget[type: :click, id: "import"]
  [model, Plushie::Effect.file_open(:import,
    title: "Import Experiment",
    filters: [["Ruby", "*.rb"]])]
```

The dialog may be fast or slow. Either way, the UI stays responsive:
the rest of `update` keeps processing events (typing in the editor,
clicking other buttons) while the renderer waits on the OS.

When the user picks a file, the result arrives as `FileOpened`:

```ruby
in Event::Effect[tag: :import, result: Event::Effect::Result::FileOpened[path:]]
  import_experiment(model, path)

in Event::Effect[tag: :import, result: Event::Effect::Result::Cancelled[]]
  model
```

`import_experiment` is plain Ruby. It reads the file, invents a
unique name if the chosen one collides, copies it into the
experiments directory, and selects it as the active file:

```ruby
def import_experiment(model, path)
  source = File.read(path)
  name = unique_name(File.basename(path))
  Experiments.save(name, source)
  preview, error = render(source)
  model.with(
    files: Experiments.list,
    active_file: name,
    source: source,
    preview: preview,
    error: error
  )
end

def unique_name(base)
  return base unless Experiments.list.include?(base)
  stem = File.basename(base, ".rb")
  i = 2
  loop do
    candidate = "#{stem}-#{i}.rb"
    return candidate unless Experiments.list.include?(candidate)
    i += 1
  end
end
```

`File.read` is synchronous, but Ruby source files are small and the
read is local. If you wanted to import larger files without blocking
the Elm loop, wrap the read in `Command.task`:

```ruby
in Event::Effect[tag: :import, result: Event::Effect::Result::FileOpened[path:]]
  [model.with(status: :importing),
   Plushie::Command.task(-> { [path, File.read(path)] }, :import_read)]

in Event::Async[tag: :import_read, result: [path, source]]
  finish_import(model, path, source)
```

Both styles are valid. For the pad's use case (local, small files)
the direct read is simpler and the UI pause is imperceptible.

## Batching

A single `update` clause can return more than one command by wrapping
them with `Plushie::Command.batch`, or by returning an array directly:

```ruby
[model, Plushie::Command.batch([
  Plushie::Effect.clipboard_write(:copy, model.source),
  Plushie::Effect.notification(:copied, "Copied", "Source on clipboard"),
  Plushie::Command.focus("editor")
])]
```

Commands in a batch execute in list order. `Plushie::Command.none` in
a batch is a no-op, which is handy when a branch conditionally
contributes a command.

## Renderer restart survival

Async tasks run in the host Ruby process, not inside the renderer
binary. When the renderer restarts (for example, after a crash),
in-flight tasks keep running and their results arrive as usual. The
app's model is preserved across the restart.

Effects behave differently. Because effects are serviced by the
renderer, a restart cancels them: the result arrives as
`Result::RendererRestarted[]`. Treat it like `Cancelled` in most
cases; the user can retry once the renderer is back.

## DIY patterns

For integrations that do not fit the command model, spin up a thread
yourself and feed results back through `Command.dispatch` or directly
through the runtime's event queue. The trade-off of going around
`Command.task` is that you lose tag-based cancellation and
stale-result rejection. For anything more structured than "deliver
this message once," prefer `Command.task` with a tag.

## Verify it

Effect stubs let tests control what the renderer returns for platform
operations. Register a stub before triggering the effect, and the
renderer responds with your stub instead of opening a real dialog:

```ruby
class ImportTest < Plushie::Test::Case
  def test_import_adds_experiment_to_sidebar
    write_experiment_fixture("/tmp/hello-imported.rb")
    stub_effect(:file_open, Event::Effect::Result::FileOpened.new(path: "/tmp/hello-imported.rb"))
    click("#import")
    assert_includes model.files, "hello-imported.rb"
    assert_equal "hello-imported.rb", model.active_file
  end
end
```

The full effect stubbing API is covered in the
[Testing guide](15-testing.md).

## Exercise: clipboard round-trip

Add two buttons to the editor pane:

- **Copy**: copies the current editor source to the system clipboard.
- **Paste**: replaces the editor source with the clipboard contents.

The wiring fits on a page:

```ruby
# In the editor pane toolbar:
button("copy", "Copy")
button("paste", "Paste")

# In update:
in Event::Widget[type: :click, id: "copy"]
  [model, Plushie::Command.batch([
    Plushie::Effect.clipboard_write(:copy, model.source),
    Plushie::Effect.notification(:copied, "Copied", "Source on clipboard")
  ])]

in Event::Widget[type: :click, id: "paste"]
  [model, Plushie::Effect.clipboard_read(:paste)]

in Event::Effect[tag: :paste, result: Event::Effect::Result::ClipboardText[text:]]
  preview, error = render(text)
  model.with(source: text, preview: preview, error: error)
```

Bonus rounds:

- Disable Paste when the clipboard is empty. Poll on a subscription,
  or just try the paste and show a friendly message on empty text.
- Add a Copy Path button that writes `active_file`'s absolute path
  to the clipboard and fires a notification.
- Swap `clipboard_write` for `clipboard_write_html` with a styled
  HTML snippet, and observe how pasting into a rich-text app
  (a note-taker, a browser comment box) preserves formatting.

## See also

- [Commands reference](../reference/commands.md), the full `Command`
  and `Effect` surface including every method used here
- [Events reference](../reference/events.md), the `Event::Async`,
  `Event::Stream`, `Event::Effect`, and `Event::Effect::Result`
  class shapes
- [App Lifecycle reference](../reference/app-lifecycle.md), the
  `update` return-shape contract for bare models, `[model, cmd]`
  tuples, and `[model, [cmds]]` lists
- [Subscriptions reference](../reference/subscriptions.md),
  `Subscription.every` for recurring timers (complementary to
  `Command.send_after` for one-shots)
- [Testing reference](../reference/testing.md), effect stubs and
  async/stream helpers

## Next chapter

[Canvas](12-canvas.md)
