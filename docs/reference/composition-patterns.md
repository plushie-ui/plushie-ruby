# Composition Patterns

Recipes for common UI structures built from Plushie's built-in
widgets and state helpers. These are not special framework features;
they compose the same widgets, commands, subscriptions, and helpers
documented elsewhere in this reference. Each pattern shows a view
excerpt, the relevant `update` branches, and notes on when to reach
for it.

| Section | Patterns |
|---|---|
| [Navigation](#navigation) | Tabs, sidebar, breadcrumbs, route stack |
| [Overlays](#overlays) | Popover menu, modal dialog, tooltip, context menu, loading state, confirmation |
| [Layout](#layout-patterns) | Toolbar, split panes, sidebar and content, empty state |
| [Forms](#forms) | Labelled inputs, validated field, search and filter |
| [Feedback](#feedback) | Error banner, loading placeholder |
| [Lists](#lists) | Scrollable keyed lists, single and multi selection |
| [State helpers](#state-helpers) | `Plushie::Route`, `Plushie::Selection`, `Plushie::DataQuery`, `Plushie::Undo` |

Overlays (modals, popovers, context menus) belong at the **window
level** inside a `stack` so they are not scrolled or clipped by
inner containers. If you nest an overlay inside a scrollable or a
fixed-height container, it scrolls or clips with that container.

## Navigation

### Tabs

Buttons in a row with conditional body content. Track the active
tab in the model and branch on it when picking the pane to render.

```ruby
def view(model)
  window("main", title: "Tabs") do
    column(width: :fill) do
      row(spacing: 0) do
        tab_button("overview", "Overview", model)
        tab_button("details",  "Details",  model)
        tab_button("settings", "Settings", model)
      end
      rule

      case model.active_tab
      when :overview then overview_pane(model)
      when :details  then details_pane(model)
      when :settings then settings_pane(model)
      end
    end
  end
end

def tab_button(name, label, model)
  button("tab:#{name}", label,
    style: (model.active_tab == name.to_sym) ? :primary : :text)
end

def update(model, event)
  case event
  in Event::Widget[type: :click, id: "tab:overview"]
    model.with(active_tab: :overview)
  in Event::Widget[type: :click, id: "tab:details"]
    model.with(active_tab: :details)
  in Event::Widget[type: :click, id: "tab:settings"]
    model.with(active_tab: :settings)
  else
    model
  end
end
```

### Sidebar and content

A fixed-width navigation column alongside a filling content area.
The sidebar has a pixel width; the content uses `:fill` to take the
remainder.

```ruby
row(width: :fill, height: :fill) do
  column("nav", width: 220, height: :fill, padding: 8, spacing: 4) do
    model.nav.each do |item|
      button(item.id, item.label,
        width: :fill,
        style: (item.id == model.active) ? :primary : :text)
    end
  end

  container("content", width: :fill, height: :fill, padding: 16) do
    render_active_page(model)
  end
end
```

See the [Layout reference](windows-and-layout.md#sidebar--content)
for the sizing mechanics.

### Breadcrumbs

Interleave text separators with clickable buttons. The final segment
is plain text (the current location) so it isn't interactive.

```ruby
row("crumbs", spacing: 4) do
  model.breadcrumbs.each_with_index do |segment, i|
    text("sep-#{i}", "/", size: 12, color: "#999") if i.positive?

    if i == model.breadcrumbs.length - 1
      text("crumb-#{i}", segment, size: 12)
    else
      button("crumb-#{i}", segment, style: :text)
    end
  end
end
```

### Route-driven dispatch

`Plushie::Route` is a navigation stack keyed by path plus optional
params. Push on navigation, pop for back, read `Route.current` in
the view.

```ruby
def init(_opts) = Model.new(route: Plushie::Route.new(:list))

def view(model)
  window("main", title: "App") do
    case Plushie::Route.current(model.route)
    when :list     then list_view(model)
    when :detail   then detail_view(model, Plushie::Route.params(model.route))
    when :settings then settings_view(model)
    end
  end
end

def update(model, event)
  case event
  in Event::Widget[type: :click, id: "show-detail", scope: [item_id, *]]
    model.with(route: Plushie::Route.push(model.route, :detail, id: item_id))

  in Event::Widget[type: :click, id: "back"]
    model.with(route: Plushie::Route.pop(model.route))

  else
    model
  end
end
```

`Plushie::Route.pop` refuses to remove the root entry, so the app
can't navigate below its starting path. `Plushie::Route.can_go_back?`
tells you whether to show a back button.

## Overlays

The window-level `stack` holds every floating surface: modals,
context menus, toasts, loading overlays. Conditional `nil` values
are filtered out by `stack`, so you can write expressive
`model.show_modal && modal_overlay(model)` guards.

```ruby
def view(model)
  window("main", title: "App") do
    stack(width: :fill, height: :fill) do
      main_content(model)

      modal_overlay(model)   if model.show_modal
      context_menu(model)    if model.context_menu
      loading_overlay        if model.loading
    end
  end
end
```

### Popover menu

The `overlay` widget takes exactly two children: the anchor first,
the floating panel second. `flip: true` repositions the panel when
it would overflow the viewport.

```ruby
overlay("options", position: :below, gap: 4, flip: true) do
  button("options-trigger", "Options")

  container("options-panel",
    padding: 8,
    background: "#ffffff",
    border: Plushie::Type::Border.from_opts(
      color: "#dddddd", width: 1, rounded: 4)) do
    column(spacing: 2) do
      button("opt-edit",   "Edit",   style: :text, width: :fill)
      button("opt-delete", "Delete", style: :text, width: :fill)
    end
  end
end
```

`position:` accepts `:below`, `:above`, `:left`, `:right`. See the
overlay section in [Built-in Widgets](built-in-widgets.md#overlay)
for the full prop list.

### Modal dialog

A semi-transparent backdrop filling the window with a centred card
on top. `container(center: true)` centres its child on both axes.

```ruby
def modal_overlay(model)
  container("modal-backdrop",
    width: :fill, height: :fill,
    background: "#00000088", center: true) do

    container("modal-card", padding: 24, background: "#ffffff",
      border: Plushie::Type::Border.from_opts(rounded: 8)) do
      column(spacing: 12) do
        text("modal-title", "Delete item?", size: 18)
        text("modal-body", "This action cannot be undone.")
        row(spacing: 8) do
          button("modal-cancel",  "Cancel")
          button("modal-confirm", "Delete", style: :danger)
        end
      end
    end
  end
end

def update(model, event)
  case event
  in Event::Widget[type: :click, id: "delete", scope: [item_id, *]]
    model.with(show_modal: true, pending_id: item_id)

  in Event::Widget[type: :click, id: "modal-confirm"]
    model.with(items: model.items.reject { |i| i.id == model.pending_id },
               show_modal: false, pending_id: nil)

  in Event::Widget[type: :click, id: "modal-cancel"]
    model.with(show_modal: false, pending_id: nil)

  in Event::Key[type: :press, key: "Escape"]
    model.with(show_modal: false, pending_id: nil)

  else
    model
  end
end
```

Handle `Escape` so keyboard users can dismiss the modal. After
closing, return focus to the element that opened it (see
[focus management](#focus-management)).

### Tooltips

`tooltip` wraps a single anchor child. Position defaults to
`:bottom`; `:follow_cursor` tracks the mouse.

```ruby
tooltip("save-tip", "Saves unsaved changes", position: :top, delay: 400) do
  button("save", "Save")
end
```

`delay:` is the milliseconds to wait before showing the tip, which
avoids flashing tooltips during quick cursor passes.

### Context menu

Right-click uses `pointer_area(on_right_press: true)`. The menu
renders at the window-level stack using `pin` for absolute
positioning at the cursor.

```ruby
pointer_area("row-#{item.id}", on_right_press: true) do
  text("label-#{item.id}", item.name)
end

def update(model, event)
  case event
  in Event::Widget[type: :press, scope: [src, *],
      value: { button: :right, x:, y: }]
    model.with(context_menu: { source: src, x:, y: })

  in Event::Key[type: :press, key: "Escape"]
    model.with(context_menu: nil)

  else
    model
  end
end

# In the window-level stack:
if model.context_menu
  pin do
    container("ctx", padding: 4, background: "#ffffff",
      border: Plushie::Type::Border.from_opts(color: "#ddd", width: 1, rounded: 4)) do
      column(spacing: 2) do
        button("ctx-edit",   "Edit",   style: :text, width: :fill)
        button("ctx-delete", "Delete", style: :text, width: :fill)
      end
    end
  end
end
```

The `:press` event's `value` hash carries `x`, `y`, `button`, and
`modifiers`. See the [Events reference](events.md#pointer-events)
for every field.

### Loading state

Conditionally add a translucent overlay while async work is in
flight. Place it at the window-level stack so it covers scrollable
content.

```ruby
def loading_overlay
  container("loading",
    width: :fill, height: :fill,
    background: "#ffffff88", center: true) do
    text("loading-msg", "Loading...", size: 16)
  end
end

def update(model, event)
  case event
  in Event::Widget[type: :click, id: "fetch"]
    [model.with(loading: true),
     Plushie::Command.task(-> { fetch_data }, :fetched)]

  in Event::Async[tag: :fetched, result: data]
    model.with(loading: false, data: data)

  else
    model
  end
end
```

Use `progress_bar` when you have a real fraction to report; a
`text` placeholder covers the indeterminate case.

### Confirmation dialog

A modal specialised for yes/no choices. Queue the action in
`model.pending` so the dialog itself stays generic.

```ruby
def confirm_dialog(message)
  container("confirm-backdrop",
    width: :fill, height: :fill,
    background: "#00000066", center: true) do
    container("confirm-card", padding: 20, background: "#ffffff",
      border: Plushie::Type::Border.from_opts(rounded: 8)) do
      column(spacing: 12) do
        text("confirm-msg", message)
        row(spacing: 8) do
          button("confirm-no",  "No")
          button("confirm-yes", "Yes", style: :primary)
        end
      end
    end
  end
end

def update(model, event)
  case event
  in Event::Widget[type: :click, id: "confirm-yes"]
    apply_pending(model).with(pending: nil)
  in Event::Widget[type: :click, id: "confirm-no"]
    model.with(pending: nil)
  else
    model
  end
end
```

## Layout patterns

### Toolbar

A row with button groups separated by `rule` dividers or `space`.
`space(width: :fill)` expands to push trailing items to the right.

```ruby
row("toolbar", spacing: 4, padding: [4, 8]) do
  button("bold", "B")
  button("italic", "I")
  rule("sep-1", direction: :vertical, height: 20)

  button("align-left",   "Left")
  button("align-center", "Centre")

  space(width: :fill)

  button("settings", "Settings")
end
```

### Split panes

Use `pane_grid` when you want the renderer to manage resizable
panes for you. The children's IDs must match the entries in the
`panes:` list.

```ruby
pane_grid("editor", panes: %w[nav source preview], spacing: 2) do
  container("nav",     padding: 8) { file_tree(model) }
  text_editor("source", model.source, highlight_syntax: "ruby")
  container("preview", padding: 8) { rendered_preview(model) }
end
```

The renderer persists pane sizes by the pane grid's ID. Events
arrive as `Event::Widget[type: :pane_resized, ...]` and friends;
see the [Built-in Widgets reference](built-in-widgets.md#pane-grid)
for the full event catalog.

For a hand-rolled two-pane split with a draggable divider, combine
`pointer_area` with a subscription that feeds pointer-move events
while dragging:

```ruby
row("split", width: :fill, height: :fill) do
  container("left", width: model.split_x, height: :fill) { left_pane(model) }

  pointer_area("divider",
    cursor: :resizing_horizontally,
    on_press: "drag-start",
    on_release: "drag-end") do
    container("handle", width: 4, height: :fill, background: "#dddddd")
  end

  container("right", width: :fill, height: :fill) { right_pane(model) }
end

def subscribe(model)
  model.dragging ? [Plushie::Subscription.on_pointer_move(max_rate: 60)] : []
end
```

Subscriptions are recomputed every render, so flipping
`model.dragging` in `update` transparently starts and stops the
global pointer feed.

### Empty state

A centred placeholder when a collection is empty. Use
`container(center: true)` with a `column` of illustration, title,
and call-to-action.

```ruby
def empty_state
  container("empty", width: :fill, height: :fill, center: true) do
    column(spacing: 8, align_x: :center) do
      text("empty-title", "Nothing here yet", size: 18, color: "#6b7280")
      text("empty-body",  "Create your first item to get started.",
        color: "#9ca3af")
      button("empty-cta", "Create item", style: :primary)
    end
  end
end

def view(model)
  window("main") do
    if model.items.empty?
      empty_state
    else
      item_list(model)
    end
  end
end
```

## Forms

### Labelled input column

A column of label, input, and inline help, repeated per field.
Spacing separates fields; `width: :fill` on the inputs keeps them
consistent.

```ruby
column("form", spacing: 16, padding: 16, width: :fill) do
  column("email-field", spacing: 4) do
    text("email-label", "Email", size: 12, color: "#374151")
    text_input("email", model.email, placeholder: "you@example.com", width: :fill)
    text("email-help", "We only use this for notifications.", size: 12, color: "#6b7280")
  end

  column("name-field", spacing: 4) do
    text("name-label", "Display name", size: 12)
    text_input("name", model.name, width: :fill)
  end

  row(spacing: 8) do
    button("submit", "Save", style: :primary)
    button("cancel", "Cancel")
  end
end
```

### Validated field

Show an inline error under an input and thread the accessibility
state through so screen readers announce it.

```ruby
def email_field(model)
  column("email-field", spacing: 4) do
    text("email-label", "Email", size: 12)
    text_input("email", model.email, placeholder: "Email",
      a11y: { required: true, invalid: !model.email_error.nil? })

    if model.email_error
      text("email-error", model.email_error, color: "#ef4444", size: 12)
    end
  end
end

def update(model, event)
  case event
  in Event::Widget[type: :input, id: "email", value:]
    error = value.include?("@") ? nil : "Must be a valid email"
    model.with(email: value, email_error: error)
  else
    model
  end
end
```

Validation errors go on the model; `view` reads them. Never
compute errors inside `view`, keep it a pure projection.

### Search and filter

A text input that filters a list in real time. `Plushie::DataQuery`
accepts a `search:` pair, a `filter:` lambda, and a `sort:` spec,
and returns a hash with `:entries`, `:total`, `:page`, and
`:page_size` keys.

```ruby
column("search-view", spacing: 8) do
  text_input("search", model.query, placeholder: "Search...")

  keyed_column("results", spacing: 4) do
    filtered(model).each do |item|
      container(item.id, padding: 8) do
        text("#{item.id}-name", item.name)
      end
    end
  end
end

private

def filtered(model)
  return model.items if model.query.empty?

  Plushie::DataQuery.query(model.items,
    search: [[:name, :email], model.query])[:entries]
end

def update(model, event)
  case event
  in Event::Widget[type: :input, id: "search", value:]
    model.with(query: value)
  else
    model
  end
end
```

For long queries, debounce with `Plushie::Command.send_after` so
expensive searches only run after the user stops typing.

## Feedback

### Error banner

A conditionally rendered container anchored at the top of the body.
Colour the banner by severity and clear it on dismiss.

```ruby
def error_banner(model)
  return nil unless model.error

  container("banner", padding: [8, 16], background: "#fee2e2",
    border: Plushie::Type::Border.from_opts(color: "#fecaca", width: 1, rounded: 4)) do
    row(spacing: 8) do
      text("banner-msg", model.error, color: "#991b1b", size: 14)
      space(width: :fill)
      button("banner-dismiss", "x", style: :text)
    end
  end
end
```

Return `nil` when there is nothing to show; `column` and `stack`
both filter `nil` children, so the banner disappears cleanly.
Match `Event::Widget[type: :click, id: "banner-dismiss"]` to clear
`model.error`.

### Loading placeholder

For a placeholder that swaps out to real content on `Event::Async`,
render skeleton rows while `model.loading` is set and a
`progress_bar` when the fraction is known.

```ruby
if model.loading
  progress_bar("upload", [0, 100], model.upload_percent, width: :fill)
end
```

## Lists

### Scrollable keyed list

For dynamic lists where items are added, removed, or reordered, use
`keyed_column` inside a `scrollable`. `keyed_column` diffs by child
ID so widget state (scroll position, focus, cursor) survives list
changes; a plain `column` diffs by position.

```ruby
scrollable("log", height: 400, direction: :vertical, auto_scroll: true) do
  keyed_column("entries", spacing: 4) do
    model.entries.each do |entry|
      container(entry.id, padding: 8) do
        row(spacing: 8) do
          text("#{entry.id}-time", entry.timestamp, size: 12, color: "#6b7280")
          text("#{entry.id}-msg",  entry.message)
        end
      end
    end
  end
end
```

`auto_scroll: true` pins the scroll position to the newest entry
until the user scrolls away; combine with `anchor: :end` for
chat-log or terminal layouts.

### Selection

`Plushie::Selection` tracks the selected set for `:single`, `:multi`,
or `:range` modes. Read it in `view` to highlight rows; update it
from row-click events.

**Multi selection:**

```ruby
def init(_opts)
  Model.new(items: load_items,
            selection: Plushie::Selection.new(mode: :multi))
end

def view(model)
  keyed_column("items", spacing: 4) do
    model.items.each do |item|
      selected = Plushie::Selection.selected?(model.selection, item.id)
      container(item.id,
        padding: 8,
        style: selected ? :primary : :transparent) do
        row(spacing: 8) do
          checkbox("select", selected)
          text("#{item.id}-name", item.name)
        end
      end
    end
  end
end

def update(model, event)
  case event
  in Event::Widget[type: :toggle, id: "select", scope: [item_id, *]]
    model.with(selection: Plushie::Selection.toggle(model.selection, item_id))
  else
    model
  end
end
```

**Table selection** uses the same helper; pass the set of selected
IDs via the table's `selected:` prop and toggle on `:row_click`:

```ruby
table("users",
  columns: cols,
  rows:    model.users.map(&:to_h),
  selected: Plushie::Selection.selected(model.selection).to_a)

in Event::Widget[type: :row_click, id: "users", value: row_id]
  model.with(selection: Plushie::Selection.toggle(model.selection, row_id))
```

For shift-click ranges, initialise with an `order:` list matching
the rendered order, then use `Plushie::Selection.range_select` on
shift-click.

## State helpers

### Route

See [Route-driven dispatch](#route-driven-dispatch) above for
push/pop navigation. `Plushie::Route.history(route)` returns the
full stack if you want to render a navigation trail.

### DataQuery with sort controls

Render sortable headers, track the active column and direction in
the model, feed both into `Plushie::DataQuery.query`. `:filter`,
`:search`, and `:sort` compose as successive narrowing steps; the
result is a hash with `:entries`, `:total`, `:page`, and
`:page_size` keys.

```ruby
def users_page(model)
  result = Plushie::DataQuery.query(model.users,
    search: model.query.empty? ? nil : [[:name, :email], model.query],
    sort:   [model.sort_dir, model.sort_field],
    page:   model.page,
    page_size: 25)

  keyed_column("rows", spacing: 4) do
    result[:entries].each { |user| user_row(user) }
  end
end
```

Pair with the built-in `table` widget's `:sort` event for sortable
columns: clicking a `sortable: true` header emits
`Event::Widget[type: :sort, id: "users", value: col_key]`, which
your `update` uses to flip `model.sort_dir` and re-run the query.

### Undo with coalesced typing

`Plushie::Undo` stores commands with an `apply` proc and an `undo`
proc. Commands sharing a `:coalesce` key within
`:coalesce_window_ms` merge into a single entry, so a run of
keystrokes becomes one Ctrl+Z target.

```ruby
def init(_opts)
  Model.new(undo: Plushie::Undo.new({ body: "" }))
end

def view(model)
  state = Plushie::Undo.current(model.undo)
  window("main", title: "Editor") do
    column(spacing: 8, padding: 16) do
      text_editor("body", state[:body])
    end
  end
end

def update(model, event)
  case event
  in Event::Widget[type: :input, id: "body", value: new_text]
    previous = Plushie::Undo.current(model.undo)[:body]
    cmd = {
      apply: ->(s) { s.merge(body: new_text) },
      undo:  ->(s) { s.merge(body: previous) },
      coalesce: :typing,
      coalesce_window_ms: 500
    }
    model.with(undo: Plushie::Undo.push(model.undo, cmd))

  in Event::Key[type: :press, key: "z", modifiers: { command: true, shift: false }]
    model.with(undo: Plushie::Undo.undo(model.undo))

  in Event::Key[type: :press, key: "z", modifiers: { command: true, shift: true }]
    model.with(undo: Plushie::Undo.redo(model.undo))

  else
    model
  end
end
```

The `:command` modifier is platform-aware: Ctrl on Linux and
Windows, Cmd on macOS. `Plushie::Undo.can_undo?` and
`Plushie::Undo.can_redo?` tell the toolbar which buttons to enable.

## Focus management

Return focus to a sensible location after destructive actions or
when closing dialogs. Losing focus strands keyboard and screen
reader users.

```ruby
in Event::Widget[type: :click, id: "delete", scope: [item_id, *]]
  remaining = model.items.reject { |i| i.id == item_id }
  cmd = remaining.first ?
    Plushie::Command.focus("#{remaining.first.id}/select") :
    Plushie::Command.none
  [model.with(items: remaining), cmd]

in Event::Widget[type: :click, id: "modal-confirm"]
  [apply_pending(model).with(show_modal: false),
   Plushie::Command.focus(model.modal_opener_id)]
```

`Plushie::Command.focus_next_within(scope)` and
`Plushie::Command.focus_previous_within(scope)` cycle focus within
a named subtree, useful for trapping tab focus inside an open
modal. The plain `Plushie::Command.focus_next` and
`Plushie::Command.focus_previous` walk the whole view's tab order.

## See also

- [Built-in Widgets reference](built-in-widgets.md) - widget
  catalog with prop tables
- [Windows and Layout reference](windows-and-layout.md) - sizing,
  alignment, containers
- [Events reference](events.md) - full event taxonomy and
  pattern-matching cookbook
- [Accessibility reference](accessibility.md) - the `a11y` prop,
  roles, and keyboard navigation
