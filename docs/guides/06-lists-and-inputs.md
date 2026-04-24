# Lists and Inputs

The pad edits a single experiment held in memory. In this chapter
we give it a filesystem: experiments are saved as `.rb` files under
`experiments/`, listed in a sidebar, created from a toolbar input,
switched between, and deleted when you no longer want them.

Along the way we cover dynamic list rendering, `keyed_column` vs
`column`, scoped IDs for per-row events, `text_input` with submit,
`checkbox` for booleans, and `pick_list` / `combo_box` / `slider`
for the rest of the form-control vocabulary.

## Storing experiments on disk

Each experiment is a Ruby source file in `experiments/` at the
project root. The directory sits outside `lib/`, so Zeitwerk does
not try to autoload it and the pad does not accidentally compile
an experiment at boot. File I/O is plain Ruby standard library; no
Plushie concepts involved.

Create `lib/plushie_pad/experiments.rb`:

```ruby
# frozen_string_literal: true

require "fileutils"

module PlushiePad
  module Experiments
    DIR = File.expand_path("../../experiments", __dir__)

    def self.list
      return [] unless Dir.exist?(DIR)
      Dir.children(DIR).select { |f| f.end_with?(".rb") }.sort
    end

    def self.load(name)
      path = File.join(DIR, name)
      File.exist?(path) ? File.read(path) : ""
    end

    def self.save(name, source)
      FileUtils.mkdir_p(DIR)
      path = File.join(DIR, name)
      tmp = "#{path}.tmp"
      File.write(tmp, source)
      File.rename(tmp, path)
    end

    def self.delete(name)
      path = File.join(DIR, name)
      File.unlink(path) if File.exist?(path)
    end

    def self.starter_source(label)
      <<~RUBY
        module Experiment
          def self.view
            Plushie::Widget::Column.new("root", padding: 16, spacing: 8)
              .push(Plushie::Widget::Text.new("greeting", "Hello from #{label}!", size: 24))
              .push(Plushie::Widget::Text.new("hint", "Edit me and press Save."))
              .build
          end
        end
      RUBY
    end
  end
end
```

Require it from `lib/plushie_pad.rb` so the app can reach it:

```ruby
require_relative "plushie_pad/experiments"
```

Writes go through a temp file and a rename, so a crash mid-save
leaves the old file intact.

## Extending the model

The model grows new fields for the file list, the active file, and
the new-name input:

```ruby
Model = Plushie::Model.define(
  :source,
  :preview,
  :error,
  :files,        # experiment filenames (Array<String>)
  :active_file,  # currently selected filename (String or nil)
  :new_name,     # new-experiment name input (String)
  :auto_save    # auto-save toggle (Boolean, wired in chapter 10)
)
```

`init` loads the file list and picks the first file as active. If
the directory is empty, it falls back to a starter template with no
active file:

```ruby
def init(_opts)
  files = Experiments.list
  source, active = if files.any?
    [Experiments.load(files.first), files.first]
  else
    [Experiments.starter_source("hello"), nil]
  end
  preview, error = render(source)
  Model.new(
    source: source,
    preview: preview,
    error: error,
    files: files,
    active_file: active,
    new_name: "",
    auto_save: false
  )
end
```

## Rendering a dynamic list

To render one row per file, iterate the list inside a layout
container's block. Each iteration calls a widget helper, and the
DSL pushes its result onto the current context:

```ruby
column("files", spacing: 4, padding: 8) do
  model.files.each { |file| button(file, file) }
end
```

This works, but it has a subtle bug. `column` matches children
against their previous state by position. Inserting a file at the
top of the list shifts every other child down one slot. The
widget that used to sit at position 1 now sits at position 2, so
the renderer treats it as "the second row changed" instead of "a
new row was inserted". Any state that row owned (scroll offset,
focus, text cursor) moves to the neighbour.

`keyed_column` diffs children by their ID instead of position, so
items keep their state no matter where they move in the list:

```ruby
keyed_column("files", spacing: 4, padding: 8) do
  model.files.each { |file| button(file, file) }
end
```

Reach for `keyed_column` for any list whose contents change at
runtime: file lists, chat messages, todo items, search results.
Plain `column` is for fixed layouts where the children are known
at compile time. See
[keyed_column vs column](../reference/built-in-widgets.md#keyed_column-vs-column)
for the full comparison.

### Give each row a stable ID

The diff only works if each row's ID is stable across renders. Use
an ID derived from the item's identity (a filename, UUID, row PK),
never an index:

```ruby
# Bad: inserting at the head renumbers every row.
model.files.each_with_index do |file, i|
  container("item-#{i}") { ... }
end

# Good: the filename is the identity.
model.files.each do |file|
  container(file) { ... }
end
```

Index-based IDs make the diff see "every row changed" on an
insertion, which is exactly what `keyed_column` is trying to avoid.

## Scoped IDs for per-row events

Each row wants its own select button and delete button. If every
delete button had `id: "delete"`, `update` could not tell which
file to delete. Scoped IDs solve this.

When you wrap children in a named `container`, the container's ID
becomes part of every descendant event's `scope`. Pattern-matching
on the scope recovers the parent's ID:

```ruby
def file_row(model, file)
  select_style = (model.active_file == file) ? :primary : :secondary
  container(file, padding: 4) do
    row("row", spacing: 4) do
      button("select", file, style: select_style)
      button("delete", "x", style: :danger)
    end
  end
end
```

A click on the delete button inside `container("hello.rb")`
arrives as:

```ruby
Event::Widget[
  type: :click,
  id: "delete",
  scope: ["hello.rb", "main"],
  window_id: "main"
]
```

The `scope` field is the ancestor chain with the immediate parent
first and the window ID at the tail. Pattern-match with a splat to
bind the parent and ignore the rest:

```ruby
in Event::Widget[type: :click, id: "delete", scope: [file, *]]
  delete_file(model, file)
```

The `scope: [file, *]` arm works at any nesting depth. Wrapping
the row in additional containers only adds more entries at the
head of `scope`, and the splat swallows them. For the full rules,
see the [Scoped IDs reference](../reference/scoped-ids.md).

## Building the sidebar

Put the rows inside a scrollable keyed column, and wrap the whole
thing in a fixed-width container so it holds its shape regardless
of window size:

```ruby
def sidebar(model)
  container("sidebar-wrap",
    width: 200,
    height: :fill,
    border: Plushie::Type::Border.from_opts(color: "#333333", width: 1)) do
    scrollable("sidebar", height: :fill) do
      keyed_column("files", spacing: 4, padding: 8) do
        model.files.each { |file| file_row(model, file) }
      end
    end
  end
end
```

The outer `container` gets the width and border. The `scrollable`
gives a vertical scrollbar once the list exceeds the visible area.
The `keyed_column` spaces rows and diffs them by filename. Each
`file_row` wraps the row controls in a `container` keyed by the
filename, producing the scoped events.

## text_input

`text_input` is a single-line editable field. The positional
arguments are the widget ID and the current value from the model.
Keyword options tune behaviour:

```ruby
text_input("new-name", model.new_name,
  placeholder: "new_name.rb",
  on_submit: true)
```

- `placeholder:` shows hint text when the field is empty.
- `on_submit: true` makes Enter emit a `:submit` event. Without
  it, only `:input` events fire.

The `:input` event carries the full buffer as `value` on every
keystroke. Update the model directly:

```ruby
in Event::Widget[type: :input, id: "new-name", value: name]
  model.with(new_name: name)
```

The `:submit` event fires when the user presses Enter (assuming
`on_submit: true`). Use it to trigger the create flow:

```ruby
in Event::Widget[type: :submit, id: "new-name"]
  create_new(model)
```

Like `text_editor`, `text_input` is stateful: the cursor position,
selection, and undo stack live in the renderer keyed by the scoped
ID. Changing the ID discards the state, so pick a stable one.

## checkbox and toggler

`checkbox` and `toggler` are the two boolean-state widgets. Both
take an ID and the current boolean, and both emit `:toggle` with
the new boolean as `value`:

```ruby
checkbox("auto-save", model.auto_save, label: "Auto-save")
toggler("dark_mode", model.dark_mode, label: "Dark mode")
```

```ruby
in Event::Widget[type: :toggle, id: "auto-save", value: on]
  model.with(auto_save: on)
```

The visual difference: `checkbox` shows a box with a tick;
`toggler` shows an iOS-style switch. The event shape is identical.
Use whichever suits the form.

## slider and vertical_slider

`slider` takes an ID, a two-element `[min, max]` range, and the
current value. Keyword options include `step:`, `shift_step:`,
`default:`, and style overrides:

```ruby
slider("volume", [0, 100], model.volume, step: 5)
```

Two events fire during interaction. `:slide` fires on every
pointer move while dragging, carrying the live value:

```ruby
in Event::Widget[type: :slide, id: "volume", value: level]
  model.with(volume: level)
```

`:slide_release` fires once when the user releases the handle:

```ruby
in Event::Widget[type: :slide_release, id: "volume", value: final]
  model.with(volume: final)
```

Match `:slide` for live previews and `:slide_release` when you
only care about the final value (for example, dispatching a
network request). `vertical_slider` has the same signature and
events but flows top-to-bottom.

## pick_list and combo_box

`pick_list` is a dropdown with a fixed option list. Positional
args: ID, options array, currently selected value:

```ruby
pick_list("theme", %w[Light Dark Solarized], model.theme,
  placeholder: "Pick a theme")
```

Selection arrives as `:select` with the chosen string as `value`:

```ruby
in Event::Widget[type: :select, id: "theme", value: choice]
  model.with(theme: choice)
```

`combo_box` combines a text input with a filtered dropdown. Good
for free-text fields with a known set of common values:

```ruby
combo_box("language", %w[Ruby Elixir Gleam Rust], model.language_search,
  placeholder: "Language")
```

It emits `:input` on every keystroke (current text), `:select`
when the user picks a suggestion, and `:open` / `:close` as the
dropdown toggles. Hold both the search text and the committed
selection in the model if you need them separately.

See the [Built-in Widgets reference](../reference/built-in-widgets.md)
for the full prop lists and remaining input widgets.

## Focus after creating a new experiment

Creating a new experiment is a good moment to jump focus back to
the editor so the user can start typing immediately. This is a
side effect: the model update happens synchronously, but the focus
change is a command the runtime executes afterwards.

Return a `[model, command]` tuple from the `update` arm instead of
a bare model:

```ruby
def create_new(model)
  raw = model.new_name.strip
  return model if raw.empty?
  name = raw.end_with?(".rb") ? raw : "#{raw}.rb"
  label = File.basename(name, ".rb")
  source = Experiments.starter_source(label)
  Experiments.save(name, source)
  preview, error = render(source)
  updated = model.with(
    files: Experiments.list,
    active_file: name,
    source: source,
    preview: preview,
    error: error,
    new_name: ""
  )
  [updated, Plushie::Command.focus("editor")]
end
```

`Plushie::Command.focus` takes a widget path. A bare ID like
`"editor"` matches any widget with that local ID in the current
window. For multi-window apps or when the same ID appears in
multiple containers, pass a scoped path like
`"sidebar/new-name"`. See the
[Commands reference](../reference/commands.md) for the full
command surface.

Any `update` arm can return either a bare model or a
`[model, command]` tuple. The runtime handles both.

## Wiring switch and delete

Two more arms handle selecting and deleting rows. Both extract the
filename from the scope chain:

```ruby
in Event::Widget[type: :click, id: "select", scope: [file, *]]
  switch_file(model, file)

in Event::Widget[type: :click, id: "delete", scope: [file, *]]
  delete_file(model, file)
```

`switch_file` saves the current buffer before loading the new one,
so typing does not go missing when the user changes focus:

```ruby
def switch_file(model, file)
  Experiments.save(model.active_file, model.source) if model.active_file
  source = Experiments.load(file)
  preview, error = render(source)
  model.with(
    active_file: file,
    source: source,
    preview: preview,
    error: error
  )
end
```

`delete_file` removes the file, refreshes the list, and picks a
new active file when the deleted one was the selected one:

```ruby
def delete_file(model, file)
  Experiments.delete(file)
  files = Experiments.list
  if model.active_file == file
    if files.any?
      switch_file(model.with(files: files), files.first)
    else
      model.with(
        files: [],
        active_file: nil,
        source: Experiments.starter_source("hello"),
        preview: nil,
        error: nil
      )
    end
  else
    model.with(files: files)
  end
end
```

Notice that `file` is just a local variable bound by pattern
matching. Scope matching is ordinary Ruby pattern binding: the
splat makes the arm flexible about nesting depth.

## Updating the toolbar and view

The toolbar grows to hold the auto-save checkbox and the new-name
input:

```ruby
def toolbar(model)
  row("toolbar", padding: [8, 4], spacing: 8) do
    button("save", "Save")
    checkbox("auto-save", model.auto_save, label: "Auto-save")
    text_input("new-name", model.new_name,
      placeholder: "new_name.rb",
      on_submit: true)
  end
end
```

The root view wraps sidebar, editor, and preview in a horizontal
row with the toolbar stacked below:

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
    end
  end
end
```

The sidebar has a fixed 200-pixel width. Editor and preview each
take `[:fill_portion, 2]`, so they split the remaining space
evenly. We clean up sizing in [chapter 7](07-layout.md).

## Pattern: one row per item

The shape we built for files generalises to any list where items
have their own controls. A todo list with a done checkbox and a
delete button per task looks almost identical:

```ruby
keyed_column("tasks", spacing: 4) do
  model.tasks.each do |task|
    container(task.id, padding: 4) do
      row("row", spacing: 8) do
        checkbox("done", task.done, label: task.title)
        button("delete", "x", style: :danger)
      end
    end
  end
end
```

And the `update` arms:

```ruby
in Event::Widget[type: :toggle, id: "done", scope: [task_id, *], value: done]
  mark_task(model, task_id, done)

in Event::Widget[type: :click, id: "delete", scope: [task_id, *]]
  delete_task(model, task_id)
```

Keyed lists plus scoped IDs cover the common case for dynamic UI.
The model stays flat, the update arms stay readable, and widget
state survives reorders and inserts.

## Verify it

Start the pad with `bin/plushie_pad` and:

- Create a few experiments with different names. Each gets a
  starter template and appears in the sidebar.
- Switch between them. The editor content and preview update; the
  active row highlights with the primary button style.
- Delete the active experiment. The sidebar shrinks and the next
  row becomes active automatically.
- Write a gallery experiment with some widgets, switch away, and
  switch back. Your content is preserved because `switch_file`
  saves on the way out.
- Toggle the Auto-save checkbox. The model flips but nothing saves
  periodically yet. We wire the timer up in
  [chapter 10](10-subscriptions.md).

## Exercise: duplicate a row

Add a Duplicate button to each sidebar row that copies the
experiment to a new file (for example, `hello.rb` to
`hello-copy.rb`) and switches to the copy. A hint for the naming:
strip `.rb`, append `-copy`, re-add `.rb`, and if that name is
taken, keep bumping a counter (`-copy-2`, `-copy-3`) until you
find a free slot.

The wiring looks familiar:

```ruby
# In file_row:
button("duplicate", "copy")

# In update:
in Event::Widget[type: :click, id: "duplicate", scope: [file, *]]
  duplicate_file(model, file)
```

`duplicate_file` loads the source, invents a fresh name,
`Experiments.save`s the source under the new name, and returns a
new model with `files: Experiments.list`, `active_file: new_name`,
and `source: source` (the same source the duplicated file had).
Bonus points: return `Plushie::Command.focus("editor")` so the
user can start editing the copy straight away.

## See also

- [Built-in Widgets reference](../reference/built-in-widgets.md),
  the full prop lists for `text_input`, `checkbox`, `pick_list`,
  `combo_box`, `slider`, and the rest
- [Events reference](../reference/events.md), the `:toggle`,
  `:select`, `:slide`, `:slide_release`, `:submit` event shapes
  and the pattern-matching cookbook
- [Scoped IDs reference](../reference/scoped-ids.md), how named
  containers build the `scope` chain and the rules for dynamic IDs
- [Commands reference](../reference/commands.md),
  `Plushie::Command.focus` and the other post-update commands

## Next chapter

[Layout](07-layout.md)
