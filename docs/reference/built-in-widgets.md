# Built-in Widgets

Every Plushie app builds its UI from widgets. Built-in widgets are
exposed through the block-based DSL mixed in by `Plushie::App`, and
each widget has a typed builder class under `Plushie::Widget::*` for
programmatic construction.

```ruby
# Block DSL (primary form), used inside view/1.
column(padding: 16, spacing: 8) do
  text("greeting", "Hello")
  button("save", "Save", style: :primary)
end

# Typed builder (programmatic form), used when constructing
# subtrees outside a view block:
node = Plushie::Widget::Button.new("save", "Save")
  .set_style(:primary)
  .build
```

The two forms produce the same node shape and can be mixed freely.
Prop names are keyword arguments in the block DSL and use snake_case
throughout, matching the wire encoding.

## Widget catalog

### Layout

| DSL method | Module | Description |
|---|---|---|
| `window` | `Plushie::Widget::Window` | Top-level window with title, size, position, theme |
| `column` | `Plushie::Widget::Column` | Arranges children vertically |
| `row` | `Plushie::Widget::Row` | Arranges children horizontally |
| `container` | `Plushie::Widget::Container` | Single-child wrapper for styling, scoping, alignment |
| `scrollable` | `Plushie::Widget::Scrollable` | Scrollable viewport around child content |
| `stack` | `Plushie::Widget::Stack` | Layers children on top of each other (z-axis) |
| `grid` | `Plushie::Widget::Grid` | Fixed-column or fluid grid layout |
| `keyed_column` | `Plushie::Widget::KeyedColumn` | Vertical layout with ID-based diffing for dynamic lists |
| `responsive` | `Plushie::Widget::Responsive` | Emits resize events for adaptive layouts |
| `pin` | `Plushie::Widget::Pin` | Positions child at absolute coordinates |
| `floating` | `Plushie::Widget::Floating` | Applies translate/scale transforms to child |
| `space` | `Plushie::Widget::Space` | Invisible spacer |

Full prop tables for all layout containers are in the
[Layout reference](windows-and-layout.md).

### Input

| DSL method | Call form | Events (under `Event::Widget`) |
|---|---|---|
| `button` | `button(id, label, **opts)` | `:click` |
| `text_input` | `text_input(id, value, **opts)` | `:input`, `:submit`, `:paste` |
| `text_editor` | `text_editor(id, content, **opts)` | `:input`, `:paste` |
| `checkbox` | `checkbox(id, checked, **opts)` | `:toggle` (value: boolean) |
| `toggler` | `toggler(id, active, **opts)` | `:toggle` (value: boolean) |
| `radio` | `radio(id, label, group:, value:, ...)` | `:select` |
| `slider` | `slider(id, range, value, **opts)` | `:slide`, `:slide_release` |
| `vertical_slider` | `vertical_slider(id, range, value, **opts)` | `:slide`, `:slide_release` |
| `pick_list` | `pick_list(id, options, selected, **opts)` | `:select`, `:open`, `:close` |
| `combo_box` | `combo_box(id, options, value, **opts)` | `:input`, `:select`, `:open`, `:close` |

Every interactive widget emits an `Event::Widget` value. The `type`
field carries the event symbol. See the [Events reference](events.md)
for the full type and pattern-matching guide.

**button** is the simplest interactive widget. The label is the
second positional argument. Emits `:click` on press.

```ruby
button("save", "Save", style: :primary)
```

**text_input** is a single-line editable field. Emits `:input` on
every keystroke with the full text as `value`. Emits `:submit` on
Enter when `on_submit: true` is set, and `:paste` when
`on_paste: true` is set and the user pastes into the field. Use
`text_direction: :auto`, `:ltr`, or `:rtl` to provide the logical
direction hint.

```ruby
text_input("email", model.email, placeholder: "you@example.com", on_submit: true)
```

**text_editor** is a multi-line editable area with syntax
highlighting support (`highlight_syntax: "ruby"`). The `content`
argument seeds the initial text. Holds renderer-side state (cursor,
selection, scroll). Use `text_direction: :auto`, `:ltr`, or `:rtl`
to configure logical direction. Set `on_paste: true` to receive
`:paste` events with the pasted text.

```ruby
text_editor("notes", model.notes, highlight_syntax: "markdown", wrapping: :word)
```

**checkbox** / **toggler** are boolean toggles. Both emit `:toggle`
with the new boolean value. `checkbox` shows a box; `toggler` shows
a switch. Pass the current state as the second positional argument
and `label:` as a keyword for accessible text.

```ruby
checkbox("agree", model.agreed, label: "I agree to the terms")
toggler("dark_mode", model.dark_mode, label: "Dark mode")
```

**slider** / **vertical_slider** are range inputs. `range` is a
two-element `[min, max]` array. Emits `:slide` continuously while
dragging and `:slide_release` when the drag ends with the final
value. Supports `circular_handle: true` for a round handle, with
`handle_radius` controlling the circle's radius (slider only).

```ruby
slider("volume", [0, 100], model.volume, step: 5)
```

**pick_list** is a dropdown selection. `options` is an array of
strings. `selected` is the currently selected value (or `nil`).
Emits `:select` when an option is chosen.

```ruby
pick_list("color", %w[Red Green Blue], model.color)
```

**combo_box** is a searchable dropdown. Combines a text input with
a filtered option list. Holds renderer-side state (search text,
open state). Emits `:input` on typing and `:select` on option
selection.

```ruby
combo_box("country", model.countries, model.country_search, placeholder: "Search...")
```

**radio** is a one-of-many selection. A radio group is expressed
as multiple `radio` calls sharing the same `group:` string. Each
call provides the radio's `value:` and a positional label. The
currently selected value is read from the model and compared
against each radio's `value`.

```ruby
column do
  radio("r1", "Small",  group: "size", value: "s")
  radio("r2", "Medium", group: "size", value: "m")
  radio("r3", "Large",  group: "size", value: "l")
end
```

The renderer highlights the radio whose `value` matches `selected`.
Emits `:select` with the radio's `value`.

### Display

| DSL method | Call form | Description |
|---|---|---|
| `text` | `text(content)` or `text(id, content, **opts)` | Static text display |
| `rich_text` | `rich_text(id, spans, **opts)` | Styled text with per-span formatting |
| `rule` | `rule` or `rule(id, **opts)` | Horizontal or vertical divider |
| `progress_bar` | `progress_bar(id, range, value, **opts)` | Progress indicator |
| `tooltip` | `tooltip(id, tip, **opts) { child }` | Popup tip on hover |
| `image` | `image(id, source, **opts)` | Raster image from file path or URL |
| `svg` | `svg(id, source, **opts)` | Vector image from SVG file or string |
| `qr_code` | `qr_code(id, data, **opts)` | QR code from a data string |
| `markdown` | `markdown(id, content, **opts)` | Rendered markdown |
| `canvas` | `canvas(id, **opts) { layers }` | Drawing surface with named layers |

**text** supports an auto-ID form (`text("Hello")`) and an
explicit-ID form (`text("greeting", "Hello")`). Key props: `size`,
`color`, `font`, `wrapping`, `shaping`, `align_x`, `align_y`.

**rich_text** displays styled text with individually formatted
spans. Each span is a hash with optional keys: `content`, `size`,
`color`, `font`, `link` (clickable URL), `underline`,
`strikethrough`, `line_height`, `padding`, and `highlight`
(background with optional border). A `Plushie::Widget::RichText::Span`
struct can also be used instead of a plain hash.

```ruby
rich_text("greeting", [
  { content: "Hello, ", size: 16 },
  { content: "world", size: 16, color: "#3b82f6", underline: true },
  { content: "!", size: 16 }
])
```

A `rich_text` widget also emits `:link_click` with the link URL as
value when a span with `link:` set is activated.

**tooltip** wraps a child widget. The child is the anchor; `tip`
is the tooltip text. Props: `position` (`:top`, `:bottom`, `:left`,
`:right`, `:follow_cursor`), `gap`, `delay`, `snap_within_viewport`.

```ruby
tooltip("help_tip", "Click to save your work", position: :top) do
  button("save", "Save")
end
```

**image** renders a raster image. Two source modes:

- **Path-based** (preferred): `image("photo", "path/to/file.png")`.
  The renderer loads the file directly. No wire transfer.
- **Handle-based**: pass a handle name previously registered via
  `Plushie::Command.create_image`. References an in-memory image.

Key props: `content_fit`, `filter_method`, `width`, `height`,
`opacity`, `rotation` (degrees), `border_radius`, `scale`, `crop`
(`{x:, y:, width:, height:}`), `alt` (accessible label).

**In-memory image handles:**

```ruby
# Create from encoded PNG/JPEG bytes:
Plushie::Command.create_image("avatar", png_bytes)

# Create from raw RGBA pixels:
Plushie::Command.create_image_rgba("avatar", 512, 512, rgba_pixels)

# Reference in view (by handle name):
image("display", "avatar")

# Update pixels:
Plushie::Command.update_image("avatar", 0, 0, 512, 512, new_pixels)

# Delete:
Plushie::Command.delete_image("avatar")
```

Handle-based images send the entire payload over the wire in a
single message, which blocks all other protocol traffic for large
images. Prefer path-based loading when the file exists on disk.

**canvas** contains named layers of shapes. See the
[Canvas reference](canvas.md).

## Table

`Plushie::Widget::Table`

Displays structured data in rows and columns with sortable headers,
row selection highlighting, and optional striped backgrounds. Rows
are real tree children, so adding, removing, or reordering rows
produces minimal wire patches (LIS-based diffing) instead of
re-sending the entire dataset.

Two row-construction paths are supported. Pass `rows:` for simple
text-only tables, or use the block form with `table_row` and `cell`
for rich cells containing arbitrary widgets. The two are mutually
exclusive; setting both raises at build time.

### Simple text-only rows

```ruby
cols = [
  { key: "name",  label: "Name", sortable: true, width: :fill },
  { key: "email", label: "Email" }
]

table("users",
  columns: cols,
  rows: [
    { name: "Ada",   email: "ada@example.com" },
    { name: "Grace", email: "grace@example.com" }
  ],
  sort_by: "name",
  sort_order: :asc
)
```

### Rich cells

```ruby
table("users", columns: cols, selected: Plushie::Selection.to_list(model.sel)) do
  model.users.each do |user|
    table_row(user.id) do
      cell("name",    text("name-#{user.id}", user.name))
      cell("email",   text("email-#{user.id}", user.email))
      cell("actions", button("del-#{user.id}", "Delete"))
    end
  end
end
```

Each `cell` binds its content to a column by key.

### Columns

Column definitions are hashes passed via the `columns:` prop:

| Key | Type | Default | Description |
|---|---|---|---|
| `key` | string or symbol | required | Row data lookup key |
| `label` | string | required | Header display text |
| `sortable` | boolean | `false` | Header clickable for sort |
| `width` | Length | `:fill` | Column width |
| `align` | `"left"` `"center"` `"right"` | `"left"` | Cell alignment |

All column keys must be the same type (all symbols or all strings).

### Sorting

Mark columns as `sortable: true`. Clicking a sortable header emits
a `:sort` event with the column key as the value. The table shows
the sort indicator but does not reorder rows. Sort in your model:

```ruby
case event
in Event::Widget[type: :sort, id: "users", value: col]
  dir = (model.sort_by == col && model.sort_order == :asc) ? :desc : :asc
  sorted = model.users.sort_by { |u| u[col.to_sym] }
  sorted.reverse! if dir == :desc
  model.with(users: sorted, sort_by: col, sort_order: dir)
end
```

### Selection

Selection is app-managed. Pass selected row IDs via the `selected:`
prop; the renderer highlights those rows. Handle `:row_click` to
update selection state using `Plushie::Selection`:

```ruby
case event
in Event::Widget[type: :row_click, id: "users", value: row_id]
  model.with(sel: Plushie::Selection.toggle(model.sel, row_id))
end
```

### Props

| Prop | Type | Default | Description |
|---|---|---|---|
| `columns` | `[Hash]` | | Column definitions |
| `rows` | `[Hash]` | | Data shorthand for text-only rows |
| `header` | boolean | `true` | Show header row |
| `selected` | `[String]` | | Row IDs to highlight |
| `striped` | boolean | `false` | Alternate row backgrounds |
| `separator` | float | `1.0` | Divider thickness (0.0 to hide) |
| `separator_color` | Color | | Divider colour |
| `sort_by` | string | | Currently sorted column key |
| `sort_order` | `:asc`/`:desc` | | Sort direction |
| `width` | Length | `:fill` | Table width |
| `height` | Length | | Table height (scrollable when set) |
| `padding` | Padding | | Cell internal padding |
| `header_text_size` | number | | Header font size |
| `row_text_size` | number | | Body font size (data shorthand) |

## Pane grid

`Plushie::Widget::PaneGrid`

Resizable tiled pane layout. Children are keyed by their node ID and
rendered as individual panes. The renderer manages internal pane
sizes and arrangement, persisted across re-renders by the widget's
ID.

```ruby
pane_grid("editor", panes: %w[left right], spacing: 2) do
  text_editor("left",  model.left_source)
  text_editor("right", model.right_source)
end
```

### Pane grid props

| Prop | Type | Default | Description |
|---|---|---|---|
| `panes` | `[String]` | | List of pane identifiers |
| `spacing` | number | `2` | Space between panes in pixels |
| `width` | Length | `:fill` | Grid width |
| `height` | Length | `:fill` | Grid height |
| `min_size` | number | `10` | Minimum pane size in pixels |
| `divider_color` | Color | | Colour for the split divider |
| `divider_width` | number | | Divider thickness in pixels |
| `leeway` | number | | Grabbable area around dividers |
| `split_axis` | `:horizontal`/`:vertical` | | Initial split direction |
| `event_rate` | integer | | Max events/sec for coalescable pane events |

### Pane grid events

| Event symbol | Value | Description |
|---|---|---|
| `:pane_clicked` | `{ pane: }` | A pane was selected |
| `:pane_resized` | `{ split:, ratio: }` | A split divider was moved |
| `:pane_dragged` | `{ pane:, target:, action:, region:, edge: }` | Drag in progress |
| `:pane_focus_cycle` | `{ pane: }` | F6 / Shift+F6 focus cycling |

### Usage patterns

Pane identifiers in the `panes:` list determine which children map
to which pane. Each child's ID must match a pane identifier.

The pane grid holds renderer-side state (pane sizes, arrangement).
If the widget's ID changes, this state resets. An explicit string ID
is required.

For accessibility, wrap the pane grid in a container with an
explicit role and label (see the [Accessibility
reference](accessibility.md)).

## Interaction wrappers

### pointer_area

`Plushie::Widget::PointerArea`

Wraps a single child and captures pointer events from mouse, touch,
and pen input. Use for right-click menus, hover detection, drag
tracking, scroll capture, and custom cursor styles. All events use
the unified pointer model: the `pointer` field (`:mouse`, `:touch`,
`:pen`) identifies the device, and `modifiers` carries the current
modifier key state for shift-click, ctrl-drag, and similar patterns.

| Prop | Type | Purpose |
|---|---|---|
| `cursor` | cursor symbol | Mouse cursor on hover |
| `on_press` | string | Left button press event tag |
| `on_release` | string | Left button release event tag |
| `on_right_press` | boolean | Enable right button press |
| `on_right_release` | boolean | Enable right button release |
| `on_middle_press` | boolean | Enable middle button press |
| `on_middle_release` | boolean | Enable middle button release |
| `on_double_click` | boolean | Enable double-click |
| `on_enter` | boolean | Enable cursor enter |
| `on_exit` | boolean | Enable cursor exit |
| `on_move` | boolean | Enable cursor move (coalescable) |
| `on_scroll` | boolean | Enable scroll wheel (coalescable) |
| `event_rate` | integer | Max events/sec for move and scroll |
| `a11y` | hash | Accessibility overrides |

Cursor values: `:pointer`, `:grab`, `:grabbing`, `:crosshair`,
`:text`, `:move`, `:not_allowed`, `:progress`, `:wait`, `:help`,
`:resizing_horizontally`, `:resizing_vertically`, and others.

Move and scroll events carry `pointer` (device type) and
`modifiers` (current modifier key state):

```ruby
pointer_area("canvas-area",
  on_move: true,
  on_press: :area_press,
  on_scroll: true,
  cursor: :crosshair) do
  canvas("drawing", width: 400, height: 300)
end

case event
in Event::Widget[type: :press, id: "canvas-area",
    value: { pointer: :mouse, modifiers: { shift: true } }]
  add_to_selection(model)

in Event::Widget[type: :move, id: "canvas-area",
    value: { x:, y:, modifiers: { control: true } }]
  pan_canvas(model, x, y)

in Event::Widget[type: :scroll, id: "canvas-area",
    value: { delta_y:, pointer: :mouse }]
  zoom(model, delta_y)
end
```

### sensor

`Plushie::Widget::Sensor`

Wraps a single child and emits events when the child's size changes
or when it enters/exits visibility. Useful for responsive layouts,
lazy loading, and intersection observation.

| Prop | Type | Purpose |
|---|---|---|
| `delay` | integer | Delay (ms) before emitting events |
| `anticipate` | number | Distance (px) to anticipate visibility |
| `on_resize` | boolean | Enable resize events |
| `event_rate` | integer | Max events/sec for resize |
| `a11y` | hash | Accessibility overrides |

Emits `:resize` with `{ width:, height: }` as value when the
wrapped child's rendered size changes.

### overlay

`Plushie::Widget::Overlay`

Positions the second child as a floating overlay relative to the
first child (anchor). Exactly two children required.

| Prop | Type | Default | Purpose |
|---|---|---|---|
| `position` | `:below`/`:above`/`:left`/`:right` | `:below` | Overlay position |
| `gap` | number | `0` | Space between anchor and overlay |
| `offset_x` | number | `0` | Horizontal offset after positioning |
| `offset_y` | number | `0` | Vertical offset after positioning |
| `flip` | boolean | `false` | Auto-flip when overlay overflows viewport |
| `align` | `:start`/`:center`/`:end` | `:center` | Cross-axis alignment |
| `width` | Length | | Overlay container width |
| `a11y` | hash | | Accessibility overrides |

The overlay renders above all other content at the positioned
location. See the [Composition Patterns](composition-patterns.md)
reference for a popover menu example.

### themer

`Plushie::Widget::Themer`

Applies a different theme to its children. Single child, single
prop.

```ruby
themer(theme: :dark) do
  container("body", padding: 12) do
    text("info", "This section uses the dark theme")
  end
end
```

## Common props

Most widgets support a subset of these cross-cutting props:

- **`:style`** - visual appearance. Accepts a preset symbol (e.g.
  `:primary`, `:danger`) or a `StyleMap` hash. See the
  [Styling reference](themes-and-styling.md).
- **`:a11y`** - accessibility attributes. See the
  [Accessibility reference](accessibility.md).
- **`:width`** / **`:height`** - sizing. Accepts `:fill`, `:shrink`,
  `[:fill_portion, n]`, or a pixel number. See the
  [Layout reference](windows-and-layout.md).
- **`:event_rate`** - max events per second for high-frequency
  events. Supported on `slider`, `vertical_slider`, `pointer_area`,
  `sensor`, `canvas`, and `pane_grid`.

## Renderer-side state

Some widgets hold state in the renderer that persists across
re-renders. If their ID changes, this state resets:

- **`text_input`** - cursor position, selection, undo history
- **`text_editor`** - cursor, selection, scroll position, undo
- **`combo_box`** - search text, open/closed state
- **`scrollable`** - scroll position
- **`pane_grid`** - pane sizes and arrangement

These widgets require explicit string IDs. Stateful widgets share
scroll and selection state through their ID, so changing the ID is
equivalent to discarding the state.

## keyed_column vs column

Use `column` for static layouts. Use `keyed_column` when children
are dynamic (added, removed, reordered). It diffs by child ID
instead of position, preserving widget state across list changes.
Same props as column minus `align_x`, `clip`, and `wrap`.

## Auto-ID vs explicit ID

Layout containers (`column`, `row`, `stack`, `grid`, `keyed_column`,
`pin`, `floating`, `overlay`, `themer`) and some display widgets
(`text`, `rule`, `space`, `table`) support auto-generated IDs.
Omit the ID and one is generated from the call site
(e.g. `"auto:view:42"`). These IDs are unstable across code changes:
any refactor that moves the call to a different line changes the
generated ID.

All interactive and stateful widgets require explicit string IDs
for event routing and state persistence.

## Animatable props

Numeric props support renderer-side transitions via
`Plushie::Animation::Transition.build`,
`Plushie::Animation::Spring.build`, and sequence chains. Commonly
animated: `max_width`, `max_height`, `opacity`, `translate_x`,
`translate_y`, `scale`. See the [Animation reference](animation.md).

## Prop value types

These prop types appear across multiple widgets. The full styling
types (Color, Theme, StyleMap, Border, Shadow, Gradient) are in the
[Styling reference](themes-and-styling.md). Layout types (Length,
Padding, Alignment) are in the [Layout reference](windows-and-layout.md).

### Font

Used by: `text`, `rich_text`, `text_input`, `text_editor`.

| Value | Meaning |
|---|---|
| `:default` | System default proportional font |
| `:monospace` | System monospace font |
| `"Family Name"` | Specific font family (must be loaded via `settings`) |

A full `Plushie::Type::Font` struct also supports `weight:`
(`:thin` through `:black`), `style:` (`:normal`, `:italic`,
`:oblique`), and `stretch:` (`:ultra_condensed` through
`:ultra_expanded`).

### Shaping

Used by: `text`, `rich_text`, `text_input`, `text_editor`.

| Value | Meaning |
|---|---|
| `:basic` | Simple left-to-right shaping (fastest) |
| `:advanced` | Full Unicode shaping (ligatures, RTL, complex scripts) |
| `:auto` | Let the renderer decide based on content |

### Wrapping

Used by: `text`, `rich_text`.

| Value | Meaning |
|---|---|
| `:none` | No wrapping (text overflows) |
| `:word` | Break at word boundaries |
| `:glyph` | Break at any character |
| `:word_or_glyph` | Try word boundaries first, fall back to glyph |

### Text direction

Used by: `text`, `text_input`, `text_editor`.

| Value | Meaning |
|---|---|
| `:auto` | Renderer chooses direction from content |
| `:ltr` | Left-to-right text |
| `:rtl` | Right-to-left text |

### Ellipsis

Used by: `text`, `rich_text`, `pick_list`, `combo_box`.

| Value | Meaning |
|---|---|
| `:none` | No ellipsis |
| `:start` | Omit the beginning |
| `:middle` | Omit the middle |
| `:end` | Omit the end |

### Content fit

Used by: `image`, `svg`.

| Value | Meaning |
|---|---|
| `:contain` | Scale to fit within bounds, preserving aspect ratio |
| `:cover` | Scale to fill bounds, cropping if needed |
| `:fill` | Stretch to fill bounds exactly (may distort) |
| `:none` | No scaling (original size) |
| `:scale_down` | Like `:contain` but never scales up |

### Filter method

Used by: `image`.

| Value | Meaning |
|---|---|
| `:nearest` | Pixel-perfect interpolation (blocky, good for pixel art) |
| `:linear` | Smooth interpolation (good for photos) |

### Tooltip position

Used by: `tooltip`.

| Value | Meaning |
|---|---|
| `:top` | Above the widget |
| `:bottom` | Below the widget |
| `:left` | Left of the widget |
| `:right` | Right of the widget |
| `:follow_cursor` | Follows the mouse cursor |

### Scroll direction

Used by: `scrollable`.

| Value | Meaning |
|---|---|
| `:vertical` | Vertical scrolling (default) |
| `:horizontal` | Horizontal scrolling |
| `:both` | Bidirectional scrolling |

### Scroll anchor

Used by: `scrollable`.

| Value | Meaning |
|---|---|
| `:start` | Anchor at the top/left (default) |
| `:end` | Anchor at the bottom/right |

### Auto scroll

Used by: `scrollable`.

When `auto_scroll: true` is set, the scrollable automatically scrolls
to reveal new content appended at the anchor end. Useful for chat
logs, terminal output, and other append-only content where the user
expects to see the latest entries without manual scrolling.

```ruby
scrollable("log", direction: :vertical, anchor: :end, auto_scroll: true) do
  column(spacing: 4) do
    model.log_entries.each do |entry|
      text(entry.id, entry.text)
    end
  end
end
```

When the user manually scrolls away from the anchor, auto-scroll
pauses to avoid fighting the user's position. It resumes when the
user scrolls back to the anchor end.

## See also

- [Layout reference](windows-and-layout.md) - sizing, alignment,
  and all layout containers with full prop tables
- [Styling reference](themes-and-styling.md) - Color, Theme,
  StyleMap, Border, Shadow, Gradient
- [Canvas reference](canvas.md) - shapes, layers, interactive
  elements
- [Accessibility reference](accessibility.md) - the `a11y` prop,
  roles, and keyboard navigation
- [Events reference](events.md) - all event types delivered by
  widgets
- [Animation reference](animation.md) - transition, spring,
  sequence descriptors
