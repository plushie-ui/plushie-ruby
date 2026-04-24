# State Management

The pad has grown: the editor tracks undo history, the sidebar is a
scrollable list of files, a text input starts new experiments, and a
subscription drives auto-save. All of that state lives in a single
`Model` struct and changes through `update`. The longer the app runs,
the more that struct has to juggle.

This chapter introduces four helpers that take common pieces of that
juggling off your hands: `Plushie::Undo` for reversible edits (already
wired into the pad), `Plushie::Route` for switching between views,
`Plushie::Selection` for multi-selecting rows, and
`Plushie::DataQuery` for filtering and sorting collections. Each one
is a pure data structure. No processes, no side effects, no framework
coupling. You put them in the model, update them in `update`, and read
them in `view`. They compose freely.

Along the way the pad grows a Settings view, a search box for the
sidebar, and bulk delete for multiple selected files.

## Plushie::Undo

The pad already uses `Plushie::Undo` to make Ctrl+Z and Ctrl+Shift+Z
roll the editor buffer back and forward.
[Chapter 5](05-events.md) wired the keyboard shortcuts; this section
recaps the command shape and the coalescing behaviour because the
same ideas show up in every other editor-like feature you build.

Create a stack around an initial value:

```ruby
undo = Plushie::Undo.new("")
```

Push a command. A command is a hash with `:apply` and `:undo` procs,
plus optional metadata:

```ruby
undo = Plushie::Undo.push(undo, {
  apply: ->(text) { text + "a" },
  undo:  ->(text) { text[0..-2] },
  label: "Type a",
  coalesce: :typing,
  coalesce_window_ms: 500
})
```

The keys:

| Key | Type | Description |
|---|---|---|
| `:apply` | Proc | Takes the current value, returns the new one |
| `:undo` | Proc | Takes the new value, returns the old one |
| `:label` | String | Display string for history listings |
| `:coalesce` | Symbol | Merges with adjacent commands sharing this key |
| `:coalesce_window_ms` | Integer | Window in which coalescing applies |

`:apply` and `:undo` must respond to `:call`. `Plushie::Undo.push`
raises `ArgumentError` if either is missing.

Read and walk the stack:

```ruby
Plushie::Undo.current(undo)    # "a"
Plushie::Undo.can_undo?(undo)  # true
undo = Plushie::Undo.undo(undo)
Plushie::Undo.current(undo)    # ""
Plushie::Undo.can_redo?(undo)  # true
Plushie::Undo.history(undo)    # ["Type a"] when not undone
```

`undo` and `redo` on an empty stack return the state unchanged, so
you can call them without guarding. `Plushie::Undo.history` returns
the labels with the most recent entry first.

The stack is bounded by `max_size:` (default 100). Pushing past the
limit drops the oldest entry silently. Pass a different limit when
you know you want more:

```ruby
Plushie::Undo.new("", max_size: 1000)
```

### Coalescing keystrokes

The pad's editor fires an `:input` event on every keystroke. Pushing
one undo entry per keystroke means fifty Ctrl+Z presses to undo a
typed word. `:coalesce` solves that by merging adjacent commands that
share a key within the time window:

```ruby
in Event::Widget[type: :input, id: "editor", value: source]
  stack = Plushie::Undo.push(
    model.undo_stack,
    {
      apply: ->(_s) { source },
      undo:  ->(_s) { model.source },
      label: "typing",
      coalesce: :typing,
      coalesce_window_ms: 500
    }
  )
  model.with(source: source, dirty: true, undo_stack: stack)
```

Every keystroke inside a 500 ms window folds into the single top
entry. The merged entry keeps the *first* undo proc, so one Ctrl+Z
jumps back to the state before the burst started, not to the
keystroke before the current one. Pause for longer than the window
and the next keystroke starts a fresh entry.

Different coalesce keys never merge. Mark formatting commands with
`coalesce: :format`, selection changes with `coalesce: :select`, and
each family folds separately.

## Plushie::Route

When your app grows beyond a single screen, you need a way to track
which screen you're on. `Plushie::Route` is a LIFO navigation stack
keyed by a path plus optional params. Push when navigating forward,
pop to go back.

Create a route at a starting path:

```ruby
route = Plushie::Route.new(:editor)
Plushie::Route.current(route)      # :editor
Plushie::Route.can_go_back?(route) # false
```

Push a new path, optionally with params:

```ruby
route = Plushie::Route.push(route, :settings, tab: :general)
Plushie::Route.current(route)      # :settings
Plushie::Route.params(route)       # { tab: :general }
Plushie::Route.can_go_back?(route) # true
```

`params` is a plain hash bound to the top entry. Every push can
carry its own params; popping reveals the params of the entry
underneath.

Pop to walk back one step:

```ruby
route = Plushie::Route.pop(route)
Plushie::Route.current(route)      # :editor
```

`Plushie::Route.pop` on a single-entry stack returns the route
unchanged, so the app cannot navigate below its starting path. Use
`Plushie::Route.can_go_back?` to decide whether to render a back
button.

`Plushie::Route.history(route)` returns every path on the stack,
most recent first, if you want to render a breadcrumb trail.

Paths are any Ruby value. The pad uses symbols; strings work too.

### Applying it: an editor / settings split

Add a Settings view to the pad. The current screen shows the editor,
sidebar, and preview; the new screen shows theme and font-size
controls. A toolbar button flips between them.

Add the route to the model:

```ruby
Model = Plushie::Model.define(
  :source,
  # ... existing fields ...
  :undo_stack,
  :route,            # Plushie::Route::State
  :theme_choice,     # :dark, :light, :solarized
  :font_size         # Integer
)

def init(_opts)
  # ... existing init ...
  Model.new(
    # ... existing fields ...
    undo_stack: Plushie::Undo.new(source),
    route: Plushie::Route.new(:editor),
    theme_choice: :dark,
    font_size: 14
  )
end
```

Dispatch the top-level layout on the current path:

```ruby
def view(model)
  window("main", title: "Plushie Pad", theme: model.theme_choice) do
    case Plushie::Route.current(model.route)
    when :editor   then editor_screen(model)
    when :settings then settings_screen(model)
    end
  end
end
```

`editor_screen` is the pad's existing view; move the sidebar, editor,
preview, toolbar, and log into a helper. `settings_screen` is new:

```ruby
def settings_screen(model)
  column("settings", padding: 24, spacing: 16) do
    row("settings-header", spacing: 8) do
      button("back", "< Back", style: :text)
      text("title", "Settings", size: 20)
    end
    pick_list("theme", %i[dark light solarized], model.theme_choice,
      placeholder: "Theme")
    slider("font-size", [10, 24], model.font_size, step: 1)
  end
end
```

Wire the navigation events in `update`. One arm for the toolbar
button, one for the back button:

```ruby
in Event::Widget[type: :click, id: "open-settings"]
  model.with(route: Plushie::Route.push(model.route, :settings))

in Event::Widget[type: :click, id: "back"]
  model.with(route: Plushie::Route.pop(model.route))
```

Add the trigger to the existing toolbar:

```ruby
def toolbar(model)
  row("toolbar", padding: [8, 4], spacing: 8) do
    button("save", "Save")
    checkbox("auto-save", model.auto_save, label: "Auto-save")
    text_input("new-name", model.new_name,
      placeholder: "new_name.rb",
      on_submit: true)
    space(width: :fill)
    button("open-settings", "Settings", style: :text)
  end
end
```

Click Settings and the pad flips to the settings view. Click Back
and you're returned to the editor. The editor's model (source buffer,
undo stack, file list) is preserved across the round trip because
none of those fields changed: only `route` did.

## Plushie::Selection

`Plushie::Selection` tracks selected IDs for lists and tables with
three modes:

- `:single` (default): at most one item selected. Selecting a new
  item replaces the previous one.
- `:multi`: any number of items. `toggle` adds or removes; `select`
  with `extend: true` adds without clearing.
- `:range`: like multi, but `range_select` picks every item between
  the current anchor and the target using a provided order list.

Create a selection:

```ruby
sel = Plushie::Selection.new(mode: :multi)
```

Add, toggle, remove, and query:

```ruby
sel = Plushie::Selection.select(sel, "a")
sel = Plushie::Selection.toggle(sel, "b")          # adds "b"
sel = Plushie::Selection.toggle(sel, "b")          # removes "b"
sel = Plushie::Selection.select(sel, "c", extend: true)
Plushie::Selection.selected?(sel, "a")             # true
Plushie::Selection.selected(sel)                   # Set["a", "c"]
sel = Plushie::Selection.deselect(sel, "a")
sel = Plushie::Selection.clear(sel)
```

`Plushie::Selection.selected` returns a `Set`, not an Array. Use
`Set#to_a` when you need to feed it to something array-shaped (for
example, the `table` widget's `selected:` prop).

Range selection needs an ordered list of IDs at construction time so
the helper knows what "between" means:

```ruby
sel = Plushie::Selection.new(mode: :range, order: model.files)
sel = Plushie::Selection.select(sel, "a.rb")       # anchor = "a.rb"
sel = Plushie::Selection.range_select(sel, "c.rb") # selects a, b, c
```

`range_select` without an anchor falls back to selecting just the
target. Rebuild the selection with the current `order:` whenever the
underlying list changes, or shift-click will try to slice a stale
ordering.

### Applying it: multi-selecting sidebar files

The pad's sidebar has one Select button and one Delete button per
file. We'll add a checkbox per row, track the set in a
`Plushie::Selection`, and provide a "Delete selected" toolbar button
that wipes the whole set in one click.

Extend the model:

```ruby
Model = Plushie::Model.define(
  # ... existing fields ...
  :selection    # Plushie::Selection::State
)

def init(_opts)
  # ...
  Model.new(
    # ...
    selection: Plushie::Selection.new(mode: :multi)
  )
end
```

Add the checkbox to `file_row` and reflect the selection in row
style:

```ruby
def file_row(model, file)
  select_style = if model.active_file == file
    :primary
  elsif Plushie::Selection.selected?(model.selection, file)
    :secondary
  else
    :text
  end
  selected = Plushie::Selection.selected?(model.selection, file)

  container(file, padding: 4) do
    row("row", spacing: 4) do
      checkbox("select-check", selected)
      button("select", file, style: select_style)
      button("delete", "x", style: :danger)
    end
  end
end
```

The active file keeps its primary style; selected-but-not-active
rows pick up the secondary style, which is enough of a visual hint
for bulk operations.

Add two arms to `update`. Toggling the checkbox updates the
selection; the bulk-delete click walks the set and removes each file:

```ruby
in Event::Widget[type: :toggle, id: "select-check", scope: [file, *]]
  model.with(selection: Plushie::Selection.toggle(model.selection, file))

in Event::Widget[type: :click, id: "delete-selected"]
  delete_selected(model)
```

```ruby
def delete_selected(model)
  ids = Plushie::Selection.selected(model.selection)
  return model if ids.empty?

  ids.each { |file| Experiments.delete(file) }
  remaining = Experiments.list
  active = ids.include?(model.active_file) ? remaining.first : model.active_file
  source = active ? Experiments.load(active) : Experiments.starter_source(STARTER_LABEL)
  preview, error = render(source)

  model.with(
    files: remaining,
    active_file: active,
    source: source,
    preview: preview,
    error: error,
    dirty: false,
    undo_stack: Plushie::Undo.new(source),
    selection: Plushie::Selection.clear(model.selection)
  )
end
```

Clearing the selection after the bulk delete prevents stale IDs
referring to files that no longer exist. If you skip the clear, the
checkbox state goes out of sync with the rendered list.

Wire the trigger into the toolbar:

```ruby
button("delete-selected", "Delete selected",
  style: :danger,
  enabled: !Plushie::Selection.selected(model.selection).empty?)
```

For shift-click range selection, construct the selection with an
`order:` list matching the rendered order, rebuild it whenever the
file list changes, and route shift-clicks to `range_select`.
Ctrl-click (or Cmd-click on macOS) maps to `select(..., extend:
true)` for additive selection; plain clicks stay on `toggle` so the
default matches platform expectations.

## Plushie::DataQuery

`Plushie::DataQuery` is a query pipeline for in-memory record
collections. It takes an array of hashes and returns a result hash
keyed by `:entries`, `:total`, `:page`, `:page_size`, and `:groups`.
The pipeline applies `:filter`, `:search`, `:sort`, then pagination,
and finally `:group` on the paginated slice.

```ruby
records = [
  {name: "Alice", role: "dev"},
  {name: "Bob",   role: "design"},
  {name: "Carol", role: "dev"}
]

result = Plushie::DataQuery.query(records,
  search: [[:name, :role], "dev"],
  sort:   [:asc, :name],
  page:   1,
  page_size: 10)

result[:entries]  # [{name: "Alice", ...}, {name: "Carol", ...}]
result[:total]    # 2
result[:page]     # 1
```

The options:

| Option | Shape | Description |
|---|---|---|
| `:filter` | `->(record) { ... }` | Keeps records for which the proc returns truthy |
| `:search` | `[[fields], query_string]` | Case-insensitive substring match across the named fields |
| `:sort` | `[:asc, field]` or `[[dir, field], ...]` | Sort by one or more fields |
| `:page` | Integer | 1-based page number (default 1) |
| `:page_size` | Integer | Records per page (default 25) |
| `:group` | Symbol | Groups paginated entries by the field |

Records are expected to be symbol-keyed hashes. Anything that
responds to `[]` and `fetch` the same way (a `Data` struct,
`OpenStruct`) works too.

Repeated `:sort` pairs act as tiebreakers: `[[:asc, :role], [:asc,
:name]]` sorts by role first, then by name within a role. `:filter`
and `:search` are single-entry in the keyword form; if you need
more than one stage, chain two `DataQuery.query` calls and feed the
first `:entries` into the second.

Skip `:search` entirely when the query is empty; guard with a
conditional build:

```ruby
options = {sort: [:asc, :name]}
options[:search] = [[:name], query] unless query.empty?
result = Plushie::DataQuery.query(records, **options)
```

### Applying it: a search box for the sidebar

Add a search input above the file list that narrows the sidebar to
matching names. The pad's `files` field is an array of strings; map
them into hashes so `DataQuery` has a keyed field to match against.

Extend the model and initialise the field:

```ruby
Model = Plushie::Model.define(
  # ... existing fields ...
  :file_query   # String
)

def init(_opts)
  # ...
  Model.new(
    # ...
    file_query: ""
  )
end
```

Wire the input event:

```ruby
in Event::Widget[type: :input, id: "file-search", value: q]
  model.with(file_query: q)
```

Compute the visible file list inside the sidebar view. When the
query is empty, render the raw list; when it's non-empty, run it
through `DataQuery`:

```ruby
def visible_files(model)
  return model.files if model.file_query.empty?

  records = model.files.map { |name| {name: name} }
  result = Plushie::DataQuery.query(records,
    search: [[:name], model.file_query],
    sort:   [:asc, :name])
  result[:entries].map { |r| r[:name] }
end

def sidebar(model)
  container("sidebar-wrap",
    width: 200,
    height: :fill,
    border: Plushie::Type::Border.from_opts(color: "#333333", width: 1)) do
    column("sidebar", spacing: 4, padding: 8) do
      text_input("file-search", model.file_query, placeholder: "Search...")
      scrollable("sidebar-list", height: :fill) do
        column("files", spacing: 4) do
          visible_files(model).each { |file| file_row(model, file) }
        end
      end
    end
  end
end
```

`view` stays pure: the filtered list is derived every render from
`model.files` and `model.file_query`. For lists where the filter
is expensive, debounce the input with `Plushie::Command.send_after`
(see the [Commands reference](../reference/commands.md)).

## When to reach for each helper

Pick the one that matches the shape of the state you're tracking:

- **Editors with reversible actions**: `Plushie::Undo`. Text
  editors, drawing canvases, form builders. Anything where Ctrl+Z
  is an expected affordance.
- **Multi-view apps**: `Plushie::Route`. Editor / settings splits,
  list / detail drill-downs, wizards. If `view` needs a `case` on
  "which screen am I on", route is the storage.
- **Lists with row selection**: `Plushie::Selection`. File
  managers, inboxes, bulk-edit tables. Skip it for single-row
  highlighting when the active item is already in the model; an
  `active_file` field is simpler than a one-element selection.
- **Filterable / sortable collections**: `Plushie::DataQuery`.
  Search boxes, sortable tables, paginated lists.

The helpers compose. The pad now uses all four: `Plushie::Undo`
wraps the editor buffer, `Plushie::Route` switches between editor
and settings, `Plushie::Selection` tracks sidebar multi-selection,
and `Plushie::DataQuery` filters the sidebar list. Each field is
independent, so changes to one don't ripple into the others.

## Exercise: a "Recently opened" view

Add a third screen to the pad listing files opened this session,
most recent first, with a search box. Combining `Plushie::Route`
and `Plushie::DataQuery` covers the full feature.

Add a `recents` field to the model as an array of hashes:
`[{name: "hello.rb", opened_at: 1_730_000_000}, ...]`. Push a new
entry at the head inside `switch_file`, dropping any earlier entry
for the same name so the list does not accumulate duplicates. Cap
the list with `.first(20)`.

Add a "Recent" button to the toolbar that pushes `:recents` onto
the route, and a third arm to the top-level `case` in `view` that
renders a `text_input("recent-query", model.recent_query, ...)`
above a scrollable list. Filter through `Plushie::DataQuery`
searching on the `:name` field and sorting by `:opened_at`
descending, guarding `:search` so an empty query doesn't drop
everything.

Clicking a row should pop the route back to `:editor` and call
`switch_file` with the chosen name. That's two operations in one
update arm: set the new route and load the file. Return the
composed model in one `with` call.

Bonus: add a `pick_list` above the list that switches the sort
between "most recent" and "alphabetical". Store the choice in the
model and pass it to `DataQuery` as the `:sort` tuple.

## See also

- [Composition Patterns reference](../reference/composition-patterns.md),
  recipes that combine these helpers with widgets: tabs, modals,
  sortable tables, filter pipelines
- [Custom Types reference](../reference/custom-types.md), the prop
  types consumed when you render selection highlights, route-driven
  layouts, and sortable columns
- [Events reference](../reference/events.md), the `:toggle`,
  `:click`, and `:input` event shapes and how `scope:` composes
  through nested containers
- [Commands reference](../reference/commands.md),
  `Plushie::Command.focus` and `Plushie::Command.send_after` for
  focus management and debounced searches

## Next chapter

[Testing](15-testing.md)
