# Canvas

The canvas widget is a 2D drawing surface. Shapes, paths, text,
images, and interactive elements compose into named layers drawn on
top of each other. The widget lives in `Plushie::Widget::Canvas`;
shape builders and value types live under `Plushie::Canvas::Shape`;
the block DSL methods (`canvas`, `layer`, `canvas_rect`,
`canvas_interactive`, and so on) are mixed in by `Plushie::App`
alongside the rest of the widget DSL.

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

Unlike layout widgets, the canvas does not compose its children
visually: shape nodes are drawing instructions, not widgets. Shapes
do not participate in layout, do not emit their own status events,
and are not reachable by the focus chain unless they sit inside a
`canvas_interactive` element.

## Canvas widget

`Plushie::Widget::Canvas`

Declarative widget with a `"canvas"` wire type. Takes a required
string ID (no auto-ID form: stateful widgets need stable IDs for
event routing) and options for size, background, pointer event
enablement, and accessibility.

### Props

| Prop | Type | Description |
|---|---|---|
| `width` | Length | Canvas width |
| `height` | Length | Canvas height |
| `background` | Color | Fill drawn beneath all layers |
| `interactive` | Boolean | Enable hit testing for `canvas_interactive` elements |
| `on_press` | Boolean | Emit canvas-level `:press` events |
| `on_release` | Boolean | Emit canvas-level `:release` events |
| `on_move` | Boolean | Emit canvas-level `:move` events (coalescable) |
| `on_scroll` | Boolean | Emit canvas-level `:scroll` events (coalescable) |
| `alt` | String | Accessible name for the drawing surface |
| `description` | String | Extended description for assistive technology |
| `role` | String or Symbol | ARIA role override (default `:canvas`) |
| `arrow_mode` | String | `"focus"`, `"scroll"`, or `"none"` (arrow key behaviour) |
| `event_rate` | Integer | Max events per second for coalescable pointer events |
| `a11y` | Hash | Accessibility overrides (see [Accessibility reference](accessibility.md)) |

The default role is `:canvas`. Provide `alt` so screen readers have
text to announce; `role` can escalate that to a semantic grouping
role (for example `"radiogroup"` when the canvas hosts a set of
mutually exclusive interactive elements). `arrow_mode: "focus"`
lets the user Tab and arrow between interactive elements inside the
canvas; `"scroll"` forwards arrow keys to the surrounding scrollable
container instead.

### Builder form

`Plushie::Widget::Canvas.new("drawing", width: 400, height: 300)`
returns a typed builder. The `#add_layer(name, shape_nodes)` method
appends a pre-built layer, and `#build` produces the final node.
Use the block DSL for app views; use the builder only when
assembling a canvas subtree outside a view block.

## Layers

Layers group shapes for z-ordering and caching. Each layer maps to
its own cache on the renderer side, so when a layer's shapes change
only that layer is re-tessellated. Unchanged layers are drawn from
cache.

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

Layers are drawn in declaration order: the first `layer` block draws
first (bottom), the last `layer` block draws last (top). Naming is
arbitrary; pick names that describe the role (`"grid"`, `"data"`,
`"labels"`, `"cursors"`). Split static and dynamic content into
separate layers so re-tessellation only touches the moving parts.

On the wire, `layer("name")` encodes as a child node with
`type: "__layer__"`.

## Shape primitives

All shape DSL methods sit directly inside a `canvas` or `layer`
block. They are leaf nodes: no children, auto-generated IDs. For
programmatic construction outside a view block, call the
corresponding builder in `Plushie::Canvas::Shape` (for example
`Plushie::Canvas::Shape.rect(0, 0, 100, 50, fill: "#3b82f6")`),
which returns a `Data` struct with a `#to_wire` method.

### Rectangle

```ruby
canvas_rect(10, 10, 80, 40, fill: "#3b82f6", radius: 4)
```

| Prop | Type | Description |
|---|---|---|
| `fill` | Color or gradient | Interior fill |
| `stroke` | Color or `Stroke` | Outline (shorthand colour or full descriptor) |
| `stroke_width` | Number | Outline width when `stroke` is a bare colour |
| `opacity` | Number | 0.0 to 1.0 |
| `radius` | Number or Hash | Uniform corner radius, or per-corner hash |

The `radius:` hash takes `:top_left`, `:top_right`, `:bottom_right`,
`:bottom_left`. Only specified corners are rounded; others remain
square.

### Circle

```ruby
canvas_circle(100, 100, 40, fill: "#22c55e")
```

`canvas_circle(cx, cy, r, **opts)` takes a centre point and radius.
Supports `fill`, `stroke`, `stroke_width`, `opacity`.

### Line

```ruby
canvas_line(0, 0, 100, 100, stroke: "#333", stroke_width: 2)
```

`canvas_line(x1, y1, x2, y2, **opts)` draws a segment between two
points. Supports `stroke`, `stroke_width`, `opacity`. A line with no
stroke draws nothing.

### Text

```ruby
canvas_text(50, 190, "A", fill: "#333", size: 12)
```

`canvas_text(x, y, content, **opts)` draws text anchored at
`(x, y)`. Supports `fill`, `size`, `font`, `opacity`. Canvas text
uses `Plushie::Canvas::Shape::CanvasText` on the SDK side to avoid
name collision with the regular `text` widget.

### Path

`canvas_path(commands, **opts)` draws a freeform shape built from
path commands:

```ruby
canvas_path([
  Plushie::Canvas::Shape.move_to(10, 0),
  Plushie::Canvas::Shape.line_to(20, 20),
  Plushie::Canvas::Shape.line_to(0, 20),
  Plushie::Canvas::Shape.close
], fill: "#22c55e")
```

Path commands are built with these module functions on
`Plushie::Canvas::Shape`:

| Function | Signature | Description |
|---|---|---|
| `move_to(x, y)` | `[x, y]` | Move pen without drawing |
| `line_to(x, y)` | `[x, y]` | Straight line to point |
| `bezier_to(cp1x, cp1y, cp2x, cp2y, x, y)` | cubic | Cubic bezier curve |
| `quadratic_to(cpx, cpy, x, y)` | quadratic | Quadratic bezier curve |
| `arc(cx, cy, r, start_angle, end_angle)` | arc | Arc by centre |
| `close` | none | Close the current subpath |

Paths support `fill`, `stroke`, `stroke_width`, `opacity`. A closed
path with a fill produces a filled polygon; an open path with only
a stroke produces a poly-line.

### Image

```ruby
canvas_image("priv/images/logo.png", 50, 8, 32, 32, opacity: 0.8)
```

`canvas_image(source, x, y, w, h, **opts)` renders a raster image.
The `source` is either a file path the renderer can read or a
handle name previously registered with
`Plushie::Command.create_image`. Supports `rotation` (degrees) and
`opacity`.

### SVG

```ruby
canvas_svg(File.read("priv/icons/save.svg"), 10, 8, 20, 20)
```

`canvas_svg(source, x, y, w, h)` renders an SVG source string into
a rectangle. The `source` is the SVG XML content itself: read files
from disk with `File.read` before passing them in.

## Groups

`canvas_group` nests shapes under shared transforms, clipping, or
accessibility context. It has no interactive behaviour: no hit
testing, no cursor changes, no focus participation. Use it when you
want several shapes to move, rotate, or clip as a unit.

```ruby
canvas_group(x: 100, y: 50, transforms: [
  Plushie::Canvas::Shape.rotate(45)
]) do
  canvas_rect(0, 0, 40, 40, fill: "#ef4444")
end
```

`canvas_group(id = nil, x:, y:, transforms:, **opts, &block)` takes
an optional explicit ID and the following keyword arguments:

| Keyword | Type | Description |
|---|---|---|
| `x`, `y` | Number | Convenience: prepend a `translate(x, y)` to `transforms` |
| `transforms` | `[Transform]` | Array of `Translate`, `Rotate`, `Scale` values |
| `clip` | `Clip` or Hash | Clip region applied to children |
| `opacity` | Number | 0.0 to 1.0, compounded with children's opacity |

When no ID is given, an auto ID is generated from a canvas-scoped
counter. Structural groups are transparent to the scope chain; only
`canvas_interactive` creates event-bearing scope.

## Interactive elements

`canvas_interactive` wraps a group of shapes in a hit-testable
element that emits widget events. It requires an explicit string
ID: the ID both scopes the event and keys the renderer-side focus
and press tracking.

```ruby
canvas_interactive("save",
  on_click: true,
  cursor: "pointer",
  focusable: true,
  a11y: {role: :button, label: "Save"}) do
  canvas_svg(File.read("priv/icons/save.svg"), 0, 0, 36, 36)
end
```

On the wire, `canvas_interactive` and `canvas_group` both encode as
`type: "group"`. The split is SDK-side only: it communicates intent
at the call site.

### Interaction props

| Prop | Type | Description |
|---|---|---|
| `on_click` | Boolean | Emit `:click` events |
| `on_hover` | Boolean | Emit `:enter` and `:exit` events |
| `draggable` | Boolean | Emit `:drag` and `:drag_end` events |
| `drag_axis` | `"x"`, `"y"`, `"both"` | Constrain drag direction |
| `drag_bounds` | `DragBounds` or Hash | Clamp drag coordinates |
| `hit_rect` | `HitRect` or Hash | Override the default hit region |
| `cursor` | String | Cursor on hover (`"pointer"`, `"grab"`, etc.) |
| `tooltip` | String | Tooltip text on hover |
| `focusable` | Boolean | Include in Tab order |
| `show_focus_ring` | Boolean | Draw the default focus indicator |
| `focus_ring_radius` | Number | Corner radius for the focus ring |
| `hover_style` | `ShapeStyle` or Hash | Override fill, stroke, opacity on hover |
| `pressed_style` | `ShapeStyle` or Hash | Override while pressed |
| `focus_style` | `ShapeStyle` or Hash | Override while keyboard-focused |
| `a11y` | Hash | Accessibility overrides |

When `a11y` is omitted, the SDK fills in a sensible default based on
the other flags: `focusable: true` defaults to `role: "group"`,
`on_click: true` defaults to `role: "button"`, and
`draggable: true` defaults to `role: "slider"`. Any explicit `a11y`
hash wins over the defaults.

### HitRect and DragBounds

By default, the hit region is the bounding box of the element's
shapes. Override it with an explicit rectangle to enlarge a small
target or to treat a complex group as a simple rectangle:

```ruby
canvas_interactive("handle",
  on_click: true,
  hit_rect: Plushie::Canvas::Shape::HitRect.new(x: -10, y: -10, w: 40, h: 40)) do
  canvas_circle(0, 0, 6, fill: "#3b82f6")
end
```

`DragBounds` clamps drag coordinates:

```ruby
canvas_interactive("knob",
  draggable: true,
  drag_axis: "x",
  drag_bounds: Plushie::Canvas::Shape::DragBounds.new(min_x: 0, max_x: 300)) do
  canvas_rect(-8, -8, 16, 16, fill: "#3b82f6")
end
```

Any of `:min_x`, `:max_x`, `:min_y`, `:max_y` may be omitted; only
the specified axes are clamped. A plain hash with the same keys is
accepted in place of the struct.

### ShapeStyle

`Plushie::Canvas::Shape::ShapeStyle` carries visual overrides for
interactive states:

```ruby
Plushie::Canvas::Shape::ShapeStyle.new(
  fill: "#2563eb",
  stroke: Plushie::Canvas::Shape.stroke("#1e40af", 2),
  opacity: 0.9
)
```

Only specified fields are overridden; unspecified fields inherit
from the shape's base values. The block DSL also accepts a plain
hash with the same keys.

## Transforms

Transforms apply to groups, not individual shapes. They are applied
in the order they appear in the `transforms:` array.

| Builder | Description |
|---|---|
| `Plushie::Canvas::Shape.translate(x, y)` | Move the group origin |
| `Plushie::Canvas::Shape.rotate(degrees)` | Rotate (degrees by default) |
| `Plushie::Canvas::Shape.rotate(radians: r)` | Rotate in radians (converted to degrees) |
| `Plushie::Canvas::Shape.scale(factor)` | Uniform scale |
| `Plushie::Canvas::Shape.scale(x, y)` | Non-uniform scale |
| `Plushie::Canvas::Shape.scale_uniform(factor)` | Uniform scale (explicit name) |

```ruby
canvas_group(transforms: [
  Plushie::Canvas::Shape.translate(200, 100),
  Plushie::Canvas::Shape.rotate(30),
  Plushie::Canvas::Shape.scale(1.5)
]) do
  canvas_rect(-20, -20, 40, 40, fill: "#ef4444")
end
```

The `x:` and `y:` keyword arguments on `canvas_group` and
`canvas_interactive` are shorthand for a leading `translate(x, y)`;
they compose with any explicit `transforms:` array.

## Clips

`Plushie::Canvas::Shape::Clip` restricts drawing to a rectangular
region within a group. One clip per group.

```ruby
canvas_group(clip: Plushie::Canvas::Shape.clip(0, 0, 80, 80)) do
  canvas_circle(40, 40, 60, fill: "#3b82f6")
end
```

The circle's radius exceeds the clip, so only the portion inside
the 80x80 window is drawn.

## Stroke and Dash

`Plushie::Canvas::Shape.stroke(color, width, **opts)` produces a
stroke descriptor for the `stroke:` prop on shapes that support
outlines:

```ruby
canvas_rect(0, 0, 100, 50,
  fill: "#3b82f6",
  stroke: Plushie::Canvas::Shape.stroke("#1e40af", 2,
    cap: "round",
    join: "round",
    dash: Plushie::Canvas::Shape::Dash.new(segments: [5, 3], offset: 0)))
```

| Option | Values | Description |
|---|---|---|
| `cap` | `"butt"`, `"round"`, `"square"` | Line end style |
| `join` | `"miter"`, `"round"`, `"bevel"` | Corner join style |
| `dash` | `Dash` or Hash | Dash pattern |

`Plushie::Canvas::Shape::Dash.new(segments:, offset:)` takes an
array of segment lengths (alternating dash and gap) and an initial
offset along that pattern.

Strokes accept a bare colour string (`stroke: "#333"`) when no cap,
join, or dash is needed. Combine with a separate `stroke_width:`
prop on the shape to set the width.

## Linear gradients

`Plushie::Canvas::Shape.linear_gradient(from, to, stops)` builds a
gradient fill usable anywhere a colour is accepted. Coordinates are
in canvas space, not angles:

```ruby
canvas_rect(0, 0, 200, 50,
  fill: Plushie::Canvas::Shape.linear_gradient(
    [0, 0], [200, 0],
    [[0.0, "#3b82f6"], [1.0, "#1d4ed8"]]))
```

`from` and `to` are `[x, y]` pairs. `stops` is an array of
`[offset, colour]` pairs where offset is 0.0-1.0. This canvas
gradient is distinct from `Plushie::Type::Gradient.linear` (angle
based, used for widget backgrounds).

## Canvas-level events

When `on_press`, `on_release`, `on_move`, or `on_scroll` is set on
the canvas widget, the renderer emits unified pointer events with
canvas-local coordinates. All such events target the canvas ID
itself, not any interactive child. The `pointer` field identifies
the input device (`:mouse`, `:touch`, `:pen`); `modifiers` carries
the current key modifier state.

```ruby
case event
in Event::Widget[type: :press, id: "drawing",
    value: {x:, y:, pointer: :mouse, button: :left}]
  start_stroke(model, x, y)

in Event::Widget[type: :move, id: "drawing",
    value: {x:, y:, pointer: :touch, finger: 0}]
  continue_stroke(model, x, y)

in Event::Widget[type: :scroll, id: "drawing",
    value: {delta_y:, modifiers: {control: true}}]
  zoom(model, delta_y)
end
```

See the [Events reference](events.md) for the full pointer event
shape and the `:mouse`, `:touch`, `:pen` distinction.

## Element-level events

Interactive elements emit generic widget events carrying their own
ID. The canvas widget's ID appears in `scope` so the app can tell
which canvas the element belongs to.

| Event type | Requires | Value fields |
|---|---|---|
| `:click` | `on_click: true` | (none) |
| `:enter` | `on_hover: true` | `x`, `y` |
| `:exit` | `on_hover: true` | `x`, `y` |
| `:drag` | `draggable: true` | `x`, `y`, `delta_x`, `delta_y` |
| `:drag_end` | `draggable: true` | `x`, `y` |
| `:focused` | `focusable: true` | (none) |
| `:blurred` | `focusable: true` | (none) |
| `:key_press` | `focusable: true` | `key`, `modifiers`, `text`, ... |
| `:key_release` | `focusable: true` | `key`, `modifiers`, ... |

Match them like any scoped widget event:

```ruby
case event
in Event::Widget[type: :click, id: element_id, scope: ["chart", *]]
  select_bar(model, element_id)

in Event::Widget[type: :drag, id: "handle", scope: ["slider", *],
    value: {x:, y:}]
  model.with(handle_x: x, handle_y: y)
end
```

The canvas ID sits at the front of `scope` (immediate parent first);
the window ID is the last element. See the
[Scoped IDs reference](scoped-ids.md) for the full scope layout.

## Canvas widgets

Canvas content with reusable internal state and event transformation
lives in a canvas widget: a Ruby class that renders itself into
shapes and intercepts events before they reach the app.

```ruby
class ToggleSwitch
  include Plushie::CanvasWidget

  canvas_widget :toggle_switch

  def self.init = {hover: false}

  def self.view(id, props, state)
    include Plushie::UI

    on = props[:on] || false
    thumb_x = on ? 44 : 20

    canvas(id, width: 64, height: 32) do
      layer("track") do
        canvas_interactive("toggle",
          on_click: true,
          on_hover: true,
          cursor: "pointer",
          a11y: {role: :switch, label: props[:label], toggled: on}) do
          canvas_rect(0, 0, 64, 32,
            fill: on ? "#3b82f6" : "#dddddd",
            radius: 16)
          canvas_circle(thumb_x, 16, 12, fill: "#ffffff")
        end
      end
    end
  end

  def self.handle_event(event, state)
    case event
    in Event::Widget[type: :click, id: "toggle"]
      [:emit, :toggle, {value: !state[:hover]}, state]

    in Event::Widget[type: :enter, id: "toggle"]
      [:update_state, state.merge(hover: true)]

    in Event::Widget[type: :exit, id: "toggle"]
      [:update_state, state.merge(hover: false)]

    else
      [:ignored, state]
    end
  end
end
```

### Class methods

| Method | Signature | Description |
|---|---|---|
| `canvas_widget(type_name)` | Symbol | Declares the widget type name |
| `init` | `-> Hash` | Returns the initial state hash |
| `view(id, props, state)` | ID, Hash, Hash | Returns a canvas node |
| `handle_event(event, state)` | event, state | Returns an action tuple |
| `subscribe(props, state)` | optional | Returns subscriptions to run while mounted |

### Action tuples from `handle_event`

| Return | Effect |
|---|---|
| `[:ignored, state]` | Event passes through to the next handler or the app |
| `[:consumed, state]` | Event is suppressed |
| `[:update_state, state]` | State updated; event suppressed |
| `[:emit, kind, data, state]` | Event replaced with `Event::Widget[type: kind, value: data]` and continues |

The runtime walks the scope chain from innermost widget to outermost
before delivering events to `update`. Each widget gets a chance to
handle the event. Emitted events carry the widget's own scoped ID
and flow through any outer widgets in the chain.

### Subscriptions

`subscribe(props, state)` returns an array of subscriptions, the
same shape as the app-level `subscribe` callback. Timer events
dispatched to the widget arrive through `handle_event` with the
original tag. Use this for widgets that need animation frames or
polling while mounted.

### Placement

Canvas widgets must be rendered inside a window. A widget placed
outside any window raises during normalisation. Within a window,
widget state is keyed by the full scoped ID (`window#path`), so
moving a widget between containers discards its state.

## See also

- [Built-in Widgets reference](built-in-widgets.md) - the canvas
  widget alongside the rest of the widget catalog
- [Events reference](events.md) - pointer event fields, element
  events, and the `Event::Widget` pattern-matching shapes
- [Scoped IDs reference](scoped-ids.md) - how canvas IDs and
  interactive element IDs combine in the `scope` chain
- [Accessibility reference](accessibility.md) - `a11y` fields,
  roles, and the default role inference for interactive elements
- [Commands reference](commands.md) - `focus` and `create_image`
  for driving canvas content from the app
