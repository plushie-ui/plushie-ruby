# Writing Widget Extensions

Guide for building custom widget extensions for Plushie. Extensions let you
render arbitrary Rust-native widgets while keeping your app's state and logic
in Ruby.

## Quick start

An extension has two halves:

1. **Ruby side:** use `include Plushie::Extension`. This declares the widget's
   props, commands, and (for native widgets) the Rust crate and constructor.

2. **Rust side:** implement the `WidgetExtension` trait from `plushie-core`. This
   receives tree nodes from Ruby and returns `iced::Element`s for rendering.

```ruby
# lib/my_sparkline/extension.rb
class MySparkline
  include Plushie::Extension

  widget :sparkline, kind: :native_widget

  rust_crate "native/my_sparkline"
  rust_constructor "my_sparkline::SparklineExtension::new()"

  prop :data, [:list, :number], doc: "Sample values to plot"
  prop :color, :color, default: "#4CAF50", doc: "Line color"
  prop :capacity, :number, default: 100, doc: "Max samples in the ring buffer"

  command :push, value: :number
end
```

This generates:

- `MySparkline.new(id, opts)` -- builds a widget node with typed props
- `MySparkline.push(widget, value:)` -- sends a command to the Rust extension
- `MySparkline.type_names`, `native_crate`, `rust_constructor` methods

```rust
// native/my_sparkline/src/lib.rs
use plushie_core::prelude::*;

pub struct SparklineExtension;

impl SparklineExtension {
    pub fn new() -> Self { Self }
}

impl WidgetExtension for SparklineExtension {
    fn type_names(&self) -> &[&str] { &["sparkline"] }
    fn config_key(&self) -> &str { "sparkline" }

    fn render<'a>(&self, node: &'a TreeNode, env: &WidgetEnv<'a>) -> Element<'a, Message> {
        let label = prop_str(node, "label").unwrap_or_default();
        text(label).into()
    }
}
```

Build with `bundle exec rake plushie:build` (extensions are registered via
configuration).

## Extension kinds

### `:native_widget` -- Rust-backed extensions

Use `widget :name, kind: :native_widget` for widgets rendered by a Rust
crate. Requires `rust_crate` and `rust_constructor` declarations.

```ruby
class MyApp::HexView
  include Plushie::Extension

  widget :hex_view, kind: :native_widget
  rust_crate "native/hex_view"
  rust_constructor "hex_view::HexViewExtension::new()"

  prop :data, :string, doc: "Binary data (base64)"
  prop :columns, :number, default: 16
end
```

### `:widget` -- Pure Ruby composite widgets

Use `widget :name, kind: :widget` for widgets composed entirely from
existing Plushie widgets. No Rust code needed. Define a `render` method.

```ruby
class MyApp::Card
  include Plushie::Extension

  widget :card, kind: :widget, container: true

  prop :title, :string
  prop :subtitle, :string, default: nil

  def render(id, props, children)
    column(padding: 16, spacing: 8) do
      text("ext_title", props[:title], size: 20)
      text("ext_subtitle", props[:subtitle], size: 14) if props[:subtitle]
      children.each { |child| child }
    end
  end
end
```

## DSL reference

| Method | Required | Description |
|---|---|---|
| `widget :name` | yes | Declares the widget type name |
| `widget :name, container: true` | -- | Marks as accepting children |
| `prop :name, :type` | no | Declares a prop with type |
| `prop :name, :type, opts` | no | Options: `default:`, `doc:` |
| `command :name, params` | no | Declares a command (native widgets only) |
| `rust_crate "path"` | native only | Path to the Rust crate |
| `rust_constructor "expr"` | native only | Rust constructor expression |

### Automatic DSL integration

`prop` declarations automatically generate the callbacks that the DSL
uses for option validation and block-form construction. Extension widgets
work with block-form options out of the box -- no extra boilerplate needed.

When a prop's type maps to a struct type (e.g. `:padding` maps to
`Plushie::Type::Padding`), the extension widget automatically supports
nested block construction for that prop:

```ruby
class MyApp::Card
  include Plushie::Extension

  widget :card, kind: :widget, container: true

  prop :title, :string
  prop :padding, :padding, default: 0
  prop :border, :border, default: nil
end

# In a view:
my_card("info", title: "Details") do
  border do
    width 1
    color "#ddd"
    rounded 4
  end
  padding 16

  text("Card content here")
end
```

### Supported prop types

`:number`, `:string`, `:boolean`, `:color`, `:length`, `:padding`,
`:alignment`, `:font`, `:style`, `:atom`, `:map`, `:any`, `[:list, inner]`

The `a11y` and `event_rate` options are available on all extension
widgets automatically. You do not need to declare them with `prop`.

The `a11y` hash supports all standard fields including `disabled`,
`position_in_set`, `size_of_set`, and `has_popup` -- useful when
building accessible composite widgets from extension primitives.

## Extension tiers

Not every extension needs the full trait. The `WidgetExtension` trait has
sensible defaults for all methods except `type_names`, `config_key`, and
`render`. Choose the tier that fits your widget:

### Tier A: render-only

Implement `type_names`, `config_key`, and `render`. Everything else uses
defaults. Good for widgets that compose existing iced widgets (e.g.
`column`, `row`, `text`, `scrollable`, `container`) with no Rust-side
interaction state.

```rust
impl WidgetExtension for HexViewExtension {
    fn type_names(&self) -> &[&str] { &["hex_view"] }
    fn config_key(&self) -> &str { "hex_view" }

    fn render<'a>(&self, node: &'a TreeNode, env: &WidgetEnv<'a>) -> Element<'a, Message> {
        // Compose standard iced widgets from node props
        let data = prop_str(node, "data").unwrap_or_default();
        // ... build column/row/text layout ...
        container(content).into()
    }
}
```

### Tier B: interactive (+handle_event)

Add `handle_event` to intercept events from your widgets before they reach
Ruby. Use this when the extension needs to process mouse/keyboard input
internally (pan, zoom, hover tracking) or transform events before forwarding.
For example, a canvas-based plotting widget might handle pan/zoom entirely
in Rust while forwarding click events to Ruby as semantic `plot_click`
events.

```rust
fn handle_event(
    &mut self,
    node_id: &str,
    family: &str,
    data: &Value,
    caches: &mut ExtensionCaches,
) -> EventResult {
    match family {
        "canvas_press" => {
            // Transform raw canvas coordinates into plot-space click
            let x = data.get("x").and_then(|v| v.as_f64()).unwrap_or(0.0);
            let y = data.get("y").and_then(|v| v.as_f64()).unwrap_or(0.0);
            let plot_event = OutgoingEvent::extension_event(
                "plot_click".to_string(),
                node_id.to_string(),
                Some(serde_json::json!({"plot_x": x, "plot_y": y})),
            );
            EventResult::Consumed(vec![plot_event])
        }
        "canvas_move" => {
            // Update hover state internally, don't forward
            EventResult::Consumed(vec![])
        }
        _ => EventResult::PassThrough,
    }
}
```

#### Throttling high-frequency extension events (CoalesceHint)

If your extension emits events on every mouse move or at frame rate,
the host receives far more events than it needs, and over SSH or
slow connections the unthrottled traffic can stall the UI entirely.
The renderer can buffer these and deliver only the latest value (or
accumulated deltas) at a controlled rate. Mark events with a
`CoalesceHint` to opt in. Events without a hint are always delivered
immediately -- the right default for clicks, selections, and other
discrete actions.

```rust
// Latest value wins -- position tracking, state snapshots
let event = OutgoingEvent::extension_event("cursor_pos", node_id, data)
    .with_coalesce(CoalesceHint::Replace);

// Deltas sum -- scroll, velocity, counters
let event = OutgoingEvent::extension_event("pan_scroll", node_id, data)
    .with_coalesce(CoalesceHint::Accumulate(
        vec!["delta_x".into(), "delta_y".into()]
    ));

// No hint -- discrete actions are never coalesced
let event = OutgoingEvent::extension_event("node_selected", node_id, data);
```

The hint declares how to coalesce; `event_rate` on the widget node
controls frequency. Set `event_rate` from Ruby:

```ruby
MyPlot.new("plot1", data: chart_data, event_rate: 30)
```

Both are in the prelude (`CoalesceHint`, `OutgoingEvent`).

### Tier C: full lifecycle (+prepare, handle_command, cleanup)

Add `prepare` for mutable state synchronization before each render pass,
`handle_command` for commands sent from Ruby to the extension, and
`cleanup` for resource teardown when nodes are removed. Typical uses
include ring buffers fed by extension commands with canvas rendering,
generation-tracked cache invalidation, and custom `iced::advanced::Widget`
implementations with viewport state, hit testing, and pan/zoom persisted
in `ExtensionCaches`.

```rust
fn prepare(&mut self, node: &TreeNode, caches: &mut ExtensionCaches, theme: &Theme) {
    // Initialize or sync per-node state.
    // First arg is the namespace (typically config_key()), second is the node ID.
    let state = caches.get_or_insert::<SparklineState>(self.config_key(), &node.id, || {
        SparklineState::new(prop_usize(node, "capacity").unwrap_or(100))
    });
    // Update from props if needed
    state.color = prop_color(node, "color");
}

fn handle_command(
    &mut self,
    node_id: &str,
    op: &str,
    payload: &Value,
    caches: &mut ExtensionCaches,
) -> Vec<OutgoingEvent> {
    match op {
        "push" => {
            if let Some(state) = caches.get_mut::<SparklineState>(self.config_key(), node_id) {
                if let Some(value) = payload.as_f64() {
                    state.push(value as f32);
                    state.generation.bump();
                }
            }
            vec![]
        }
        _ => vec![],
    }
}

fn cleanup(&mut self, node_id: &str, caches: &mut ExtensionCaches) {
    caches.remove(self.config_key(), node_id);
}
```

The full list of trait methods:

| Method | Required | Phase | Receives | Returns |
|---|---|---|---|---|
| `type_names` | yes | registration | -- | `&[&str]` |
| `config_key` | yes | registration | -- | `&str` |
| `init` | no | startup | `&InitCtx<'_>` (ctx.config, ctx.theme, ctx.default_text_size, ctx.default_font) | -- |
| `prepare` | no | mutable (pre-view) | `&TreeNode`, `&mut ExtensionCaches`, `&Theme` | -- |
| `render` | yes | immutable (view) | `&TreeNode`, `&WidgetEnv` | `Element<Message>` |
| `handle_event` | no | update | node_id, family, data, `&mut ExtensionCaches` | `EventResult` |
| `handle_command` | no | update | node_id, op, payload, `&mut ExtensionCaches` | `Vec<OutgoingEvent>` |
| `cleanup` | no | tree diff | node_id, `&mut ExtensionCaches` | -- |

### WidgetEnv / RenderCtx fields

`WidgetEnv` (and the underlying `RenderCtx`) provides access to:

- `env.theme` -- the current iced `Theme`
- `env.window_id` -- the window ID (`&str`) this render pass is for
- `env.scale_factor` -- DPI scale factor (`f32`) for the current window

Extensions doing DPI-aware rendering or per-window adaptation can use
`window_id` and `scale_factor` directly.

### Prelude additions

The `plushie_core::prelude` re-exports `alignment`, `Point`, and `Size`,
so you do not need to reach into `plushie_core::iced::alignment` for
alignment types. The prelude also re-exports `CoalesceHint`,
`OutgoingEvent`, `GenerationCounter`, `ExtensionCaches`, and the
`prop_*` helper functions.


## Message::Event construction

Extensions that implement custom `iced::advanced::Widget` types need to
publish events back through the extension system. Use the `Message::Event`
variant:

```rust
use plushie_core::message::Message;
use serde_json::json;

// In your Widget::update() method:
shell.publish(Message::Event(
    self.node_id.clone(),           // node ID (String)
    json!({"key": "value"}),        // event data (serde_json::Value)
    "my_event_family".to_string(),  // family string (String)
));
```

The event flows through the system like this:

```
Widget::update()
  -> shell.publish(Message::Event(id, data, family))
  -> App::update() in renderer.rs
  -> ExtensionDispatcher::handle_event(id, family, data, caches)
  -> your extension's handle_event() method
  -> EventResult determines what reaches Ruby
```

If your extension does not implement `handle_event` (or returns
`EventResult::PassThrough`), the event is serialized as-is and sent to
Ruby over the wire as an `OutgoingEvent` with the family and data you
provided.

### Constructing OutgoingEvent from extensions

When your `handle_event` or `handle_command` needs to emit events to Ruby,
use `OutgoingEvent::extension_event`:

```rust
OutgoingEvent::extension_event(
    "my_custom_family".to_string(),  // family string
    node_id.to_string(),             // node ID
    Some(json!({"detail": 42})),     // optional data payload (None for bare events)
)
```

This is equivalent to `OutgoingEvent::generic(family, id, data)`. The
resulting JSON sent to Ruby looks like:

```json
{"type": "event", "family": "my_custom_family", "id": "node-1", "data": {"detail": 42}}
```

## Event family reference

Every event sent over the wire carries a `family` string that identifies
what kind of interaction produced it. Extension authors need to know these
strings when implementing `handle_event` -- the `family` parameter tells
you what happened.

### Widget events (node ID in `id` field)

These are emitted by built-in widgets. They use dedicated `Message` variants
internally but arrive at extensions via `Message::Event` when the widget is
inside an extension's node tree.

| Family | Source widget | Data fields |
|---|---|---|
| `click` | button | -- |
| `input` | text_input, text_editor | `value`: new text |
| `submit` | text_input | `value`: current text |
| `toggle` | checkbox, toggler | `value`: bool |
| `slide` | slider, vertical_slider | `value`: f64 |
| `slide_release` | slider, vertical_slider | `value`: f64 |
| `select` | pick_list, combo_box, radio | `value`: selected string |
| `open` | pick_list, combo_box | -- |
| `close` | pick_list, combo_box | -- |
| `paste` | text_input | `value`: pasted text |
| `option_hovered` | combo_box | `value`: hovered option |
| `sort` | table | `data.column`: column key |
| `key_binding` | text_editor | `data`: binding tag and key data |
| `scroll` | scrollable | `data`: absolute/relative offsets, bounds, content size |

### Canvas events (node ID in `id` field)

| Family | Data fields |
|---|---|
| `canvas_press` | `data.x`, `data.y`, `data.button` |
| `canvas_release` | `data.x`, `data.y`, `data.button` |
| `canvas_move` | `data.x`, `data.y` |
| `canvas_scroll` | `data.x`, `data.y`, `data.delta_x`, `data.delta_y` |
| `canvas_shape_enter` | `data.shape_id`, `data.x`, `data.y` |
| `canvas_shape_leave` | `data.shape_id` |
| `canvas_shape_click` | `data.shape_id`, `data.x`, `data.y`, `data.button` |
| `canvas_shape_drag` | `data.shape_id`, `data.x`, `data.y`, `data.delta_x`, `data.delta_y` |
| `canvas_shape_drag_end` | `data.shape_id`, `data.x`, `data.y` |
| `canvas_shape_focused` | `data.shape_id` |

### MouseArea events (node ID in `id` field)

| Family | Data fields |
|---|---|
| `mouse_right_press` | -- |
| `mouse_right_release` | -- |
| `mouse_middle_press` | -- |
| `mouse_middle_release` | -- |
| `mouse_double_click` | -- |
| `mouse_enter` | -- |
| `mouse_exit` | -- |
| `mouse_move` | `data.x`, `data.y` |
| `mouse_scroll` | `data.delta_x`, `data.delta_y` |

### Sensor events (node ID in `id` field)

| Family | Data fields |
|---|---|
| `sensor_resize` | `data.width`, `data.height` |

### PaneGrid events (grid ID in `id` field)

| Family | Data fields |
|---|---|
| `pane_resized` | `data.split`, `data.ratio` |
| `pane_dragged` | `data.pane`, `data.target` |
| `pane_clicked` | `data.pane` |

### Subscription events (subscription tag in `tag` field, empty `id`)

These are only routed through extensions if the extension widget's node ID
matches. In practice, extensions mostly see the widget-scoped events above.
Listed here for completeness.

| Family | Data fields |
|---|---|
| `key_press` | `modifiers`, `data.key`, `data.modified_key`, `data.physical_key`, `data.location`, `data.text`, `data.repeat` |
| `key_release` | `modifiers`, `data.key`, `data.modified_key`, `data.physical_key`, `data.location` |
| `modifiers_changed` | `data.shift`, `data.ctrl`, `data.alt`, `data.logo`, `data.command` |
| `cursor_moved` | `data.x`, `data.y` |
| `cursor_entered` | -- |
| `cursor_left` | -- |
| `button_pressed` | `data.button` |
| `button_released` | `data.button` |
| `wheel_scrolled` | `data.delta_x`, `data.delta_y`, `data.unit` |
| `finger_pressed` | `data.id`, `data.x`, `data.y` |
| `finger_moved` | `data.id`, `data.x`, `data.y` |
| `finger_lifted` | `data.id`, `data.x`, `data.y` |
| `finger_lost` | `data.id`, `data.x`, `data.y` |
| `ime_opened` | -- |
| `ime_preedit` | `data.text`, `data.cursor` |
| `ime_commit` | `data.text` |
| `ime_closed` | -- |
| `animation_frame` | `data.timestamp_millis` |
| `theme_changed` | `data.mode` |

### Window events (subscription tag in `tag` field)

| Family | Data fields |
|---|---|
| `window_opened` | `data.window_id`, `data.position` |
| `window_closed` | `data.window_id` |
| `window_close_requested` | `data.window_id` |
| `window_moved` | `data.window_id`, `data.x`, `data.y` |
| `window_resized` | `data.window_id`, `data.width`, `data.height` |
| `window_focused` | `data.window_id` |
| `window_unfocused` | `data.window_id` |
| `window_rescaled` | `data.window_id`, `data.scale_factor` |
| `file_hovered` | `data.window_id`, `data.path` |
| `file_dropped` | `data.window_id`, `data.path` |
| `files_hovered_left` | `data.window_id` |

## EventResult guide

`handle_event` returns one of three variants:

### PassThrough

"I don't care about this event. Forward it to Ruby as-is." This is the
default.

### Consumed(events)

"I handled this event. Do NOT forward the original. Optionally emit
different events instead."

```rust
// Handle internally, emit nothing
EventResult::Consumed(vec![])

// Transform: swallow raw event, emit semantic one
EventResult::Consumed(vec![
    OutgoingEvent::extension_event("plot_click", node_id, data)
])
```

### Observed(events)

"I handled this event AND forward the original. Also emit additional
events."

```rust
// Forward the original click AND emit a computed event
EventResult::Observed(vec![
    OutgoingEvent::extension_event(
        "sparkline_sample_clicked".to_string(),
        node_id.to_string(),
        Some(json!({"sample_index": 7, "value": 42.5})),
    )
])
```

The original event is sent first, then the additional events in order.


## canvas::Cache and GenerationCounter

`iced::widget::canvas::Cache` is `!Send + !Sync`. This means it cannot be
stored in `ExtensionCaches` (which requires `Send + Sync + 'static`). This
is a fundamental constraint of iced's rendering architecture, not a bug.

### The pattern

Instead of storing `canvas::Cache` in `ExtensionCaches`, use iced's built-in
tree state mechanism. The cache lives in your `Program::State` (initialized
via `Widget::state()` or `canvas::Program`), and a `GenerationCounter` in
`ExtensionCaches` tracks when your data changes.

```rust
use plushie_core::prelude::*;
use iced::widget::canvas;

/// Stored in ExtensionCaches (Send + Sync).
struct SparklineData {
    samples: Vec<f32>,
    generation: GenerationCounter,
}

/// Stored in canvas Program::State (not Send, not Sync -- iced manages it).
struct SparklineState {
    last_generation: u64,
    cache: canvas::Cache,
}
```

In `prepare` or `handle_command`, bump the generation when data changes:

```rust
fn handle_command(&mut self, node_id: &str, op: &str, payload: &Value, caches: &mut ExtensionCaches) -> Vec<OutgoingEvent> {
    if op == "push" {
        if let Some(data) = caches.get_mut::<SparklineData>(self.config_key(), node_id) {
            data.samples.push(payload.as_f64().unwrap_or(0.0) as f32);
            data.generation.bump();  // signal that a redraw is needed
        }
    }
    vec![]
}
```

In `draw`, compare generations to decide whether to clear the cache:

```rust
impl canvas::Program<Message> for SparklineProgram<'_> {
    type State = SparklineState;

    fn draw(
        &self,
        state: &Self::State,
        renderer: &iced::Renderer,
        _theme: &Theme,
        bounds: iced::Rectangle,
        _cursor: iced::mouse::Cursor,
    ) -> Vec<canvas::Geometry> {
        // Check if data has changed since last draw
        if state.last_generation != self.current_generation {
            state.cache.clear();
            // Note: state.last_generation is updated after draw via update()
        }

        let geometry = state.cache.draw(renderer, bounds.size(), |frame| {
            // Draw your content here
        });

        vec![geometry]
    }
}
```

### Why GenerationCounter instead of content hashing

`GenerationCounter` is a simple `u64` counter. Incrementing it is O(1) and
comparing two values is a single integer comparison. Content hashing is
more expensive and harder to get right (what do you hash? serialized JSON?
raw bytes?). The counter approach is the recommended pattern.

`GenerationCounter` implements `Send + Sync + Clone` and stores cleanly in
`ExtensionCaches`. Create it with `GenerationCounter::new()` (starts at 0),
call `.bump()` to increment, and `.get()` to read the current value.


## plushie-iced Widget trait guide

Extensions implementing `iced::advanced::Widget` directly (Tier C) need to
be aware of the plushie-iced API. Several methods changed names and signatures
from earlier versions.

### Key changes

**`on_event` is now `update`:**

```rust
// plushie-iced
fn update(
    &mut self,
    tree: &mut widget::Tree,
    event: iced::Event,
    layout: Layout<'_>,
    cursor: mouse::Cursor,
    renderer: &Renderer,
    clipboard: &mut dyn Clipboard,
    shell: &mut Shell<'_, Message>,
    viewport: &Rectangle,
) -> event::Status {
    // ...
}
```

**Capturing events:** Instead of returning `event::Status::Captured`, call
`shell.capture_event()` and return `event::Status::Captured`:

```rust
// In update():
shell.capture_event();
event::Status::Captured
```

**Alignment fields renamed:**

```rust
// 0.13:
// fn horizontal_alignment(&self) -> alignment::Horizontal
// fn vertical_alignment(&self) -> alignment::Vertical

// 0.14:
fn align_x(&self) -> alignment::Horizontal { ... }
fn align_y(&self) -> alignment::Vertical { ... }
```

Note: the types are different too. `align_x` returns
`alignment::Horizontal`, `align_y` returns `alignment::Vertical`.

**Widget::size() returns Size\<Length\>:**

```rust
fn size(&self) -> iced::Size<Length> {
    iced::Size::new(self.width, self.height)
}
```

**Widget::state() initializes tree state:**

```rust
fn state(&self) -> widget::tree::State {
    widget::tree::State::new(MyWidgetState::default())
}
```

Called once on first mount. The state persists in iced's widget tree and is
accessible in `update()` and `draw()` via `tree.state.downcast_ref::<MyWidgetState>()`.

**Widget::tag() for state type verification:**

```rust
fn tag(&self) -> widget::tree::Tag {
    widget::tree::Tag::of::<MyWidgetState>()
}
```

### Publishing events from custom widgets

Use `shell.publish(Message::Event(...))` as described in the Message::Event
construction section above. The `Message` type is re-exported from
`plushie_core::prelude`.

### Full Widget skeleton

```rust
use iced::advanced::widget::{self, Widget};
use iced::advanced::{layout, mouse, renderer, Clipboard, Layout, Shell};
use iced::event;
use iced::{Element, Length, Rectangle, Size, Theme};
use plushie_core::prelude::*;

struct MyWidget<'a> {
    node_id: String,
    node: &'a TreeNode,
}

struct MyWidgetState {
    // your per-instance state
}

impl Default for MyWidgetState {
    fn default() -> Self { Self { /* ... */ } }
}

impl<'a> Widget<Message, Theme, iced::Renderer> for MyWidget<'a> {
    fn tag(&self) -> widget::tree::Tag {
        widget::tree::Tag::of::<MyWidgetState>()
    }

    fn state(&self) -> widget::tree::State {
        widget::tree::State::new(MyWidgetState::default())
    }

    fn size(&self) -> Size<Length> {
        Size::new(Length::Fill, Length::Shrink)
    }

    fn layout(&self, _tree: &mut widget::Tree, _renderer: &iced::Renderer, limits: &layout::Limits) -> layout::Node {
        let size = limits.max();
        layout::Node::new(Size::new(size.width, 200.0))
    }

    fn draw(
        &self,
        tree: &widget::Tree,
        renderer: &mut iced::Renderer,
        theme: &Theme,
        style: &renderer::Style,
        layout: Layout<'_>,
        cursor: mouse::Cursor,
        viewport: &Rectangle,
    ) {
        // Draw your widget
    }

    fn update(
        &mut self,
        tree: &mut widget::Tree,
        event: iced::Event,
        layout: Layout<'_>,
        cursor: mouse::Cursor,
        renderer: &iced::Renderer,
        clipboard: &mut dyn Clipboard,
        shell: &mut Shell<'_, Message>,
        viewport: &Rectangle,
    ) -> event::Status {
        if let iced::Event::Mouse(mouse::Event::ButtonPressed(mouse::Button::Left)) = &event {
            if cursor.is_over(layout.bounds()) {
                shell.publish(Message::Event(
                    self.node_id.clone(),
                    serde_json::json!({"x": 0, "y": 0}),
                    "my_widget_click".to_string(),
                ));
                shell.capture_event();
                return event::Status::Captured;
            }
        }
        event::Status::Ignored
    }
}

impl<'a> From<MyWidget<'a>> for Element<'a, Message> {
    fn from(w: MyWidget<'a>) -> Self {
        Self::new(w)
    }
}
```


## Prop helpers reference

The `plushie_core::prop_helpers` module (re-exported via `prelude::*`) provides
typed accessors for reading props from `TreeNode`. Use these instead of
manually traversing `serde_json::Value`:

| Helper | Return type | Notes |
|---|---|---|
| `prop_str(node, key)` | `Option<String>` | |
| `prop_f32(node, key)` | `Option<f32>` | Accepts numbers and numeric strings |
| `prop_f64(node, key)` | `Option<f64>` | Accepts numbers and numeric strings |
| `prop_u32(node, key)` | `Option<u32>` | Rejects negative values |
| `prop_u64(node, key)` | `Option<u64>` | Rejects negative values |
| `prop_usize(node, key)` | `Option<usize>` | Via `prop_u64` |
| `prop_i64(node, key)` | `Option<i64>` | Signed integers |
| `prop_bool(node, key)` | `Option<bool>` | |
| `prop_bool_default(node, key, default)` | `bool` | Returns default when absent |
| `prop_length(node, key, fallback)` | `Length` | Parses "fill", "shrink", numbers, `{fill_portion: n}` |
| `prop_range_f32(node)` | `RangeInclusive<f32>` | Reads `range` prop as `[min, max]`, defaults to `0.0..=100.0` |
| `prop_range_f64(node)` | `RangeInclusive<f64>` | Same as above, f64 |
| `prop_color(node, key)` | `Option<iced::Color>` | Parses `#RRGGBB` / `#RRGGBBAA` hex strings |
| `prop_f32_array(node, key)` | `Option<Vec<f32>>` | Array of numbers |
| `prop_horizontal_alignment(node, key)` | `alignment::Horizontal` | "left"/"center"/"right", defaults Left |
| `prop_vertical_alignment(node, key)` | `alignment::Vertical` | "top"/"center"/"bottom", defaults Top |
| `prop_content_fit(node)` | `Option<ContentFit>` | Reads `content_fit` prop |
| `node.prop_str(key)` | `Option<String>` | Method on `TreeNode` (same as `prop_str`) |
| `node.prop_f32(key)` | `Option<f32>` | Method on `TreeNode` (same as `prop_f32`) |
| `node.prop_bool(key)` | `Option<bool>` | Method on `TreeNode` (same as `prop_bool`) |
| `node.prop_color(key)` | `Option<Color>` | Method on `TreeNode` (same as `prop_color`) |
| `node.prop_padding(key)` | `Padding` | Method on `TreeNode` (same as `prop_padding`) |
| `node.props()` | `Option<&Map>` | Access the props object directly |
| `OutgoingEvent::with_value(value)` | `OutgoingEvent` | Set the `value` field on extension events |
| `PlushieAppBuilder::extension_boxed(ext)` | `PlushieAppBuilder` | Register pre-boxed extensions |
| `f64_to_f32(v)` | `f32` | Clamping f64-to-f32 conversion |
| `prop_padding(node, key)` | `Padding` | Public padding prop helper |


## ExtensionCaches

`ExtensionCaches` is type-erased storage keyed by `(namespace, key)` pairs.
The namespace is typically your extension's `config_key()`, and the key is
the node ID. This is the primary mechanism for persisting state between
`prepare`/`render`/`handle_event`/`handle_command` calls.

Key methods:

| Method | Signature | Notes |
|---|---|---|
| `get::<T>(ns, key)` | `-> Option<&T>` | Immutable access |
| `get_mut::<T>(ns, key)` | `-> Option<&mut T>` | Mutable access |
| `get_or_insert::<T>(ns, key, default_fn)` | `-> &mut T` | Initialize if absent. Replaces on type mismatch. |
| `insert::<T>(ns, key, value)` | `-> ()` | Overwrites existing |
| `remove(ns, key)` | `-> bool` | Returns whether key existed |
| `contains(ns, key)` | `-> bool` | |
| `remove_namespace(ns)` | `-> ()` | Remove all entries for a namespace |

Common keying patterns:

- **Per-node state:** `caches.get::<MyState>(self.config_key(), &node.id)`
- **Per-node sub-keys:** `caches.get::<GenerationCounter>(self.config_key(), &format!("{}:gen", node.id))`
- **Global extension state:** `caches.get::<GlobalConfig>(self.config_key(), "_global")`

The type parameter `T` must be `Send + Sync + 'static`. This is why
`canvas::Cache` (which is `!Send + !Sync`) cannot be stored here.


## Panic isolation

The `ExtensionDispatcher` wraps all mutable extension calls (`init`,
`prepare`, `handle_event`, `handle_command`, `cleanup`) in
`catch_unwind`. If your extension panics:

1. The panic is logged via `log::error!`.
2. The extension is marked as "poisoned".
3. All subsequent calls to the poisoned extension are skipped.
4. `render()` returns a red error placeholder text instead of calling your code.
5. Poisoned state is cleared on the next `Snapshot` message (full tree sync).

This means a bug in one extension cannot crash the renderer or affect other
extensions. But it also means panics are unrecoverable until the next
snapshot -- design your extension to avoid panics in production.

**Note:** `render()` panics ARE caught via `catch_unwind` in
`widgets::render()`. When a render panic is caught, the extension is
marked as "poisoned" and subsequent renders skip it, returning a red
error placeholder text until `clear_poisoned()` is called (typically on
the next `Snapshot` message).

Set `PLUSHIE_NO_CATCH_UNWIND=1` to disable panic isolation during
development. This lets panics propagate normally, giving you a full
backtrace instead of a red placeholder. Useful when debugging Rust-side
extension code. Do not use this in production.

## Testing extensions

### Ruby-side tests

```ruby
class MySparklineTest < Minitest::Test
  def test_type_names
    assert_equal [:sparkline], MySparkline.type_names
  end

  def test_new_creates_widget
    widget = MySparkline.new("spark-1", color: "#ff0000")
    assert_equal "spark-1", widget.id
    assert_equal "#ff0000", widget.color
  end
end
```

### Rust-side tests

```rust
#[cfg(test)]
mod tests {
    use plushie_core::testing::*;
    use super::*;

    #[test]
    fn handle_command_push_adds_sample() {
        let mut ext = SparklineExtension::new();
        let mut caches = ext_caches();
        let n = node_with_props("s-1", "sparkline", json!({"capacity": 10}));
        ext.prepare(&n, &mut caches, &iced::Theme::Dark);
        ext.handle_command("s-1", "push", &json!(42.0), &mut caches);

        let state = caches.get::<SparklineState>("sparkline", "s-1").unwrap();
        assert_eq!(state.samples.len(), 1);
    }
}
```

### End-to-end

```sh
bundle exec rake plushie:build
PLUSHIE_TEST_BACKEND=headless bundle exec rake test
```

## Publishing widget packages

Widget packages come in two tiers:

1. **Pure Ruby** -- compose existing primitives (canvas, column, container,
   etc.) into higher-level widgets. Works with prebuilt renderer binaries.
   No Rust toolchain needed.
2. **Ruby + Rust** -- custom native rendering via a `WidgetExtension`
   trait. Requires a Rust toolchain to compile a custom renderer binary.

The rest of this section covers Tier 1 (pure Ruby packages). For Tier 2,
see the extension quick start and trait reference above.

### When pure Ruby is enough

Canvas + Shape builders cover custom 2D rendering: charts, diagrams,
gauges, sparklines, colour pickers, drawing tools. The overlay widget
enables dropdowns, popovers, and context menus. Style maps provide
per-instance visual customization. Composition of layout primitives
(column, row, container, stack) covers cards, tab bars, sidebars, toolbars,
and other structural patterns.

See [composition-patterns.md](composition-patterns.md) for examples.

Pure Ruby falls short when you need: custom text layout engines, GPU
shaders, platform-native controls (e.g. a native file tree), or
performance-critical rendering that canvas cannot handle efficiently.

### Package structure

A plushie widget package is a standard gem:

```
my_widget/
  lib/
    my_widget.rb              # public API (convenience constructors)
    my_widget/
      donut_chart.rb          # widget struct + Node building
  test/
    my_widget/
      donut_chart_test.rb     # struct, builder, and node tests
  my_widget.gemspec
```

#### my_widget.gemspec

```ruby
Gem::Specification.new do |spec|
  spec.name = "my_widget"
  spec.version = "0.1.0"
  spec.summary = "Donut chart widget for Plushie"
  spec.authors = ["Your Name"]
  spec.files = Dir["lib/**/*.rb"]

  spec.add_dependency "plushie", "~> 0.1"
end
```

Plushie is a runtime dependency. Your package does not need the renderer
binary -- it only uses plushie's Ruby modules (`Plushie::Node`,
`Plushie::Canvas::Shape`, type modules).

### Building a widget

Build `Plushie::Node` trees from your struct. The node types must be
types the stock renderer understands. The renderer handles them without
modification.

#### Example: DonutChart

A ring chart rendered via canvas:

```ruby
# lib/my_widget/donut_chart.rb
class MyWidget::DonutChart
  attr_reader :id, :segments, :size, :thickness, :background

  # @param id [String] widget ID
  # @param segments [Array<Array(String, Numeric, String)>] [label, value, color] tuples
  # @param size [Numeric] canvas size in pixels
  # @param thickness [Numeric] ring thickness
  # @param background [String, nil] background color
  def initialize(id, segments, size: 200, thickness: 40, background: nil)
    @id = id
    @segments = segments
    @size = size
    @thickness = thickness
    @background = background
  end

  def build
    layers = {arcs: build_arc_shapes}

    props = {layers: layers, width: @size, height: @size}
    props[:background] = @background if @background

    Plushie::Node.new(id: @id, type: "canvas", props: props, children: [])
  end

  private

  def build_arc_shapes
    total = @segments.sum { |_, v, _| v }
    return [] if total == 0

    r = @size / 2.0
    inner_r = r - @thickness
    shapes = []
    start_angle = -Math::PI / 2

    @segments.each do |_label, value, color|
      sweep = value / total * 2 * Math::PI
      stop_angle = start_angle + sweep

      shapes << {
        type: "path",
        commands: [
          {type: "arc", cx: r, cy: r, r: r, start: start_angle, end: stop_angle},
          {type: "line_to", x: r + inner_r * Math.cos(stop_angle), y: r + inner_r * Math.sin(stop_angle)},
          {type: "arc", cx: r, cy: r, r: inner_r, start: stop_angle, end: start_angle},
          {type: "close"}
        ],
        fill: color
      }
      start_angle = stop_angle
    end

    shapes
  end
end
```

Key points:

- The struct follows a simple builder pattern with keyword arguments.
- `build` emits a `"canvas"` node with `"layers"` -- a type the stock
  renderer already handles.
- No Rust code. No custom node types. The renderer sees a canvas widget.

#### Convenience constructors

For consumer ergonomics, add a top-level module with functions that mirror
the `Plushie::UI` calling conventions:

```ruby
# lib/my_widget.rb
require_relative "my_widget/donut_chart"

module MyWidget
  # Creates a donut chart node.
  #
  # @param id [String]
  # @param segments [Array] [label, value, color] tuples
  # @param opts [Hash] size:, thickness:, background:
  # @return [Plushie::Node]
  def self.donut_chart(id, segments, **opts)
    DonutChart.new(id, segments, **opts).build
  end
end
```

Consumers use it like any other widget:

```ruby
include Plushie::UI

column do
  text("title", "Revenue breakdown")
  # returns a Plushie::Node -- composes naturally with the DSL
  MyWidget.donut_chart("revenue", model.segments, size: 300)
end
```

### Testing widget packages

#### Unit tests (no renderer needed)

Test the struct, builders, and `build` output directly:

```ruby
class MyWidget::DonutChartTest < Minitest::Test
  def test_new_creates_struct_with_defaults
    chart = MyWidget::DonutChart.new("c1", [["A", 50, "#ff0000"]])
    assert_equal "c1", chart.id
    assert_equal 200, chart.size
    assert_equal 40, chart.thickness
  end

  def test_build_produces_a_canvas_node
    node = MyWidget::DonutChart.new("c1", [["A", 50, "#ff0000"]]).build
    assert_equal "canvas", node.type
    assert_equal "c1", node.id
    assert node.props[:layers].is_a?(Hash)
  end
end
```

#### Integration tests with mock backend

For testing widget behaviour in a running app, use plushie's mock
backend:

```ruby
class MyWidget::IntegrationTest < Plushie::Test::Case
  class ChartApp
    include Plushie::App

    Model = Plushie::Model.define(:segments)

    def init(_opts)
      Model.new(segments: [["A", 50, "#ff0000"], ["B", 50, "#0000ff"]])
    end

    def update(model, _event) = model

    def view(model)
      window("main") do
        MyWidget.donut_chart("chart", model.segments, size: 200)
      end
    end
  end

  def test_chart_renders_in_the_tree
    session = start!(ChartApp)
    element = find!(session, "#chart")
    assert_equal "canvas", element.type
  end
end
```

### What consumers need to know

Document these in your package README:

1. **Minimum plushie version.** Your package depends on plushie; specify the
   compatible range.
2. **No renderer changes needed.** Pure Ruby packages work with the stock
   plushie binary. Consumers do not need to rebuild anything.
3. **Which built-in features are required.** If your widget uses canvas,
   consumers need the feature enabled (it is by default). Document this if
   it matters.

### Limitations of pure Ruby packages

- **No custom node types.** Your `build` must emit node types the stock
  renderer understands (`canvas`, `column`, `container`, etc.).
- **Canvas performance ceiling.** Complex canvas scenes (thousands of shapes,
  60fps animation) may hit limits.
- **No access to iced internals.** You cannot customize widget state
  continuity, keyboard focus, accessibility, or rendering internals.
- **Overlay requires the overlay node type.** If your widget needs popover
  behaviour, it depends on the `overlay` node type being available.


## Configuration

Register extensions and pass runtime configuration using `Plushie.configure`:

```ruby
Plushie.configure do |config|
  config.extensions = [MyGauge, MyChart]
  config.extension_config = {
    "sparkline" => {"max_samples" => 1000},
    "terminal" => {"shell" => "/bin/bash"}
  }
end
```

| Option | Type | Description |
|---|---|---|
| `extensions` | `Array<Class>` | Extension classes to include in custom builds |
| `extension_config` | `Hash` | Runtime config passed to extensions via the Settings wire message, keyed by `config_key` |

The `extension_config` hash is sent to the renderer on startup. Each
extension receives its own section via the `InitCtx` passed to the `init`
trait method. Use this for runtime tuning (buffer sizes, feature flags,
backend URLs) that should not be baked into the binary.

For CI or one-off builds, you can also set `PLUSHIE_EXTENSIONS` as a
comma-separated list of class names:

```sh
PLUSHIE_EXTENSIONS="MyGauge,MyChart" bundle exec rake plushie:build
```


## Build pipeline

`rake plushie:build` handles both stock and custom builds.

### Stock build (no extensions)

When no extensions are configured, the task builds the plushie binary
from the Rust source checkout specified by `PLUSHIE_SOURCE_PATH`. This
is a plain `cargo build -p plushie`.

### Custom build (with extensions)

When extensions are present (via `Plushie.configure` or
`PLUSHIE_EXTENSIONS`), the build pipeline:

1. **Resolves extensions.** Calls `configured_extensions` which reads
   from the configure block first, then falls back to the env var.
   Each class is validated to be a `native_widget`.

2. **Checks for type name collisions.** If two extensions claim the
   same type name (e.g. both register `"sparkline"`), the build
   fails with a clear error listing the conflicting classes.

3. **Checks for crate name collisions.** If two extensions have crate
   directories with the same basename (e.g. both use
   `native/my_widget`), the build fails.

4. **Validates crate paths.** Each extension's `rust_crate` path is
   resolved relative to the project root. If the resolved path
   escapes the project directory (path traversal), the build fails.
   This prevents extensions from referencing arbitrary filesystem
   locations in the generated Cargo workspace.

5. **Validates Rust constructors.** Each extension's
   `rust_constructor` expression is checked against a safe pattern
   (`identifier::path::function()`). Arbitrary code injection is
   rejected.

6. **Generates Cargo workspace.** Creates `_build/plushie/custom/`
   with:
   - `Cargo.toml` -- declares dependencies on `plushie`,
     `plushie-core`, and each extension crate
   - `src/main.rs` -- registers each extension via
     `PlushieAppBuilder::new().extension(...)` calls

7. **Runs `cargo build`.** Compiles the workspace. Pass
   `rake plushie:build[release]` for an optimized build.

8. **Installs the binary.** Copies the compiled binary to
   `_build/plushie/bin/` where the SDK's binary resolver finds it.

The generated `main.rs` looks like:

```rust
// Auto-generated by rake plushie:build
// Do not edit manually.

use plushie_core::app::PlushieAppBuilder;

fn main() -> iced::Result {
    let builder = PlushieAppBuilder::new()
        .extension(my_sparkline::SparklineExtension::new())
        .extension(my_gauge::GaugeExtension::new());
    plushie::run(builder)
}
```
