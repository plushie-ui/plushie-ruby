# frozen_string_literal: true

require "test_helper"

# Tests for features added during the Elixir SDK parity work.
# Covers: tree safety, type validation, canvas architecture,
# tween repeat, memo caching, WidgetSet, theme validation,
# subscription wire tags, command encoding, event decoding.

class TestParityFeatures < Minitest::Test
  include Plushie::UI

  # ======================================================================
  # Tree: depth limit
  # ======================================================================

  def test_tree_depth_raises_at_256
    # Build a deeply nested tree
    node = Plushie::Node.new(id: "leaf", type: "text")
    260.times { |i| node = Plushie::Node.new(id: "d#{i}", type: "container", children: [node]) }
    root = Plushie::Node.new(id: "main", type: "window", children: [node])

    assert_raises(ArgumentError) { Plushie::Tree.normalize([root]) }
  end

  # ======================================================================
  # Tree: find_first
  # ======================================================================

  def test_tree_find_first
    tree = Plushie::Node.new(id: "root", type: "root", children: [
      Plushie::Node.new(id: "a", type: "text"),
      Plushie::Node.new(id: "b", type: "button"),
      Plushie::Node.new(id: "c", type: "button")
    ])
    found = Plushie::Tree.find_first(tree) { |n| n.type == "button" }
    assert_equal "b", found.id
  end

  def test_tree_find_first_returns_nil_when_no_match
    tree = Plushie::Node.new(id: "root", type: "root", children: [
      Plushie::Node.new(id: "a", type: "text")
    ])
    assert_nil Plushie::Tree.find_first(tree) { |n| n.type == "button" }
  end

  # ======================================================================
  # Tree: ID validation
  # ======================================================================

  def test_tree_rejects_non_ascii_id
    node = Plushie::Node.new(id: "café", type: "text")
    root = Plushie::Node.new(id: "main", type: "window", children: [node])
    assert_raises(ArgumentError) { Plushie::Tree.normalize([root]) }
  end

  def test_tree_rejects_space_in_id
    node = Plushie::Node.new(id: "my button", type: "text")
    root = Plushie::Node.new(id: "main", type: "window", children: [node])
    assert_raises(ArgumentError) { Plushie::Tree.normalize([root]) }
  end

  def test_validate_user_id_rejects_hash
    assert_raises(ArgumentError) do
      Plushie::Tree.send(:validate_user_id!, "my#id")
    end
  end

  # ======================================================================
  # Tree: radio group a11y auto-inference
  # ======================================================================

  def test_radio_group_a11y_inference
    tree = window("main") do
      column("form") do
        radio("r1", "Option A", group: "choice", value: "a")
        radio("r2", "Option B", group: "choice", value: "b")
        radio("r3", "Option C", group: "choice", value: "c")
      end
    end
    normalized = Plushie::Tree.normalize_view(tree)
    form = Plushie::Tree.find(normalized, "form")
    refute_nil form

    r1 = form.children.find { |c| c.id.end_with?("r1") }
    r2 = form.children.find { |c| c.id.end_with?("r2") }
    r3 = form.children.find { |c| c.id.end_with?("r3") }

    a11y1 = r1.props[:a11y] || r1.props["a11y"] || {}
    assert_equal 1, a11y1["position_in_set"] || a11y1[:position_in_set]
    assert_equal 3, a11y1["size_of_set"] || a11y1[:size_of_set]

    a11y3 = r3.props[:a11y] || r3.props["a11y"] || {}
    assert_equal 3, a11y3["position_in_set"] || a11y3[:position_in_set]
  end

  # ======================================================================
  # Tree: window# scoped IDs
  # ======================================================================

  def test_window_scope_prefix
    tree = window("main") do
      button("save", "Save")
    end
    normalized = Plushie::Tree.normalize_view(tree)
    btn = Plushie::Tree.find(normalized, "save")
    refute_nil btn
    assert_equal "main#save", btn.id
  end

  def test_nested_scope_uses_slash
    tree = window("main") do
      column("form") do
        button("save", "Save")
      end
    end
    normalized = Plushie::Tree.normalize_view(tree)
    btn = Plushie::Tree.find(normalized, "save")
    refute_nil btn
    assert_equal "main#form/save", btn.id
  end

  # ======================================================================
  # Tween: repeat and auto_reverse
  # ======================================================================

  def test_tween_repeat_finite
    t = Plushie::Animation::Tween
    # repeat: 3 plays 3 cycles total (original + 2 repeats)
    anim = t.new(0.0, 1.0, 100, repeat: 3)
    anim = t.start(anim, 0)

    # Cycle 1 (repeat 3 -> 2)
    val, anim = t.advance(anim, 100)
    assert_equal 1.0, val
    refute_equal :finished, anim

    # Cycle 2 (repeat 2 -> 1)
    val, anim = t.advance(anim, 200)
    assert_equal 1.0, val
    refute_equal :finished, anim

    # Cycle 3 (repeat 1, not > 1 -> finished)
    val, result = t.advance(anim, 300)
    assert_equal 1.0, val
    assert_equal :finished, result
  end

  def test_tween_looping_auto_reverses
    t = Plushie::Animation::Tween
    anim = t.looping(0.0, 1.0, 100)
    anim = t.start(anim, 0)

    # First cycle: 0 -> 1
    val, anim = t.advance(anim, 100)
    assert_equal 1.0, val
    refute_equal :finished, anim

    # Second cycle: 1 -> 0 (auto-reversed)
    val, anim = t.advance(anim, 200)
    assert_equal 0.0, val
    refute_equal :finished, anim
  end

  def test_tween_value_zero_preserved
    t = Plushie::Animation::Tween
    anim = t.new(10.0, 0.0, 100)
    anim = t.start(anim, 0)
    val, _anim = t.advance(anim, 100)
    assert_equal 0.0, val
  end

  # ======================================================================
  # Memo
  # ======================================================================

  def test_memo_caches_subtree
    call_count = 0
    # Use a method to ensure the memo block is at the same source location
    # across renders (source_location-based cache key is stable).
    render = ->(deps) {
      window("main") do
        memo(deps) do
          call_count += 1
          text("t", "hello")
        end
      end
    }

    # First render: block is called
    Thread.current[:_plushie_canvas_counter] = 0
    Plushie::UI::MemoCache.seed({})
    _n1 = Plushie::Tree.normalize_view(render.call(:v1))
    cache = Plushie::UI::MemoCache.capture
    assert_equal 1, call_count

    # Second render with same deps: block is NOT called (cache hit)
    Thread.current[:_plushie_canvas_counter] = 0
    Plushie::UI::MemoCache.seed(cache)
    _n2 = Plushie::Tree.normalize_view(render.call(:v1))
    cache = Plushie::UI::MemoCache.capture
    assert_equal 1, call_count  # NOT incremented

    # Third render with changed deps: block IS called (cache miss)
    Thread.current[:_plushie_canvas_counter] = 0
    Plushie::UI::MemoCache.seed(cache)
    _n3 = Plushie::Tree.normalize_view(render.call(:v2))
    Plushie::UI::MemoCache.capture
    assert_equal 2, call_count  # incremented
  end

  # ======================================================================
  # WidgetSet
  # ======================================================================

  class FakeButton < Plushie::Widget::BuiltIn
    wire_type :button
    children :none
    positional :label, default: nil
    prop :label, :style, :a11y
  end

  def test_widget_set_overrides_method
    my_ui = Plushie::WidgetSet.create(button: FakeButton)
    obj = Object.new
    obj.extend(my_ui)
    # The overridden button should produce a node
    node = obj.send(:button, "test", "Click me")
    assert_equal "button", node.type
    assert_equal "test", node.id
  end

  def test_widget_set_rejects_invalid_override
    assert_raises(ArgumentError) do
      Plushie::WidgetSet.create(nonexistent_widget: FakeButton)
    end
  end

  # ======================================================================
  # Theme.custom validation
  # ======================================================================

  def test_theme_custom_valid_keys
    theme = Plushie::Type::Theme.custom("My Theme", base: :dark, primary: "#3b82f6")
    assert_equal "My Theme", theme[:name]
    assert_equal "dark", theme[:base]
  end

  def test_theme_custom_rejects_unknown_keys
    assert_raises(ArgumentError) do
      Plushie::Type::Theme.custom("Bad", primry: "#fff")  # typo
    end
  end

  # ======================================================================
  # A11y mnemonic validation
  # ======================================================================

  def test_mnemonic_single_char_ok
    spec = Plushie::Type::A11y.from_opts(mnemonic: "S")
    assert_equal "S", spec.mnemonic
  end

  def test_mnemonic_multi_char_rejected
    assert_raises(ArgumentError) do
      Plushie::Type::A11y.from_opts(mnemonic: "Ctrl+S")
    end
  end

  def test_mnemonic_validated_in_cast
    assert_raises(ArgumentError) do
      Plushie::Type::A11y.cast({mnemonic: "AB"})
    end
  end

  # ======================================================================
  # Font encoding (snake_case)
  # ======================================================================

  def test_font_encode_snake_case
    spec = Plushie::Type::Font.from_opts(weight: :extra_bold)
    result = Plushie::Type::Font.encode(spec)
    assert_equal "extra_bold", result[:weight]
  end

  # ======================================================================
  # Gradient coordinate format
  # ======================================================================

  def test_gradient_linear_coordinate_format
    g = Plushie::Type::Gradient.linear([0, 0], [100, 100], [[0.0, :red], [1.0, :blue]])
    assert_equal "linear", g[:type]
    assert_equal [0, 0], g[:start]
    assert_equal [100, 100], g[:end]
    assert_equal 2, g[:stops].length
  end

  def test_gradient_linear_from_angle
    g = Plushie::Type::Gradient.linear_from_angle(90, [[0.0, "#000"], [1.0, "#fff"]])
    assert_equal "linear", g[:type]
    assert_equal 2, g[:stops].length
  end

  # ======================================================================
  # Subscription wire tags
  # ======================================================================

  def test_renderer_sub_global_wire_tag
    sub = Plushie::Subscription.on_key_press
    assert_equal "on_key_press", sub.wire_tag
  end

  def test_renderer_sub_window_scoped_wire_tag
    sub = Plushie::Subscription.on_key_press(window: "main")
    assert_equal "on_key_press:main", sub.wire_tag
  end

  def test_renderer_sub_key_is_type_and_window
    sub = Plushie::Subscription.on_pointer_move(window: "editor")
    assert_equal [:on_pointer_move, "editor"], sub.key
  end

  # ======================================================================
  # Command wire format
  # ======================================================================

  def test_command_focus_uses_unified_format
    cmd = Plushie::Command.focus("email")
    assert_equal :command, cmd.type
    assert_equal "email", cmd.payload[:id]
    assert_equal "focus", cmd.payload[:family]
  end

  def test_command_scroll_to_takes_x_y
    cmd = Plushie::Command.scroll_to("list", 10, 200)
    assert_equal({x: 10, y: 200}, cmd.payload[:value])
  end

  def test_command_widget_command_structure
    cmd = Plushie::Command.widget_command("chart", "append", {values: [1, 2]})
    assert_equal :command, cmd.type
    assert_equal "chart", cmd.payload[:id]
    assert_equal "append", cmd.payload[:family]
  end

  def test_encode_command_wire_format
    encoded = Plushie::Protocol::Encode.encode_command("wgt", "reset", nil, :json)
    msg = JSON.parse(encoded)
    assert_equal "command", msg["type"]
    assert_equal "wgt", msg["id"]
    assert_equal "reset", msg["family"]
  end

  # ======================================================================
  # Event value unification
  # ======================================================================

  def test_event_widget_has_no_data_field
    event = Plushie::Event::Widget.new(type: :click, id: "btn")
    refute event.respond_to?(:data)
  end

  def test_event_system_uses_value_not_data
    event = Plushie::Event::System.new(type: :theme_changed, value: "dark")
    assert_equal "dark", event.value
    refute event.respond_to?(:data)
  end

  # ======================================================================
  # Pixel buffer validation
  # ======================================================================

  def test_create_image_pixel_buffer_validation
    assert_raises(ArgumentError) do
      Plushie::Command.create_image("img", pixels: "\x00" * 10, width: 2, height: 2)
    end
  end

  def test_create_image_valid_pixel_buffer
    pixels = "\x00" * 16  # 2x2x4 = 16
    cmd = Plushie::Command.create_image("img", pixels: pixels, width: 2, height: 2)
    assert_equal :image_op, cmd.type
  end

  # ======================================================================
  # Canvas children architecture
  # ======================================================================

  def test_canvas_layer_as_children
    node = canvas("c", width: 100, height: 100) do
      layer("bg") { canvas_rect(0, 0, 100, 100) }
    end
    assert_equal 1, node.children.length
    assert_equal "__layer__", node.children[0].type
    assert_equal "rect", node.children[0].children[0].type
  end

  def test_canvas_shapes_as_children
    node = canvas("c", width: 100, height: 100) do
      canvas_rect(0, 0, 50, 50)
      canvas_circle(25, 25, 10)
    end
    assert_equal 2, node.children.length
    assert_equal "rect", node.children[0].type
    assert_equal "circle", node.children[1].type
  end

  def test_canvas_interactive_requires_id
    assert_raises(ArgumentError) do
      canvas("c") { canvas_interactive(nil) { canvas_rect(0, 0, 10, 10) } }
    end
  end

  def test_canvas_interactive_produces_group_node
    node = canvas("c") do
      layer("l") do
        canvas_interactive("btn", on_click: true) do
          canvas_rect(0, 0, 50, 30)
        end
      end
    end
    interactive = node.children[0].children[0]
    assert_equal "group", interactive.type
    assert_equal "btn", interactive.id
    assert_equal true, interactive.props[:on_click]
  end

  def test_canvas_shape_ids_stable_across_renders
    Thread.current[:_plushie_canvas_counter] = 0
    n1 = canvas("c") { canvas_rect(0, 0, 10, 10) }

    Thread.current[:_plushie_canvas_counter] = 0
    n2 = canvas("c") { canvas_rect(0, 0, 10, 10) }

    assert_equal n1.children[0].id, n2.children[0].id
  end

  # ======================================================================
  # Canvas a11y defaults
  # ======================================================================

  def test_canvas_interactive_a11y_default_button
    group = Plushie::Canvas::Shape.interactive(
      Plushie::Canvas::Shape.rect(0, 0, 50, 30),
      "btn",
      on_click: true
    )
    wire = group.to_wire
    assert_equal "button", wire[:a11y][:role]
  end

  def test_canvas_interactive_a11y_explicit_overrides_default
    group = Plushie::Canvas::Shape.interactive(
      Plushie::Canvas::Shape.rect(0, 0, 50, 30),
      "btn",
      on_click: true,
      a11y: {role: "link", label: "Click here"}
    )
    wire = group.to_wire
    assert_equal "link", wire[:a11y][:role]
    assert_equal "Click here", wire[:a11y][:label]
  end

  # ======================================================================
  # Decoder: widget-scoped key events include all fields
  # ======================================================================

  def test_decode_widget_key_press_has_all_fields
    event = Plushie::Protocol::Decode.decode_event({
      "family" => "key_press",
      "id" => "editor",
      "window_id" => "main",
      "value" => {
        "key" => "a",
        "modified_key" => "a",
        "physical_key" => "KeyA",
        "location" => "standard",
        "modifiers" => {},
        "text" => "a",
        "repeat" => false
      }
    })
    assert_instance_of Plushie::Event::Widget, event
    assert_equal :key_press, event.type
    v = event.value
    assert_equal "a", v[:key]
    assert_equal "a", v[:modified_key]
    assert_equal :key_a, v[:physical_key]
    assert_equal :standard, v[:location]
    assert_equal "a", v[:text]
    assert_equal false, v[:repeat]
  end

  # ======================================================================
  # Decoder: enter/exit have coordinates
  # ======================================================================

  def test_decode_enter_has_coordinates
    event = Plushie::Protocol::Decode.decode_event({
      "family" => "enter",
      "id" => "canvas",
      "window_id" => "main",
      "value" => {"x" => 50.0, "y" => 25.0}
    })
    assert_equal :enter, event.type
    assert_equal 50.0, event.value[:x]
    assert_equal 25.0, event.value[:y]
  end

  # ======================================================================
  # Decoder: CommandError (renamed from WidgetCommandError)
  # ======================================================================

  def test_decode_command_error
    event = Plushie::Protocol::Decode.decode_event({
      "family" => "error",
      "id" => "command",
      "value" => {
        "kind" => "command",
        "reason" => "unknown_node",
        "id" => "gauge",
        "family" => "set_value",
        "message" => "no widget handles node"
      }
    })
    assert_instance_of Plushie::Event::CommandError, event
    assert_equal "gauge", event.id
    assert_equal "set_value", event.family
    assert_equal "unknown_node", event.reason
  end

  # ======================================================================
  # Hello decoder: new fields
  # ======================================================================

  def test_decode_hello_has_all_fields
    msg = {
      "type" => "hello", "protocol" => 1, "version" => "0.6.1",
      "name" => "plushie-renderer", "mode" => "mock", "backend" => "mock",
      "transport" => "stdio", "native_widgets" => ["chart"],
      "widgets" => ["button", "text", "chart"],
      "widget_sets" => ["iced"]
    }
    result = Plushie::Protocol::Decode.decode_hello(msg)
    assert_equal ["chart"], result[:native_widgets]
    assert_equal ["button", "text", "chart"], result[:widgets]
    assert_equal ["iced"], result[:widget_sets]
    assert_equal "mock", result[:mode]
  end

  # ======================================================================
  # Decoder: status event
  # ======================================================================

  def test_decode_status_event
    event = Plushie::Protocol::Decode.decode_event({
      "family" => "status",
      "id" => "email",
      "window_id" => "main",
      "value" => "focused"
    })
    assert_equal :status, event.type
    assert_equal "focused", event.value
  end
end
