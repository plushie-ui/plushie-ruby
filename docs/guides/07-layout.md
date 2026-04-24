# Layout

The pad from chapter 6 works, but the layout could use some
attention. The sidebar, editor, and preview panes are functional
but not well-proportioned, and the spacing is inconsistent. In
this chapter we fix that by learning Plushie's layout system.

We cover the layout containers you use every day, how sizing
works, and how spacing and alignment give your UI structure. The
full container catalog lives in the
[Windows and Layout reference](../reference/windows-and-layout.md).
Here we focus on the ones that matter most.

## The box model

Every Plushie widget has a `width:` and a `height:`. Containers
arrange their children; leaf widgets (text, buttons, images) take
up whatever space their content requires. That's it. There's no
CSS-style flex / grid / absolute toggle, no float, no block vs
inline distinction. Pick a container, set its size, and put
children in it.

The layout engine measures children in three passes:

1. Fixed-size children (numeric pixel values) are measured first.
2. `:shrink` children are measured at their intrinsic content
   size.
3. `:fill` and `[:fill_portion, n]` children divide whatever is
   left.

That ordering is worth remembering. When something unexpectedly
collapses to zero width, it's almost always because a parent is
`:shrink` (the default) and there is no available space for the
child to fill.

## Layout containers

Three containers carry most of the weight: `column`, `row`, and
`container`. A few specialised ones (`scrollable`, `stack`,
`grid`, `keyed_column`, `pin`) handle the rest.

### column

Stacks children vertically, top to bottom.

```ruby
column("numbers", spacing: 12, padding: 16) do
  text("one", "First")
  text("two", "Second")
  text("three", "Third")
end
```

Common props: `spacing:` (gap between children), `padding:`
(space inside), `width:`, `height:`, `align_x:` (how children
line up horizontally), `clip:` (clip overflow), `wrap:` (flow
children into a second column when the first one fills).

### row

Stacks children horizontally, left to right. Same props as
`column`, except it takes `align_y:` instead of `align_x:`.

```ruby
row("actions", spacing: 8) do
  button("left", "Left")
  button("right", "Right")
end
```

`wrap: true` enables multi-row flow. Handy for toolbars and tag
clouds that should reflow at different window widths.

### container

A single-child wrapper. Use it for styling (background, border,
shadow), for ID scoping (the container's ID scopes every child
beneath it), or for alignment and padding around a single widget.

```ruby
container("card", padding: 16, background: "#f5f5f5") do
  text("content", "Inside the card")
end
```

`container` is also the only layout primitive that aligns on
both axes (`align_x:` and `align_y:`), because it has a single
child and no natural flow direction.

## Sizing: `:fill`, `:shrink`, and fixed

Every layout widget's `width:` and `height:` accept four value
shapes, matching `Plushie::Type::Length`:

| Value | Behaviour |
|---|---|
| `:shrink` | Take only as much space as the content needs (default) |
| `:fill` | Take all available space in the parent |
| `[:fill_portion, n]` | Take a proportional share of available space |
| Numeric | Exact pixel size |

Pass them verbatim as keyword arguments:

```ruby
column(width: :fill, height: :fill) { ... }
container("card", width: 320) { ... }
row(width: :fill) do
  container("sidebar", width: [:fill_portion, 1]) { ... }
  container("main", width: [:fill_portion, 3]) { ... }
end
```

`Plushie::Type::Length.encode` raises `ArgumentError` on negative
numeric values and on any other array or symbol shape, so typos
fail loudly at construction time.

### `:fill` vs `:shrink`

In a `row`, a `:fill` child takes all the remaining space after
`:shrink` siblings are measured:

```ruby
row("search-bar", width: :fill) do
  text_input("search", model.query,
    width: :fill,
    placeholder: "Search...")
  button("go", "Go")
end
```

The button shrinks to its label. The text input fills the rest.
Swap the two children and the button still shrinks, the text
input still fills; sibling order doesn't change the math.

### `[:fill_portion, n]` for proportional splits

When multiple siblings use `:fill`, they share space equally.
Reach for `[:fill_portion, n]` when you want a specific ratio:

```ruby
row("split", width: :fill) do
  container("sidebar", width: [:fill_portion, 1]) do
    text("nav", "Sidebar")
  end
  container("main", width: [:fill_portion, 3]) do
    text("content", "Main content")
  end
end
```

The sidebar gets 1/4 of the width, the main area gets 3/4. The
numbers are relative: `[:fill_portion, 1]` plus
`[:fill_portion, 3]` is the same ratio as `[:fill_portion, 2]`
plus `[:fill_portion, 6]`. `:fill` on its own is shorthand for
`[:fill_portion, 1]`, which is why two sibling `:fill` children
split space evenly.

The pad uses a 2:2 split for its editor and preview panes. Same
ratio as `:fill` / `:fill`, just expressed explicitly so the
intent is obvious to a reader. If you wanted the preview twice
as wide as the editor, you would write `[:fill_portion, 1]` on
the editor and `[:fill_portion, 2]` on the preview.

### Fixed pixels

A plain number means exact pixels:

```ruby
container("icon", width: 48, height: 48) do
  text("x", "X")
end
```

Fixed-size widgets are measured before fill widgets, so a
sidebar with `width: 200` always gets its two hundred pixels and
the `:fill` main pane takes whatever is left.

## Padding

Padding is the space between a container's edges and its
content. `Plushie::Type::Padding.cast` accepts four input
shapes:

| Input | Meaning |
|---|---|
| `16` | 16 px on every side |
| `[8, 16]` | 8 px top and bottom, 16 px left and right |
| `[4, 8, 12, 16]` | `[top, right, bottom, left]` in that order |
| `{ top: 16, bottom: 8 }` | Per-side hash, omitted sides default to 0 |

```ruby
column(padding: 16) { ... }                      # uniform
column(padding: [8, 16]) { ... }                 # vertical, horizontal
column(padding: [4, 8, 12, 16]) { ... }          # per side, clockwise
column(padding: { top: 16, bottom: 8 }) { ... }  # sparse hash
```

The pad's toolbar uses the two-element form: `padding: [8, 4]`
means 8 px above and below, 4 px to the left and right. That
keeps the toolbar compact vertically while giving the buttons a
little breathing room on the sides.

Negative values raise `ArgumentError`. Padding reduces the space
available to children: a 200 px wide container with
`padding: 16` has 168 px of content space.

Programmatic code can use the struct form directly:

```ruby
Plushie::Type::Padding::Pad.new(top: 16, bottom: 8)
```

## Spacing

Spacing is the gap between sibling children inside a container.
Set via the `spacing:` prop on `column`, `row`, `grid`, and
`keyed_column`:

```ruby
column(spacing: 12) do
  text("a", "First")    # 12 px gap below
  text("b", "Second")   # 12 px gap below
  text("c", "Third")    # no gap after the last child
end
```

Spacing applies between children. It doesn't add space before
the first child or after the last, and it doesn't interact with
padding. If you want both, set both.

## Alignment

`align_x:` and `align_y:` control how children are positioned
within a container's available space. Values come from
`Plushie::Type::Alignment`:

| Prop | Container | Valid values |
|---|---|---|
| `align_x:` | `column`, `container`, `keyed_column` | `:left` (default), `:center`, `:right` |
| `align_y:` | `row`, `container` | `:top` (default), `:center`, `:bottom` |

A `column` already stacks vertically, so `align_x:` chooses
left, centred, or right within the column's width. A `row`
already flows horizontally, so `align_y:` chooses top, middle,
or bottom within the row's height. A `container` has a single
child and takes both.

```ruby
container("hero",
  width: :fill,
  height: 200,
  align_x: :center,
  align_y: :center) do
  text("centered", "I am centred")
end
```

`container` accepts `center: true` as a shortcut that sets both
axes at once:

```ruby
container("hero", width: :fill, height: :fill, center: true) do
  text("centered", "Centred both ways")
end
```

## The `:fill`-on-intermediate-containers trap

This is the layout bug you will hit most often. Containers
default to `:shrink`. If a parent is `:shrink`, there is no
available space for a `:fill` child to take. The child collapses
to zero width, and because its descendants probably also use
`:fill`, the whole subtree vanishes.

```ruby
# Bug: the outer column defaults to width :shrink, so the row's
# width: :fill has nothing to fill. The text pane collapses.
column("root") do
  row(width: :fill, height: :fill) do
    container("main", width: :fill) do
      text("hello", "Hello")
    end
  end
end
```

The fix is to make every ancestor on the path from the window to
a `:fill` descendant also `:fill`:

```ruby
column("root", width: :fill, height: :fill) do
  row("split", width: :fill, height: :fill) do
    container("main", width: :fill) do
      text("hello", "Hello")
    end
  end
end
```

When a widget disappears or collapses to a point, walk up the
tree from the widget to the window checking each parent. The
culprit is almost always an intermediate `column` or `row` that
silently defaulted to `:shrink`.

## Scrollable as a layout primitive

`scrollable` wraps a child in a scroll viewport. When the child
exceeds the viewport's height or width, scroll bars appear.

```ruby
scrollable("list", height: 300, direction: :vertical) do
  column("items", spacing: 4) do
    model.items.each do |item|
      text(item.id, item.name)
    end
  end
end
```

`direction:` defaults to `:vertical`. Set `:horizontal` or
`:both` when you need a different axis. `scrollable` needs an
explicit string ID because the renderer tracks scroll position
as internal state keyed by that ID; if the ID changes between
renders, the scroll position resets.

Think of `scrollable` as a layout tool. It's the standard way to
keep a list from pushing the rest of the UI off-screen: set a
bounded height on the scrollable, and let its child grow
vertically without affecting siblings.

## The pad's layout, explained

Here is the pad's `view` method with annotations. Each helper
method is one of the composition patterns covered above.

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

The outer `column` stacks three regions top to bottom: the main
row (sidebar plus editor plus preview), the toolbar, and the
event log. Both the column and the inner row use
`width: :fill, height: :fill` so the whole tree fills the
window, avoiding the intermediate-container trap.

### Sidebar: fixed width, scrollable, list

```ruby
def sidebar(model)
  container("sidebar-wrap",
    width: 200,
    height: :fill,
    border: Plushie::Type::Border.from_opts(color: "#333333", width: 1)) do
    scrollable("sidebar", height: :fill) do
      column("files", spacing: 4, padding: 8) do
        model.files.each { |file| file_row(model, file) }
      end
    end
  end
end
```

Three layers, each with one job. The outer `container` pins the
sidebar to exactly 200 px wide and draws a right-side border.
The `scrollable` adds scroll bars when the file list outgrows
the available height. The inner `column` lays out file rows with
4 px gaps between them and 8 px of padding inside the scrollable.

This is the canonical sidebar pattern: fixed-width wrapper,
scrollable body, column of list rows.

### Editor: `[:fill_portion, 2]` width

```ruby
def editor_pane(model)
  text_editor("editor", model.source,
    width: [:fill_portion, 2],
    height: :fill,
    highlight_syntax: "ruby",
    font: :monospace)
end
```

The editor and the preview both declare
`width: [:fill_portion, 2]`, so they split the remaining
horizontal space (after the 200 px sidebar is measured) evenly.

### Preview: equal portion, conditional child

```ruby
def preview_pane(model)
  container("preview",
    width: [:fill_portion, 2],
    height: :fill,
    padding: 16) do
    if model.error
      text("error", model.error, size: 14)
    elsif model.preview
      Plushie::UI::Context.current&.push(model.preview) || model.preview
    else
      text("placeholder", "Press Save to compile")
    end
  end
end
```

The same `[:fill_portion, 2]` width makes the preview mirror the
editor's width. The `padding: 16` gives compiled experiments
room to breathe away from the pane's edge.

### Toolbar: a row with spaced children

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

Because the toolbar row has no `width:` set, it defaults to
`:shrink` and sizes itself to the content. The outer `column` is
`:fill`, so the toolbar takes up only as much vertical space as
its shortest valid height. Its children are each `:shrink` too,
so they line up tightly with 8 px between them. `padding: [8, 4]`
is the vertical / horizontal pair: 8 px above and below the row,
4 px at the left and right.

### Event log: bounded, scrollable

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

A fixed-height `scrollable` caps the event log at 120 px tall no
matter how many entries accumulate. The inner `column` with
`spacing: 2` and a small `padding` keeps lines dense; the `11`
pt monospace font matches the editor's visual texture without
drawing attention from it.

## Multi-section layouts

The outer column in `view` is a worked example of the pattern:
stack multiple sections vertically with a `column`, let each
section be a helper method returning one subtree, and give each
section its own internal padding and spacing. Sections that
should grow get `height: :fill`; sections with a fixed footprint
(toolbar, log) size themselves at a defined height and let the
main area take the rest.

Reach for `[:fill_portion, n]` only inside a single direction at
a time. Don't mix fixed pixels, `:fill`, and `[:fill_portion, n]`
on the same axis in a single container without tracing through
the resolution order in your head.

## Exercise: sidebar on the right

Rearrange the pad's layout to put the sidebar on the right-hand
side of the window.

Starting point:

```ruby
row("main-row", width: :fill, height: :fill) do
  sidebar(model)
  editor_pane(model)
  preview_pane(model)
end
```

One-line fix: swap the method call order inside the `row`.

```ruby
row("main-row", width: :fill, height: :fill) do
  editor_pane(model)
  preview_pane(model)
  sidebar(model)
end
```

The row lays children out left to right in the order they're
pushed, and the sidebar's fixed 200 px width works just as well
on the right. The editor and preview still split the remaining
space with their `[:fill_portion, 2]` widths.

A harder variant: put the sidebar along the bottom instead, with
the editor above the preview in a single vertical pane. That
requires a `column` where the `row` used to be, and either
switching the editor and preview to stacked `column` members or
keeping them side-by-side and reflowing the chrome around them.
Try both and see which feels right.

## See also

- [Windows and Layout reference](../reference/windows-and-layout.md),
  the full prop tables for every layout container
- [Built-in Widgets reference](../reference/built-in-widgets.md),
  the widget catalog including non-layout widgets
- [Composition Patterns reference](../reference/composition-patterns.md),
  dialogs, popovers, sidebars, and other reusable structures
- [Themes and Styling reference](../reference/themes-and-styling.md),
  `Color`, `Border`, `Shadow`, and the container style presets

## Next chapter

[Styling](08-styling.md)
