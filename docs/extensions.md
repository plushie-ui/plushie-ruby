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

### Supported prop types

`:number`, `:string`, `:boolean`, `:color`, `:length`, `:padding`,
`:alignment`, `:font`, `:style`, `:atom`, `:map`, `:any`, `[:list, inner]`

The `a11y` and `event_rate` options are available on all extension
widgets automatically.

## Extension tiers

### Tier A: render-only

Implement `type_names`, `config_key`, and `render`. Good for widgets that
compose existing iced widgets with no Rust-side interaction state.

### Tier B: interactive (+handle_event)

Add `handle_event` to intercept events from your widgets before they reach
Ruby. Use this when the extension needs to process mouse/keyboard input
internally.

#### Throttling high-frequency extension events

Mark events with a `CoalesceHint` to opt in to rate limiting:

```rust
let event = OutgoingEvent::extension_event("cursor_pos", node_id, data)
    .with_coalesce(CoalesceHint::Replace);
```

### Tier C: full lifecycle

Add `prepare` for mutable state synchronization, `handle_command` for
commands from Ruby, and `cleanup` for resource teardown.

| Method | Required | Phase |
|---|---|---|
| `type_names` | yes | registration |
| `config_key` | yes | registration |
| `init` | no | startup |
| `prepare` | no | mutable (pre-view) |
| `render` | yes | immutable (view) |
| `handle_event` | no | update |
| `handle_command` | no | update |
| `cleanup` | no | tree diff |

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
