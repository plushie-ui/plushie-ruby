# Canvas

Layout containers arrange widgets into rows, columns, and boxes.
That covers most UI, but some things do not fit the widget model:
a sparkline in a toolbar, a pulsing status indicator, a diagram
with arbitrary shapes, a chart with thousands of bars. For those,
Plushie has a canvas: a 2D drawing surface you fill with shapes
instead of widgets.

This chapter covers the canvas DSL, shape primitives, transforms,
layers, and how to slot a small canvas visualization into the
pad's toolbar so the dirty state has a visible pulse. The full
catalogue lives in the
[Canvas reference](../reference/canvas.md).

## Canvas versus widget layout

Reach for a canvas when:

- The visual does not decompose into rectangles (a dial, a graph,
  a badge, a non-rectangular hit target).
- You need thousands of tiny elements drawn efficiently. Each
  canvas is one widget in the tree. The shapes inside do not
  participate in layout and do not emit per-shape events unless
  you wrap them in `canvas_interactive`.
- You want fine control over paint order (per-layer caching) or
  transform composition (rotate / scale / translate a subtree).

Stick with widgets when:

- The content is text, inputs, or standard controls. Built-in
  widgets come with a11y, focus, theming, and platform affordances
  already wired.
- The layout needs to reflow with the window. Canvas coordinates
  are explicit pixels inside a fixed-size drawing surface.

A canvas composes with widgets like any other node: drop one in
a `row` or a `container`, size it, and the rest of the layout
works as usual.

## The canvas DSL

The block form is the primary API. `canvas("id", width:, height:)`
opens a drawing surface; `layer("name")` groups shapes for
caching and z-order; shape methods (`canvas_rect`, `canvas_circle`,
and friends) sit directly inside a layer:

```ruby
canvas("chart", width: 400, height: 200) do
  layer("background") do
    canvas_rect(0, 0, 400, 200, fill: "#f5f5f5")
  end

  layer("data") do
    canvas_rect(10, 50, 80, 150, fill: "#3b82f6")
    canvas_rect(110, 100, 80, 100, fill: "#22c55e")
  end
end
```

Canvas coordinates are pixel-based. The origin is the top-left
corner of the drawing surface; `x` grows to the right and `y`
grows downward. Shapes that fall outside the canvas bounds are
clipped to it by the renderer.

Width and height accept the usual `Plushie::Type::Length` values
(`:shrink`, `:fill`, `[:fill_portion, n]`, or a numeric pixel
size). Most useful canvases use fixed pixel dimensions so their
internal geometry has a stable frame of reference.

For programmatic construction outside a view block, every DSL
method has a pure builder counterpart under `Plushie::Canvas::Shape`
(`Plushie::Canvas::Shape.rect(0, 0, 100, 50, fill: "#3b82f6")`).
The builders return `Data` structs with a `#to_wire` method and
skip the thread-local DSL context. Use the DSL inside `view`;
reach for the builders only when you are assembling shapes in
isolation (a helper method that returns a list for a parent
block to splice in, for example).

## Shape primitives

All shape methods are leaf nodes. They do not take blocks and
cannot contain children. Each returns a descriptor that the
enclosing `canvas` or `layer` block collects.

### canvas_rect

```ruby
canvas_rect(10, 10, 80, 40, fill: "#3b82f6", radius: 4)
```

`canvas_rect(x, y, w, h, **opts)` draws a rectangle. Supported
options: `fill`, `stroke`, `stroke_width`, `opacity`, and `radius`.
`radius:` takes a uniform number or a per-corner hash with
`:top_left`, `:top_right`, `:bottom_right`, `:bottom_left`:

```ruby
canvas_rect(0, 0, 120, 40,
  fill: "#e5e7eb",
  radius: {top_left: 8, bottom_left: 8})
```

### canvas_circle

```ruby
canvas_circle(100, 100, 40, fill: "#22c55e")
```

`canvas_circle(cx, cy, r, **opts)` takes a centre point and
radius. Supports `fill`, `stroke`, `stroke_width`, `opacity`.

### canvas_line

```ruby
canvas_line(0, 0, 100, 100, stroke: "#333333", stroke_width: 2)
```

`canvas_line(x1, y1, x2, y2, **opts)` draws a segment between
two points. A line with no `stroke:` renders nothing.

### canvas_text

```ruby
canvas_text(50, 12, "Hello", fill: "#333333", size: 12)
```

`canvas_text(x, y, content, **opts)` draws text anchored at
`(x, y)`. Supported options: `fill`, `size`, `font`, `opacity`.
Canvas text does not take alignment props; compute the anchor
yourself when you need text centred. For display text inside
a layout, reach for the regular `text` widget instead.

### canvas_path

`canvas_path(commands, **opts)` draws an arbitrary shape built
from path commands:

```ruby
canvas_path([
  Plushie::Canvas::Shape.move_to(10, 0),
  Plushie::Canvas::Shape.line_to(20, 20),
  Plushie::Canvas::Shape.line_to(0, 20),
  Plushie::Canvas::Shape.close
], fill: "#22c55e")
```

Supported options: `fill`, `stroke`, `stroke_width`, `opacity`.

### canvas_image and canvas_svg

Raster images and SVG sources both render into an `(x, y, w, h)`
rectangle:

```ruby
canvas_image("priv/logo.png", 10, 8, 32, 32, opacity: 0.8)
canvas_svg(File.read("priv/icons/save.svg"), 10, 8, 20, 20)
```

`canvas_image` takes a file path or a handle previously registered
with `Plushie::Command.create_image`. `canvas_svg` takes the SVG
XML source as a string; read files with `File.read` before passing
them in. SVG scales cleanly; prefer it for icons and UI chrome.

## Fill and stroke

Both `fill:` and `stroke:` accept any colour string that
`Plushie::Type::Color.cast` recognises: `:red`, `"#3b82f6"`,
`"#3b82f680"` (with alpha), or any CSS4 named colour.

`stroke:` also accepts a `Plushie::Canvas::Shape::Stroke` descriptor
when you need line caps, joins, or dashes:

```ruby
canvas_rect(0, 0, 100, 50,
  fill: "#3b82f6",
  stroke: Plushie::Canvas::Shape.stroke("#1e40af", 2,
    cap: "round",
    join: "round",
    dash: Plushie::Canvas::Shape::Dash.new(segments: [5, 3], offset: 0)))
```

With a bare colour string the `stroke_width:` prop on the shape
sets the width. With a `Stroke` descriptor the width is baked in.

`opacity:` on any shape ranges from 0.0 (fully transparent) to
1.0 (fully opaque).

## Path commands

Path commands are built with module functions on
`Plushie::Canvas::Shape`:

| Function | Signature | Description |
|---|---|---|
| `move_to(x, y)` | pen position | Move without drawing |
| `line_to(x, y)` | line | Straight line to point |
| `bezier_to(cp1x, cp1y, cp2x, cp2y, x, y)` | cubic | Cubic bezier to point |
| `quadratic_to(cpx, cpy, x, y)` | quadratic | Quadratic bezier to point |
| `arc(cx, cy, r, start_angle, end_angle)` | arc | Arc by centre and angle range |
| `close` | none | Close the current subpath |

A closed path with a `fill:` produces a filled polygon. An open
path with only a `stroke:` produces a poly-line. Angles for `arc`
are in radians, measured counter-clockwise from the positive
x-axis.

```ruby
# A triangle
canvas_path([
  Plushie::Canvas::Shape.move_to(50, 0),
  Plushie::Canvas::Shape.line_to(100, 100),
  Plushie::Canvas::Shape.line_to(0, 100),
  Plushie::Canvas::Shape.close
], fill: "#3b82f6")

# A smooth curve
canvas_path([
  Plushie::Canvas::Shape.move_to(0, 80),
  Plushie::Canvas::Shape.bezier_to(30, 0, 70, 0, 100, 80)
], stroke: "#22c55e", stroke_width: 2)
```

## Layers

Layers serve two purposes: they control paint order, and they
each map to their own cache on the renderer side. When a layer's
shapes change, only that layer is re-tessellated. Unchanged
layers draw from cache.

```ruby
canvas("scene", width: 200, height: 200) do
  layer("background") do
    canvas_rect(0, 0, 200, 200, fill: "#ffffff")
  end

  layer("foreground") do
    canvas_circle(100, 100, 20, fill: "#ef4444")
  end
end
```

Layers are drawn in declaration order: the first `layer` block
draws first (bottom), the last block draws last (top). Pick names
that describe each layer's role (`"grid"`, `"data"`, `"labels"`,
`"cursors"`), not its position.

The practical rule: split static content and dynamic content into
separate layers. A static background layer survives every animation
tick from cache while a "cursor" layer on top re-tessellates
freely. A canvas that repaints one layer per frame stays cheap
even as the static chrome grows.

## Structural groups

`canvas_group` nests shapes under shared transforms, clipping, or
opacity. It has no interactive behaviour: no hit testing, no
cursor changes, no focus participation. Use it when you want
several shapes to move, rotate, or clip as a unit.

```ruby
canvas_group(x: 100, y: 50, transforms: [
  Plushie::Canvas::Shape.rotate(45)
]) do
  canvas_rect(0, 0, 40, 40, fill: "#ef4444")
end
```

`canvas_group(id = nil, x:, y:, transforms:, **opts)` takes an
optional explicit ID. The keyword args:

| Keyword | Type | Description |
|---|---|---|
| `x`, `y` | Numeric | Shorthand: prepend a `translate(x, y)` to `transforms` |
| `transforms` | Array | Translate / rotate / scale values |
| `clip` | `Clip` or Hash | Rectangular clip applied to children |
| `opacity` | Numeric | 0.0 to 1.0, compounded with children |

### Transforms

Three transform builders live on `Plushie::Canvas::Shape`:

| Builder | Description |
|---|---|
| `Plushie::Canvas::Shape.translate(x, y)` | Move the group origin |
| `Plushie::Canvas::Shape.rotate(degrees)` | Rotate (degrees by default) |
| `Plushie::Canvas::Shape.scale(factor)` | Uniform scale |
| `Plushie::Canvas::Shape.scale(x, y)` | Non-uniform scale |

Transforms apply in the order they appear in the `transforms:`
array. Composing translate-then-rotate rotates around the new
origin; composing rotate-then-translate translates along the
rotated axes.

```ruby
canvas_group(transforms: [
  Plushie::Canvas::Shape.translate(200, 100),
  Plushie::Canvas::Shape.rotate(30),
  Plushie::Canvas::Shape.scale(1.5)
]) do
  canvas_rect(-20, -20, 40, 40, fill: "#ef4444")
end
```

`rotate` takes degrees by default. Use `rotate(radians: r)` to
pass radians; the constructor converts to degrees internally.

### Clipping

`Plushie::Canvas::Shape::Clip` restricts drawing to a rectangular
region within a group. One clip per group:

```ruby
canvas_group(clip: Plushie::Canvas::Shape.clip(0, 0, 80, 80)) do
  canvas_circle(40, 40, 60, fill: "#3b82f6")
end
```

The circle's radius exceeds the clip rectangle, so only the
portion inside the 80x80 window is drawn.

## Interactive elements

`canvas_interactive("id", ...)` wraps shapes in a hit-testable
element that emits widget events. It requires an explicit string
ID: the ID scopes the event and keys the renderer-side focus and
press tracking.

```ruby
canvas_interactive("save",
  on_click: true,
  cursor: "pointer",
  focusable: true,
  a11y: {role: :button, label: "Save"}) do
  canvas_svg(File.read("priv/icons/save.svg"), 0, 0, 36, 36)
end
```

### Interaction options

| Option | Type | Description |
|---|---|---|
| `on_click` | Boolean | Emit `:click` events |
| `on_hover` | Boolean | Emit `:enter` and `:exit` events |
| `draggable` | Boolean | Emit `:drag` and `:drag_end` events |
| `cursor` | String | Cursor on hover (`"pointer"`, `"grab"`, etc.) |
| `tooltip` | String | Tooltip text on hover |
| `focusable` | Boolean | Include in the Tab focus order |
| `hover_style` | Hash | Override fill, stroke, opacity on hover |
| `pressed_style` | Hash | Override while pressed |
| `focus_style` | Hash | Override while keyboard-focused |
| `a11y` | Hash | Accessibility role and label overrides |

`hover_style:` and `pressed_style:` change the visual appearance
during interaction. No event handling required; the renderer
applies them automatically:

```ruby
canvas_interactive("save",
  on_click: true,
  cursor: "pointer",
  hover_style: {fill: "#2563eb"},
  pressed_style: {fill: "#1d4ed8"}) do
  canvas_rect(0, 0, 100, 36, fill: "#3b82f6", radius: 6)
  canvas_text(30, 11, "Save", fill: "#ffffff", size: 14)
end
```

Only the properties you specify in the override hash change; the
rest inherit from the shape's base values.

### Accessibility

Built-in widgets know their own accessibility story. A canvas
cannot: it is a raw drawing surface. `canvas_interactive`
fills in sensible defaults based on its flags
(`on_click: true` defaults to `role: "button"`,
`draggable: true` defaults to `role: "slider"`), but the `label`
and any role beyond those defaults must come from an explicit
`a11y:` hash. Pass `focusable: true` to put the element in the
keyboard focus chain; without it the element is pointer-only.

### Canvas-level versus element-level events

The canvas widget itself can emit unified pointer events when
`on_press:`, `on_release:`, `on_move:`, or `on_scroll:` is set.
These target the canvas ID and carry canvas-local coordinates in
the `value` field:

```ruby
canvas("drawing", width: 400, height: 300, on_press: true, on_move: true)

# In update:
case event
in Event::Widget[type: :press, id: "drawing",
    value: {x:, y:, pointer: :mouse, button: :left}]
  start_stroke(model, x, y)
in Event::Widget[type: :move, id: "drawing",
    value: {x:, y:}]
  continue_stroke(model, x, y)
end
```

Element-level events carry the ID of the interactive group. The
canvas ID appears in `scope`:

```ruby
case event
in Event::Widget[type: :click, id: "save", scope: ["save-canvas", *]]
  save_file(model)
end
```

Match the scope when multiple canvases share element IDs, or
when a plain widget elsewhere in the tree uses the same id.

## Adding a pulsing dirty indicator to the pad

Back to the pad. The toolbar has a Save button and an auto-save
checkbox. The model already carries a `dirty` flag (set whenever
the editor content changes; cleared on save). A small pulsing
dot next to the Save button gives the dirty state a visible beat.

We build it as a 16x16 canvas with a single circle. When
`model.dirty` is true, the circle fills with a warning colour
and its radius cycles between two values driven by an animation
tick. When the file is clean, the canvas draws nothing.

First, drive the pulse from the model. Add a `pulse` field to
the pad's model, incremented on each animation frame while the
file is dirty:

```ruby
def subscribe(model)
  subs = []
  subs << Plushie::Subscription.on_animation_frame if model.dirty
  subs
end

def update(model, event)
  case event
  in Event::System[type: :animation_frame, data: delta_ms]
    next_pulse = (model.pulse + delta_ms * 0.004) % (Math::PI * 2)
    model.with(pulse: next_pulse)
  # ... existing clauses
  end
end
```

The subscription only runs while `model.dirty` is true, so a
clean file does not spin the frame loop. `delta_ms` is the
milliseconds since the previous frame; multiplying by 0.004
gives a pulse period of around 1.5 seconds, which reads as a
slow breath rather than a flicker.

Next, the canvas itself. Derive a radius from the pulse angle
using a sine wave offset so the dot never fully vanishes:

```ruby
def dirty_indicator(model)
  return nil unless model.dirty

  radius = 4.0 + Math.sin(model.pulse) * 2.0

  canvas("dirty", width: 16, height: 16) do
    layer("dot") do
      canvas_circle(8, 8, radius, fill: "#f59e0b")
    end
  end
end
```

`Math.sin(model.pulse)` swings between -1.0 and 1.0, so the
radius swings between 2 and 6 pixels. Early return with `nil`
when the model is clean so the toolbar skips the canvas entirely.

Finally, slot it into the toolbar next to the Save button:

```ruby
def toolbar(model)
  row("toolbar", padding: [8, 4], spacing: 8) do
    button("save", "Save", style: :primary)
    dirty_indicator(model)
    checkbox("auto-save", model.auto_save, label: "Auto-save")
    text_input("new-name", model.new_name,
      placeholder: "new_name.rb",
      on_submit: true)
  end
end
```

Because `dirty_indicator` returns either a canvas node or `nil`,
the block DSL drops the `nil` case from the row and the other
children close up around it. The pulse only draws when there
is something to save.

## Exercise: a rounded active-file row

The pad's sidebar uses a plain `button` for each file. Swap the
active file's row for a canvas-drawn rounded rectangle that
shows the filename and clicks through the same as before.

Starting point (from chapter 6 / 7):

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

The canvas version replaces the select button with a 160x28
canvas that draws a rounded fill behind the filename. The delete
button stays as-is:

```ruby
def file_row(model, file)
  container(file, padding: 4) do
    row("row", spacing: 4) do
      file_select_canvas(model, file)
      button("delete", "x", style: :danger)
    end
  end
end

def file_select_canvas(model, file)
  active = (model.active_file == file)
  fill = active ? "#3b82f6" : "#1f2937"
  text_color = active ? "#ffffff" : "#e5e7eb"

  canvas("#{file}-row", width: 160, height: 28) do
    layer("row") do
      canvas_interactive("select",
        on_click: true,
        cursor: "pointer",
        a11y: {role: :button, label: "Open #{file}"}) do
        canvas_rect(0, 0, 160, 28, fill: fill, radius: 6)
        canvas_text(8, 8, file, fill: text_color, size: 12)
      end
    end
  end
end
```

A click on the canvas fires a widget event with `id: "select"`
and `scope: ["#{file}-row", "sidebar", ..., "main"]`. The
existing click handler for `"select"` keeps working; the canvas
ID in scope lets you disambiguate the canvas version from a
plain button should both ever coexist.

Once that is in place, try variations:

- Add a hover style that tints the fill when the pointer is over
  the row.
- Extend the canvas with a small circle on the right edge that
  appears only when `file == model.active_file`, giving the
  active row a visible marker beyond the fill colour.
- Wrap the filename in a `canvas_group` with `clip:` set to the
  canvas bounds so long filenames get clipped rather than
  drawing past the rounded corners.

## See also

- [Canvas reference](../reference/canvas.md), the complete shape
  catalogue, path commands, interactive element props, and canvas
  widget class protocol
- [Built-in Widgets reference](../reference/built-in-widgets.md),
  the canvas widget listed alongside the rest of the widget set
- [Events reference](../reference/events.md), pointer event shapes
  and the `Event::Widget` pattern matches used for canvas events
- [Scoped IDs reference](../reference/scoped-ids.md), how canvas
  IDs combine with interactive element IDs in the event `scope`
- [Accessibility reference](../reference/accessibility.md), the
  `a11y:` field on `canvas_interactive`, default role inference,
  and keyboard focus behaviour

## Next chapter

[Custom Widgets](13-custom-widgets.md)
