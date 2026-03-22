# frozen_string_literal: true

require "test_helper"

class TestUIComplete < Minitest::Test
  include Plushie::UI

  # -- Existing widget DSL methods (should still work) -------------------------

  def test_window
    node = window("main", title: "App") { text("t", "hi") }
    assert_equal "window", node.type
    assert_equal 1, node.children.length
  end

  def test_column
    node = column("c", spacing: 8) { text("t", "hi") }
    assert_equal "column", node.type
  end

  def test_row
    node = row("r", spacing: 4) { button("b", "OK") }
    assert_equal "row", node.type
  end

  def test_container
    node = container("box", padding: 16) { text("t", "hi") }
    assert_equal "container", node.type
  end

  def test_stack
    node = stack { text("t", "hi") }
    assert_equal "stack", node.type
  end

  def test_scrollable
    node = scrollable("s") { text("t", "hi") }
    assert_equal "scrollable", node.type
  end

  def test_responsive
    node = responsive("r") { text("t", "hi") }
    assert_equal "responsive", node.type
  end

  def test_text
    node = text("msg", "Hello")
    assert_equal "text", node.type
    assert_equal "Hello", node.props[:content]
  end

  def test_button
    node = button("b", "Click")
    assert_equal "button", node.type
    assert_equal "Click", node.props[:label]
  end

  def test_text_input
    node = text_input("ti", "val")
    assert_equal "text_input", node.type
  end

  def test_text_editor
    node = text_editor("te", "content")
    assert_equal "text_editor", node.type
  end

  def test_checkbox
    node = checkbox("cb", true)
    assert_equal "checkbox", node.type
    assert_equal true, node.props[:checked]
  end

  def test_toggler
    node = toggler("tg", true)
    assert_equal "toggler", node.type
    assert_equal true, node.props[:active]
  end

  def test_slider
    node = slider("s", [0, 100], 50)
    assert_equal "slider", node.type
    assert_equal 50, node.props[:value]
  end

  def test_vertical_slider
    node = vertical_slider("vs", [0, 100], 25)
    assert_equal "vertical_slider", node.type
  end

  def test_pick_list
    node = pick_list("pl", %w[a b c], "a")
    assert_equal "pick_list", node.type
  end

  def test_combo_box
    node = combo_box("cb", %w[a b], "a")
    assert_equal "combo_box", node.type
  end

  def test_radio
    node = radio("r", %w[a b], "a")
    assert_equal "radio", node.type
  end

  def test_progress_bar
    node = progress_bar("pb", [0, 100], 42)
    assert_equal "progress_bar", node.type
  end

  def test_image
    node = image("img", "cat.png")
    assert_equal "image", node.type
    assert_equal "cat.png", node.props[:source]
  end

  def test_svg
    node = svg("icon", "<svg/>")
    assert_equal "svg", node.type
  end

  def test_markdown
    node = markdown("md", "# Title")
    assert_equal "markdown", node.type
  end

  def test_space
    node = space
    assert_equal "space", node.type
  end

  def test_rule
    node = rule
    assert_equal "rule", node.type
  end

  def test_qr_code
    node = qr_code("qr", "https://example.com")
    assert_equal "qr_code", node.type
  end

  def test_tooltip
    node = tooltip("tip", "Help text") { button("b", "?") }
    assert_equal "tooltip", node.type
    assert_equal 1, node.children.length
  end

  # -- New container DSL methods -----------------------------------------------

  def test_grid
    node = grid { text("t", "hi") }
    assert_equal "grid", node.type
  end

  def test_keyed_column
    node = keyed_column { text("t", "hi") }
    assert_equal "keyed_column", node.type
  end

  def test_pin
    node = pin { text("t", "hi") }
    assert_equal "pin", node.type
  end

  def test_floating
    node = floating { text("t", "hi") }
    assert_equal "floating", node.type
  end

  def test_mouse_area
    node = mouse_area("ma") { button("b", "Click") }
    assert_equal "mouse_area", node.type
  end

  def test_sensor
    node = sensor("s") { text("t", "hi") }
    assert_equal "sensor", node.type
  end

  def test_themer
    node = themer { text("t", "hi") }
    assert_equal "themer", node.type
  end

  def test_pane_grid
    node = pane_grid("pg") { text("t", "hi") }
    assert_equal "pane_grid", node.type
  end

  def test_overlay
    node = overlay { text("t", "hi") }
    assert_equal "overlay", node.type
  end

  def test_rich_text
    spans = [{text: "bold", weight: :bold}, {text: " normal"}]
    node = rich_text("rt", spans)
    assert_equal "rich_text", node.type
    assert_equal spans, node.props[:spans]
  end

  def test_table
    node = table("tbl", columns: [], rows: [])
    assert_equal "table", node.type
  end

  # -- Canvas DSL --------------------------------------------------------------

  def test_canvas_basic
    node = canvas("c", width: 200, height: 100)
    assert_equal "canvas", node.type
    assert_equal 200, node.props[:width]
  end

  def test_canvas_with_layers
    node = canvas("c", width: 200, height: 100) do
      layer("bg") do
        canvas_rect(0, 0, 200, 100, fill: "#eee")
      end
      layer("fg") do
        canvas_circle(100, 50, 20, fill: "red")
      end
    end

    assert_equal "canvas", node.type
    assert_equal 2, node.props[:layers].keys.length
    assert_equal "rect", node.props[:layers]["bg"].first[:type]
    assert_equal "circle", node.props[:layers]["fg"].first[:type]
  end

  def test_canvas_with_flat_shapes
    node = canvas("c", width: 100, height: 100) do
      canvas_rect(0, 0, 100, 100)
      canvas_line(0, 0, 100, 100)
    end

    assert_equal 2, node.props[:shapes].length
  end

  def test_canvas_text_shape
    node = canvas("c", width: 100, height: 100) do
      layer("text_layer") do
        canvas_text(10, 20, "Hello")
      end
    end

    shape = node.props[:layers]["text_layer"].first
    assert_equal "text", shape[:type]
    assert_equal "Hello", shape[:content]
  end

  def test_canvas_path_shape
    node = canvas("c", width: 100, height: 100) do
      layer("paths") do
        canvas_path([
          Plushie::Canvas::Shape.move_to(0, 0),
          Plushie::Canvas::Shape.line_to(50, 50),
          Plushie::Canvas::Shape.close
        ])
      end
    end

    shape = node.props[:layers]["paths"].first
    assert_equal "path", shape[:type]
    assert_equal 3, shape[:commands].length
  end
end
