# Windows and Layout

Every Plushie app starts with one or more windows. Inside each, you
compose layout containers to arrange widgets on screen. This page
covers windows, sizing, spacing, alignment, and all layout containers.

For a gentler introduction, see the [Layout guide](../guides/07-layout.md).

## Window

`Plushie::Widget::Window`

The top-level container. Every `view` must return a `window(...)` node
or an array of `window(...)` nodes. Widgets do not live at the top
level. Windows map to native OS windows, each with its own title bar,
size, position, and optional theme.

```ruby
def view(model)
  window("main", title: "My App", theme: :dark) do
    column(width: :fill, height: :fill) do
      # app content
    end
  end
end
```

### Window props

| Prop | Type | Description |
|---|---|---|
| `title` | String | Title bar text |
| `size` | `[width, height]` | Initial size in pixels |
| `width` | Number | Width (alternative to `size`) |
| `height` | Number | Height (alternative to `size`) |
| `position` | `[x, y]` | Initial position |
| `min_size` | `[width, height]` | Minimum dimensions |
| `max_size` | `[width, height]` | Maximum dimensions |
| `maximized` | Boolean | Start maximized |
| `fullscreen` | Boolean | Start fullscreen |
| `visible` | Boolean | Whether window is visible |
| `resizable` | Boolean | Allow resizing |
| `closeable` | Boolean | Show close button |
| `minimizable` | Boolean | Allow minimizing |
| `decorations` | Boolean | Show title bar and borders |
| `transparent` | Boolean | Transparent window background |
| `blur` | Boolean | Blur window background |
| `level` | Symbol | Stacking level (`:normal`, `:always_on_top`, `:always_on_bottom`) |
| `exit_on_close_request` | Boolean | Whether closing exits the app |
| `scale_factor` | Number | DPI scale override |
| `theme` | Symbol or Hash | Per-window theme (`:dark`, `:nord`, `:system`, or a custom theme map) |
| `a11y` | Hash | Accessibility overrides |

`decorations`, `transparent`, `visible`, `resizable`, `closeable`, and
`minimizable` default to the renderer's defaults when not set. Window
nodes carry a default accessibility role of `:window`.

### Multi-window

Return multiple windows from `view` as an array:

```ruby
def view(model)
  windows = [
    window("main", title: "App") { main_content(model) }
  ]

  if model.show_settings
    windows << window("settings",
      title: "Settings",
      exit_on_close_request: false) do
      settings_content(model)
    end
  end

  windows
end
```

`exit_on_close_request: false` on secondary windows means closing them
removes the window without exiting the app. Window IDs must be stable
strings; changing an ID causes a close and re-open.

### window_config callback

Override `window_config(model)` on your app to supply default settings
applied to every new window. Per-window props set on the tree override
these defaults.

```ruby
class MyApp
  include Plushie::App

  def window_config(_model)
    { min_size: [400, 300], decorations: true, theme: :dark }
  end

  def view(model)
    window("main", title: "App") { ... }
  end
end
```

If `window_config` raises, the error is logged and the window opens
with no base settings.

### Window events

Window lifecycle events arrive as `Event::Window` with `type:`
`:opened`, `:closed`, `:close_requested`, `:moved`, `:resized`,
`:focused`, `:unfocused`, `:rescaled`, `:file_hovered`,
`:file_dropped`, and `:files_hovered_left`. See the
[Events reference](events.md#event-window) for the full field list.

```ruby
case event
in Event::Window[type: :close_requested, window_id:]
  close_extra_window(model, window_id)

in Event::Window[type: :resized, window_id: "main", width:, height:]
  model.with(main_width: width, main_height: height)
end
```

### Window commands

Every window operation is a `Plushie::Command::Window` method, delegated
onto `Plushie::Command`:

| Method | Purpose |
|---|---|
| `close_window(window_id)` | Close a window |
| `resize_window(window_id, width, height)` | Set window size |
| `move_window(window_id, x, y)` | Set window position |
| `maximize_window(window_id, maximized = true)` | Maximize or unmaximize |
| `minimize_window(window_id, minimized = true)` | Minimize or unminimize |
| `toggle_maximize(window_id)` | Toggle maximized state |
| `toggle_decorations(window_id)` | Toggle window chrome |
| `set_window_mode(window_id, mode)` | Set `:windowed`, `:fullscreen`, or `:hidden` |
| `set_window_level(window_id, level)` | Set stacking level |
| `focus_window(window_id)` | Bring window to front |
| `drag_window(window_id)` | Begin window drag |
| `drag_resize_window(window_id, direction)` | Begin window resize drag |
| `request_attention(window_id, urgency)` | Flash / bounce in the OS task switcher |
| `set_resizable(window_id, resizable)` | Change resizable flag at runtime |
| `set_min_size(window_id, width, height)` | Change minimum size at runtime |
| `set_max_size(window_id, width, height)` | Change maximum size at runtime |
| `set_resize_increments(window_id, width, height)` | Snap-grid resize step |
| `enable_mouse_passthrough(window_id)` | Make the window click-through |
| `disable_mouse_passthrough(window_id)` | Restore normal hit-testing |
| `show_system_menu(window_id)` | Invoke the OS window system menu |
| `set_icon(window_id, rgba_data, width, height)` | Swap the window icon at runtime |
| `allow_automatic_tabbing(enabled)` | macOS automatic tab management |
| `screenshot(window_id, tag)` | Capture window screenshot |

Query state with `Plushie::Command::WindowQuery`:

| Method | Purpose |
|---|---|
| `window_size(window_id, tag)` | Query window dimensions |
| `window_position(window_id, tag)` | Query window position |
| `is_maximized(window_id, tag)` | Query maximized state |
| `is_minimized(window_id, tag)` | Query minimized state |
| `window_mode(window_id, tag)` | Query fullscreen/windowed mode |
| `scale_factor(window_id, tag)` | Query DPI scale factor |
| `raw_id(window_id, tag)` | Query platform window handle |
| `monitor_size(window_id, tag)` | Query monitor dimensions |

Query results arrive as `Event::System[type:, tag:, value:]`. See the
[Commands reference](commands.md#window-operations) for the full
mechanics.

## Sizing

Every layout widget accepts `width:` and `height:` props. Four value
forms are supported via `Plushie::Type::Length`:

| Value | Behaviour |
|---|---|
| `:shrink` | Take only as much space as the content needs. Default for most widgets. |
| `:fill` | Take all available space in the parent container. |
| `[:fill_portion, n]` | Take a proportional share of available space relative to siblings. |
| Numeric | Exact pixel size. |

`Plushie::Type::Length.encode` raises `ArgumentError` on negative
numeric values and on malformed arrays.

### How fill_portion works

When multiple siblings use `:fill` or `[:fill_portion, n]`, the
available space (after fixed-size and `:shrink` siblings are measured)
is divided proportionally. The numbers are relative ratios:

```ruby
row(width: :fill) do
  container("sidebar", width: [:fill_portion, 1]) { ... }
  container("main",    width: [:fill_portion, 3]) { ... }
end
```

Sidebar gets 1/4 of the width, main gets 3/4. `[:fill_portion, 1]`
plus `[:fill_portion, 3]` is the same ratio as `[:fill_portion, 2]`
plus `[:fill_portion, 6]`.

`:fill` is shorthand for `[:fill_portion, 1]`. Two `:fill` siblings
split space equally.

### Sizing resolution order

The layout engine processes siblings in this order:

1. **Fixed-size** children (numeric pixel values) are measured first.
2. **`:shrink`** children are measured at their intrinsic content size.
3. **`:fill` / `[:fill_portion, n]`** children divide the remaining space.

A fixed-width sidebar always gets its pixels, a shrink button takes
what it needs, and fill containers expand to use whatever is left.

### Constraints

`max_width:` and `max_height:` set upper bounds. A `:fill` child with
`max_width: 600` expands to fill available space but never exceeds
600 pixels. Available on `column`, `row`, `container`, and
`keyed_column`.

## Padding

`Plushie::Type::Padding`

Padding is the space between a container's edges and its content.
`Plushie::Type::Padding.cast` accepts several input forms:

| Input | Result |
|---|---|
| `16` | 16 px on all sides |
| `[8, 16]` | 8 px top/bottom, 16 px left/right |
| `[4, 8, 12, 16]` | Per side in `[top, right, bottom, left]` order |
| `{ top: 16, bottom: 8 }` | Per-side (unset sides default to 0) |
| `Plushie::Type::Padding::Pad.new(top: 16)` | Struct form |

Negative values raise `ArgumentError`. Padding reduces the space
available to children: a 200 px wide container with `padding: 16` has
168 px of content space.

## Spacing

Spacing is the gap between sibling children inside a container. Set
via the `spacing:` prop on `column`, `row`, `grid`, and
`keyed_column`:

```ruby
column(spacing: 12) do
  text("a", "First")    # 12 px gap below
  text("b", "Second")   # 12 px gap below
  text("c", "Third")    # no gap after last child
end
```

Spacing applies between children, not before the first or after the
last. It does not interact with padding; they are independent.

## Alignment

`Plushie::Type::Alignment`

Alignment controls how children are positioned within a container's
available space. Valid symbols: `:left`, `:center`, `:right`, `:top`,
`:bottom`.

| Prop | Container | Valid values |
|---|---|---|
| `align_x:` | `column`, `container`, `keyed_column` | `:left` (default), `:center`, `:right` |
| `align_y:` | `row`, `container` | `:top` (default), `:center`, `:bottom` |

`column` aligns children horizontally (they already stack vertically).
`row` aligns children vertically (they already flow horizontally).
`container` supports both axes since it has a single child.

Container also accepts `center: true` as a shortcut that sets both
`align_x: :center` and `align_y: :center`. For the programmatic
builder, `Plushie::Widget::Container.new(id).center_x.center_y` sets
width/height to `:fill` and centres on both axes.

## Anchor

`Plushie::Type::Anchor`

The `anchor:` prop on `scrollable` selects the initial scroll
position: `:start` (top/left, default) or `:end` (bottom/right).

## Layout containers

### column

`Plushie::Widget::Column`. Arranges children vertically, top to
bottom.

| Prop | Type | Description |
|---|---|---|
| `spacing` | Number | Vertical gap between children |
| `padding` | Padding | Inner padding |
| `width` | Length | Column width |
| `height` | Length | Column height |
| `max_width` | Number | Maximum width in pixels |
| `align_x` | Symbol | Horizontal alignment of children |
| `clip` | Boolean | Clip children that overflow |
| `wrap` | Boolean | Wrap children to next column on overflow |
| `a11y` | Hash | Accessibility overrides |
| `event_rate` | Integer | Max events/sec for coalescable events |

Defaults: `spacing` 0, `padding` 0, `width` and `height` `:shrink`,
`align_x` `:left`, `clip` and `wrap` `false`.

`wrap: true` enables multi-column flow. When children exceed the
column height, they wrap to a new column to the right (like CSS
`flex-wrap`).

### row

`Plushie::Widget::Row`. Arranges children horizontally, left to right.

| Prop | Type | Description |
|---|---|---|
| `spacing` | Number | Horizontal gap between children |
| `padding` | Padding | Inner padding |
| `width` | Length | Row width |
| `height` | Length | Row height |
| `max_width` | Number | Maximum width in pixels |
| `align_y` | Symbol | Vertical alignment of children |
| `clip` | Boolean | Clip children that overflow |
| `wrap` | Boolean | Wrap children to next row on overflow |
| `a11y` | Hash | Accessibility overrides |
| `event_rate` | Integer | Max events/sec for coalescable events |

Defaults: `spacing` 0, `padding` 0, `width` and `height` `:shrink`,
`align_y` `:top`, `clip` and `wrap` `false`.

`wrap: true` enables multi-row flow. Useful for tag clouds, toolbar
buttons, or any content that should reflow at different widths.

### container

`Plushie::Widget::Container`. Single-child wrapper for styling,
scoping, and alignment.

| Prop | Type | Description |
|---|---|---|
| `padding` | Padding | Inner padding |
| `width` | Length | Container width |
| `height` | Length | Container height |
| `max_width` | Number | Maximum width |
| `max_height` | Number | Maximum height |
| `align_x` | Symbol | Horizontal child alignment |
| `align_y` | Symbol | Vertical child alignment |
| `center` | Boolean | Centre the child in both axes |
| `clip` | Boolean | Clip the child when it overflows |
| `background` | Color or Gradient | Background fill |
| `color` | Color | Text colour override |
| `border` | Border | Border specification |
| `shadow` | Shadow | Drop shadow |
| `style` | Symbol or StyleMap | Named preset or full style map |
| `a11y` | Hash | Accessibility overrides |
| `event_rate` | Integer | Max events/sec for coalescable events |

Container style presets (passed via `style:`): `:transparent`,
`:rounded_box`, `:bordered_box`, `:dark`, `:primary`, `:secondary`,
`:success`, `:danger`, `:warning`. Full style maps are documented in
the [Styling reference](themes-and-styling.md).

Container serves three roles: **styling** (background, border,
shadow, text colour), **scoping** (named containers create ID scopes
for their children; see [Scoped IDs](scoped-ids.md)), and
**alignment** (positioning a child within available space).

### scrollable

`Plushie::Widget::Scrollable`. Adds scroll bars when content
overflows. Requires an explicit string ID because the renderer tracks
scroll position as internal state keyed by the ID.

| Prop | Type | Description |
|---|---|---|
| `width` | Length | Viewport width |
| `height` | Length | Viewport height |
| `direction` | Symbol | `:vertical` (default), `:horizontal`, or `:both` |
| `spacing` | Number | Gap between scrollbar and content |
| `scrollbar_width` | Number | Scrollbar track width |
| `scrollbar_margin` | Number | Margin around scrollbar |
| `scroller_width` | Number | Scroller handle width |
| `scrollbar_color` | Color | Scrollbar track colour |
| `scroller_color` | Color | Scroller thumb colour |
| `anchor` | Symbol | `:start` (default) or `:end` |
| `on_scroll` | Boolean | Emit `:scrolled` events with viewport data |
| `auto_scroll` | Boolean | Auto-scroll to show new content |
| `a11y` | Hash | Accessibility overrides |
| `event_rate` | Integer | Max events/sec for coalescable events |

Scrollable carries a default accessibility role of `:scroll_view`.

`auto_scroll: true` is useful for chat-style interfaces where new
messages should scroll into view. Combine with `anchor: :end` to
start scrolled to the bottom.

When `on_scroll: true`, each `:scrolled` event carries a hash value
with `absolute_x`, `absolute_y`, `relative_x`, `relative_y`,
`bounds_width`, `bounds_height`, `content_width`, and
`content_height`.

### keyed_column

`Plushie::Widget::KeyedColumn`. Like `column`, but uses each child's
ID as a diffing key for the renderer.

| Prop | Type | Description |
|---|---|---|
| `spacing` | Number | Vertical gap between children |
| `padding` | Padding | Inner padding |
| `width` | Length | Column width |
| `height` | Length | Column height |
| `max_width` | Number | Maximum width in pixels |
| `align_x` | Symbol | Horizontal alignment of children |
| `a11y` | Hash | Accessibility overrides |
| `event_rate` | Integer | Max events/sec for coalescable events |

Use `keyed_column` for dynamic lists where items are added, removed,
or reordered. A plain `column` diffs by position, so inserting at
the top shifts every child's state down by one. `keyed_column`
matches by ID, preserving widget state (focus, scroll, cursor)
regardless of position. Does not support `clip` or `wrap`.

### stack

`Plushie::Widget::Stack`. Layers children on top of each other on the
z-axis. First child is at the back, last child is at the front.

| Prop | Type | Description |
|---|---|---|
| `width` | Length | Stack width |
| `height` | Length | Stack height |
| `clip` | Boolean | Clip children that overflow |
| `a11y` | Hash | Accessibility overrides |
| `event_rate` | Integer | Max events/sec for coalescable events |

Use for overlays, badges, loading spinners, or any situation where
elements need to be layered.

### grid

`Plushie::Widget::Grid`. Arranges children in a grid layout.

| Prop | Type | Description |
|---|---|---|
| `num_columns` | Integer | Number of columns (fixed mode) |
| `spacing` | Number | Gap between cells |
| `width` | Number | Grid width in pixels |
| `height` | Number | Grid height in pixels |
| `column_width` | Length | Width of each column |
| `row_height` | Length | Height of each row |
| `fluid` | Number | Max cell width for fluid auto-wrap mode |
| `a11y` | Hash | Accessibility overrides |
| `event_rate` | Integer | Max events/sec for coalescable events |

Two modes: **fixed columns** (`num_columns: 3`) and **fluid**
(`fluid: 200`). In fluid mode the grid auto-wraps columns based on
available width, fitting as many cells of the specified max width as
possible.

### pin

`Plushie::Widget::Pin`. Positions a child at exact pixel coordinates
within a parent container.

| Prop | Type | Description |
|---|---|---|
| `x` | Number | X position in pixels |
| `y` | Number | Y position in pixels |
| `width` | Length | Pin container width |
| `height` | Length | Pin container height |
| `a11y` | Hash | Accessibility overrides |
| `event_rate` | Integer | Max events/sec for coalescable events |

Defaults: `x` and `y` 0, `width` and `height` `:shrink`. Pin does not
participate in flow layout; the child is positioned absolutely.
Useful for tooltips, popovers, and custom positioning.

### floating

`Plushie::Widget::Floating`. Applies translate and scale transforms
to a single child without removing it from flow layout.

| Prop | Type | Description |
|---|---|---|
| `translate_x` | Number | Horizontal translation in pixels |
| `translate_y` | Number | Vertical translation in pixels |
| `scale` | Number | Scale factor |
| `width` | Length | Container width |
| `height` | Length | Container height |
| `a11y` | Hash | Accessibility overrides |
| `event_rate` | Integer | Max events/sec for coalescable events |

Unlike `pin`, floating applies visual transforms while the child
still occupies its original space; the transform is visual only.

### responsive

`Plushie::Widget::Responsive`. Adapts layout by emitting resize
events when the container's size changes.

| Prop | Type | Description |
|---|---|---|
| `width` | Length | Container width |
| `height` | Length | Container height |
| `a11y` | Hash | Accessibility overrides |
| `event_rate` | Integer | Max events/sec for coalescable events |

When the responsive container's size changes, it emits
`Event::Widget[type: :resize, value: { width:, height: }]`. Use this
in `update` to store the measured size and adjust your `view` based
on it (for example, switching from a sidebar layout to a stacked
layout below a certain width).

### space

`Plushie::Widget::Space`. Invisible spacer widget. No children, no
visual output.

| Prop | Type | Description |
|---|---|---|
| `width` | Length | Space width |
| `height` | Length | Space height |
| `a11y` | Hash | Accessibility overrides |
| `event_rate` | Integer | Max events/sec for coalescable events |

Use for explicit gaps, alignment tricks, or pushing siblings apart
in a row or column.

## Border

`Plushie::Type::Border`

A border has a colour, width, and radius. Construct with keyword
options through `Border.from_opts` or use the block DSL.

```ruby
container("box",
  border: Plushie::Type::Border.from_opts(
    color: "#3366ff", width: 2, rounded: 8)) do
  text("msg", "Inside a rounded border")
end
```

| Field | Type | Description |
|---|---|---|
| `color` | Color | Stroke colour |
| `width` | Number | Stroke thickness in pixels |
| `radius` | Number or Hash | Uniform radius, or per-corner hash |

Per-corner radii use the keys `:top_left`, `:top_right`,
`:bottom_right`, `:bottom_left`:

```ruby
Plushie::Type::Border.from_opts(
  width: 1,
  radius: { top_left: 8, top_right: 8, bottom_right: 0, bottom_left: 0 })
```

Negative width or radius values raise `ArgumentError`. The inline
block DSL is also available inside container definitions:

```ruby
container("card") do
  border do
    color "#3366ff"
    width 2
    rounded 8
  end
end
```

## Shadow

`Plushie::Type::Shadow`

A shadow has a colour, offset, and blur radius. Construct with
keyword options through `Shadow.from_opts`.

```ruby
container("card",
  shadow: Plushie::Type::Shadow.from_opts(
    color: "#00000040", offset_x: 2, offset_y: 2, blur_radius: 6)) do
  text("body", "Card with a soft shadow")
end
```

| Field | Type | Description |
|---|---|---|
| `color` | Color | Shadow colour (defaults to `"#000000"`) |
| `offset_x` | Number | Horizontal offset in pixels |
| `offset_y` | Number | Vertical offset in pixels |
| `blur_radius` | Number | Gaussian blur radius in pixels |

`offset_x` and `offset_y` both default to 0; `blur_radius` defaults
to 0. `from_opts` also accepts an `offset: [x, y]` array as a
shorthand. The inline block DSL is available inside container
definitions:

```ruby
container("card") do
  shadow do
    color "#00000022"
    offset_y 2
    blur_radius 4
  end
end
```

## Composition patterns

### Sidebar + content

```ruby
row(width: :fill, height: :fill) do
  column(width: 200, height: :fill, padding: 8) do
    # fixed-width sidebar
  end
  container("main", width: :fill, height: :fill, padding: 16) do
    # content fills remaining space
  end
end
```

### Header / body / footer

```ruby
column(width: :fill, height: :fill) do
  row(padding: 8) do
    # header (shrinks to content)
  end
  container("body", width: :fill, height: :fill) do
    # body fills remaining space
  end
  row(padding: 8) do
    # footer (shrinks to content)
  end
end
```

### Centred content

```ruby
container("hero", width: :fill, height: :fill, center: true) do
  text("msg", "Centred in both axes")
end
```

### Scrollable list

```ruby
scrollable("items", height: 400) do
  keyed_column(spacing: 4) do
    model.items.each do |item|
      container(item.id, padding: 8) do
        text("#{item.id}-name", item.name)
      end
    end
  end
end
```

### Overlay / badge

```ruby
stack do
  container("back", width: :fill, height: :fill) do
    # main content underneath
  end
  pin do
    container("badge", x: 10, y: 10) { text("NEW", size: 10) }
  end
end
```

## See also

- [Built-in Widgets reference](built-in-widgets.md) - full widget
  catalog including non-layout widgets
- [Themes and Styling reference](themes-and-styling.md) - `Color`,
  `Gradient`, `StyleMap`, and the container style presets in detail
- [Commands reference](commands.md) - window operations, window
  queries, and pane grid management
- [Composition Patterns reference](composition-patterns.md) -
  dialogs, popovers, sidebars, and other reusable structures
