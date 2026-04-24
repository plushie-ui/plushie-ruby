# Scoped IDs

Named containers automatically scope their children's IDs, producing
unique hierarchical paths without manual prefixing. This is how you
distinguish "the delete button in file A" from "the delete button in
file B" without having to encode the parent context into every child
ID yourself. The scoping logic lives in `Plushie::Tree.normalize`.

## Scoping rules

| Node type | Creates scope? | Notes |
|---|---|---|
| Named container (explicit string ID) | Yes | ID pushed onto the scope chain |
| Auto-ID container (`"auto:..."` prefix) | No | Transparent, no scope effect |
| Window node (`type: "window"`) | Yes | Uses `#` separator instead of `/` |
| Custom widget | No | Widget IDs are transparent to scoping |

User-provided IDs must not contain `/` or `#`. The slash is reserved
for the scope separator, and `#` is reserved for the window boundary
(for example, `"main#form/email"`). `Plushie::Tree.normalize` raises
`ArgumentError` on violation, alongside the other ID validation rules
(non-empty, printable ASCII, at most 1024 bytes).

## ID resolution

During normalisation, the scope chain builds canonical wire IDs.
Window nodes use `#` as the separator; containers within a window
use `/`:

```
main (window)               ->  "main"
  sidebar (container)       ->  "main#sidebar"
    form (container)        ->  "main#sidebar/form"
      email (text_input)    ->  "main#sidebar/form/email"
      save (button)         ->  "main#sidebar/form/save"
```

The `#` appears exactly once, at the window boundary. Deeper nesting
uses `/`. The canonical wire format is `window#scope/path/id`.

Resolution is recursive and nesting depth is unlimited up to
`Plushie::Tree::MAX_DEPTH` (a warning is emitted when the depth
approaches the cap, to flag widgets that accidentally compose
themselves).

### Auto-ID containers are transparent

Layout containers without an explicit ID (`column`, `row`, `stack`,
`grid`, `keyed_column`, `pin`, `floating`, `overlay`, `themer`) and
some display widgets (`text`, `rule`, `space`, `table`) receive an
auto-generated ID derived from the call site, for example
`"auto:view:42"`. These IDs are transparent: they do not push anything
onto the scope chain.

```ruby
container("form") do
  column(spacing: 8) do          # auto-ID, no scope effect
    text_input("email", "")      # scoped as "form/email"
    button("save", "Save")       # scoped as "form/save"
  end
end
```

This is intentional. Intermediate layout containers exist for visual
arrangement, not semantic grouping. Only named containers (those you
give an explicit string ID) create scope boundaries.

Auto-IDs are **unstable across code changes**: the ID is derived from
`caller_locations` and embeds the enclosing method name and line
number. Any refactor that moves the call to a different line changes
the generated ID, which invalidates any state or test selector that
referenced it.

### Stateful widgets require explicit IDs

All interactive and stateful widgets take the ID as their first
positional argument: `button`, `text_input`, `text_editor`, `checkbox`,
`toggler`, `radio`, `slider`, `vertical_slider`, `pick_list`,
`combo_box`, `scrollable`, `pane_grid`, `responsive`, `tooltip`,
`container`, `image`, `svg`, `markdown`, `qr_code`, `sensor`,
`pointer_area`, `canvas`, `canvas_interactive`. Use stable,
human-readable IDs. State like cursor position, scroll offset, and
combo-box search text is keyed by the scoped ID, so changing the ID
discards the state.

### Custom widgets are transparent

Custom widgets declared with `Plushie::Widget.define` do **not**
create scopes for the children their `view` method renders. Those
children inherit the **parent's** scope, not the widget's:

```ruby
# If MyWidget has ID "my-widget" and renders a button "save":
container("form") do
  my_widget("my-widget", label: "Submit")
end

# The button inside MyWidget is scoped as "form/save",
# NOT "form/my-widget/save".
```

Custom widgets are invisible to the scope chain. Events from widgets
inside a custom widget carry the enclosing container's scope, not the
custom widget's ID. The widget's `handle_event` callback intercepts
events before they reach `update`, providing the encapsulation layer
instead.

## Duplicate sibling detection

Normalisation detects two children of the same parent that share the
same ID and raises `ArgumentError`:

```
duplicate sibling IDs detected during normalize: "save"
```

Detection is sibling-scoped. The same local ID can exist in different
scopes safely, because the scope prefix makes the wire ID globally
unique:

```ruby
container("form-a") do
  button("save", "Save")   # "form-a/save"
end

container("form-b") do
  button("save", "Save")   # "form-b/save", no conflict
end
```

When the duplicate comes from an auto-ID (common in dynamic lists
where two iterations hit the same call site), the error message
steers you toward giving each item an explicit ID.

## Dynamic IDs

IDs can be any string expression, including values from your model.
This is how you scope list items:

```ruby
model.files.each do |file|
  container(file.id) do
    button("select", file.name)
    button("delete", "x")
  end
end
```

Each file becomes a scope. The delete button for `"hello.rb"` gets
the wire ID `"hello.rb/delete"`. In the event, you extract the
filename from the scope:

```ruby
case event
in Event::Widget[type: :click, id: "delete", scope: [file, *]]
  delete_file(model, file)
end
```

Dynamic IDs follow the same rules as static IDs: no `/`, no `#`, no
duplicates among siblings, printable ASCII only.

### Using IDs as keys for dynamic lists

`keyed_column` diffs its children by ID rather than by position. Give
each item a stable ID from your data (a row PK, a UUID, anything that
survives reordering), and the renderer preserves widget state and
animation continuity across inserts, removals, and reorders.

```ruby
keyed_column(spacing: 4) do
  model.items.each do |item|
    container(item.id) do
      text("label", item.name)
      button("delete", "x")
    end
  end
end
```

Index-based IDs (`"item_#{i}"`) defeat this: inserting at the head
renumbers every subsequent child, which the diff sees as "every row
changed" rather than "one row was inserted". Prefer identity-derived
IDs.

## Event scope field

When the renderer emits a widget event, the wire ID is the canonical
`window#scope/path/id` string. `Plushie::Protocol::Decode` splits it
into three parts on the event struct:

- `id`: the local (unscoped) widget ID
- `scope`: the ancestor chain, reversed so the immediate parent is
  first and the `window_id` is the last element
- `window_id`: a separate flat field, also the last element of `scope`

```ruby
Event::Widget[
  type: :click,
  id: "save",
  scope: ["form", "sidebar", "main"],
  window_id: "main"
]
```

The scope is reversed so `[parent, *]` patterns match the immediate
parent without needing to know the full ancestry. The window ID
always sits at the end of `scope`, giving you the full hierarchy from
innermost container to outermost window.

### Pattern matching examples

```ruby
case event
# Local ID only (any scope)
in Event::Widget[type: :click, id: "save"]
  ...

# Immediate parent match (window_id at end doesn't affect [parent, *])
in Event::Widget[type: :click, id: "save", scope: ["form", *]]
  ...

# Bind the dynamic parent (list items)
in Event::Widget[type: :toggle, id: "done", scope: [item_id, *]]
  ...

# Match by window
in Event::Widget[id: "save", window_id: "settings"]
  ...

# Top-level widget inside a window (only the window in scope)
in Event::Widget[id: "save", scope: [window_id]]
  ...
end
```

Only `Event::Widget` and `Event::Ime` carry a scope. Other event
classes (`Event::Key`, `Event::Modifiers`, `Event::Timer`,
`Event::Window`, effect results) are global or window-level and have
no container scope. Subscription pointer events arrive as
`Event::Widget` with `id` set to the window ID and `scope: []`.

## Path reconstruction

`Plushie::Event.target` reconstructs the full forward-order path from
an event's `id` and `scope`. The `window_id` is stripped from the
trailing position of `scope` because it is not part of the container
path:

```ruby
event = Event::Widget.new(
  type: :click, id: "save",
  scope: ["form", "sidebar", "main"],
  window_id: "main"
)

Plushie::Event.target(event)
# => "sidebar/form/save"
```

## Accessibility cross-references

A11y props that reference another widget (`labelled_by`,
`described_by`, `error_message`, `active_descendant`, `radio_group`)
accept bare local IDs. During normalisation they are rewritten
against the current scope using the same `#` / `/` separator rules as
scoped IDs. References that already contain `/` or `#` pass through
unchanged. A reference that does not resolve to any declared widget
produces an `a11y_ref_unresolved` warning.

```ruby
container("form") do
  text("email-label", "Email")
  text_input("email", model.email,
    a11y: { labelled_by: "email-label" })
  # labelled_by resolves to "form/email-label" inside the "form" scope
end
```

## Command paths

Commands that target widgets accept either a local ID or a full
scoped path. The forward-slash scoped format works across windows as
long as the widget is unambiguous:

```ruby
Plushie::Command.focus("form/email")
Plushie::Command.scroll_to("sidebar/list", 0.0, 0.0)
```

In multi-window apps, prefix the path with the target window using
`window_id#path`:

```ruby
Plushie::Command.focus("settings#email")
Plushie::Command.scroll_to("main#sidebar/list", 0.0, 0.0)
```

The `#` separates the window ID from the widget path. Without a
window qualifier, the command targets whichever window currently
contains the widget.

## Test selectors

Test helpers (`find!`, `click`, `type_text`, `assert_text`, and
friends under `Plushie::Test::Helpers` and `Plushie::Test::Case`)
accept `#`-prefixed ID selectors, including full scoped paths:

```ruby
find!("#save")                    # local ID, first match
click("#sidebar/form/save")       # full scoped path
assert_text("#form/email", "")    # scoped assertion
```

In multi-window apps, selectors can include a window qualifier using
the `window_id#widget_path` syntax:

```ruby
click("main#save")                 # "save" in window "main"
find!("settings#form/email")       # scoped path in window "settings"
assert_text("main#count", "3")     # assertion scoped to a window
```

`Plushie::Tree::Search.find` matches a bare local ID against the tail
of any scoped wire ID (suffix match at a `/` or `#` boundary), so
`find!("#save")` finds `"main#sidebar/form/save"`. Use the fully
qualified form whenever ambiguity is possible.

## See also

- [Built-in Widgets](built-in-widgets.md) - which DSL methods support
  auto-IDs and which require explicit IDs
- [Events reference](events.md) - the `scope` field on
  `Event::Widget` and `Event::Ime`, and the `Event.target` helper
- [Commands reference](commands.md) - `focus`, `scroll_to`, and the
  other commands that accept scoped widget paths
