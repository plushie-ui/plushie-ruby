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
| `init` | no | startup | `&InitCtx<'_>` | -- |
| `prepare` | no | mutable (pre-view) | `&TreeNode`, `&mut ExtensionCaches`, `&Theme` | -- |
| `render` | yes | immutable (view) | `&TreeNode`, `&WidgetEnv` | `Element<Message>` |
| `handle_event` | no | update | node_id, family, data, `&mut ExtensionCaches` | `EventResult` |
| `handle_command` | no | update | node_id, op, payload, `&mut ExtensionCaches` | `Vec<OutgoingEvent>` |
| `cleanup` | no | tree diff | node_id, `&mut ExtensionCaches` | -- |

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

Two tiers:

1. **Pure Ruby** -- compose existing primitives. Works with prebuilt
   renderer binaries. No Rust toolchain needed.
2. **Ruby + Rust** -- custom native rendering. Requires a Rust toolchain.

### When pure Ruby is enough

Canvas + Shape builders cover custom 2D rendering. Style maps provide
per-instance visual customization. Composition of layout primitives covers
structural patterns.

### Package structure

A plushie widget package is a standard gem:

```
my_widget/
  lib/
    my_widget.rb              # public API
    my_widget/
      donut_chart.rb          # widget + Node building
  test/
    my_widget/
      donut_chart_test.rb
  my_widget.gemspec
```

### Limitations of pure Ruby packages

- **No custom node types.** Your builder must emit node types the stock
  renderer understands (`canvas`, `column`, `container`, etc.).
- **Canvas performance ceiling.** Complex scenes may hit limits.
- **No access to iced internals.**
