# frozen_string_literal: true

require "test_helper"

class TestWidgetBuilders < Minitest::Test
  def test_button_new_and_build
    btn = Plushie::Widget::Button.new("save", "Save", style: :primary)
    assert_equal "save", btn.id
    assert_equal "Save", btn.label

    node = btn.build
    assert_equal "save", node.id
    assert_equal "button", node.type
    assert_equal "Save", node.props[:label]
    assert_equal :primary, node.props[:style]
  end

  def test_button_chainable_setters
    btn = Plushie::Widget::Button.new("ok", "OK")
    btn2 = btn.set_width(200).set_disabled(true)

    # Original unchanged
    assert_nil btn.width
    assert_nil btn.disabled

    # New copy has changes
    assert_equal 200, btn2.width
    assert_equal true, btn2.disabled

    node = btn2.build
    assert_equal 200, node.props[:width]
    assert_equal true, node.props[:disabled]
  end

  def test_button_nil_props_skipped
    btn = Plushie::Widget::Button.new("bare", "Click")
    node = btn.build
    refute node.props.key?(:width)
    refute node.props.key?(:height)
    refute node.props.key?(:disabled)
  end

  def test_text_new_and_build
    txt = Plushie::Widget::Text.new("title", "Hello World", size: 24, color: "#ff0000")
    node = txt.build
    assert_equal "text", node.type
    assert_equal "Hello World", node.props[:content]
    assert_equal 24, node.props[:size]
    assert_equal "#ff0000", node.props[:color]
  end

  def test_text_input_new_and_build
    ti = Plushie::Widget::TextInput.new("search", "query", placeholder: "Type here...")
    node = ti.build
    assert_equal "text_input", node.type
    assert_equal "query", node.props[:value]
    assert_equal "Type here...", node.props[:placeholder]
  end

  def test_column_with_children
    btn = Plushie::Widget::Button.new("a", "A")
    col = Plushie::Widget::Column.new("main", spacing: 8)
      .push(btn)
    node = col.build
    assert_equal "column", node.type
    assert_equal 8, node.props[:spacing]
    assert_equal 1, node.children.length
    assert_equal "a", node.children[0].id
  end

  def test_row_with_children
    row = Plushie::Widget::Row.new("actions", spacing: 4)
      .push(Plushie::Widget::Button.new("ok", "OK"))
      .push(Plushie::Widget::Button.new("cancel", "Cancel"))
    node = row.build
    assert_equal "row", node.type
    assert_equal 2, node.children.length
  end

  def test_container_build
    c = Plushie::Widget::Container.new("box",
      padding: 16, width: :fill, background: "#eee")
    node = c.build
    assert_equal "container", node.type
    assert_equal 16, node.props[:padding]
    assert_equal :fill, node.props[:width]
    assert_equal "#eee", node.props[:background]
  end

  def test_window_build
    w = Plushie::Widget::Window.new("main",
      title: "My App", size: [800, 600], resizable: false)
    node = w.build
    assert_equal "window", node.type
    assert_equal "My App", node.props[:title]
    assert_equal [800, 600], node.props[:size]
    assert_equal false, node.props[:resizable]
  end

  def test_checkbox_build
    cb = Plushie::Widget::Checkbox.new("agree", "I agree", true)
    node = cb.build
    assert_equal "checkbox", node.type
    assert_equal "I agree", node.props[:label]
    assert_equal true, node.props[:checked]
  end

  def test_slider_build
    s = Plushie::Widget::Slider.new("vol", [0, 100], 50, step: 5)
    node = s.build
    assert_equal "slider", node.type
    assert_equal [0, 100], node.props[:range]
    assert_equal 50, node.props[:value]
    assert_equal 5, node.props[:step]
  end

  def test_image_build
    img = Plushie::Widget::Image.new("photo", "cat.png",
      width: 200, height: 150, content_fit: :cover)
    node = img.build
    assert_equal "image", node.type
    assert_equal "cat.png", node.props[:source]
    assert_equal 200, node.props[:width]
    assert_equal :cover, node.props[:content_fit]
  end

  def test_scrollable_with_children
    s = Plushie::Widget::Scrollable.new("scroll",
      height: 300, direction: :vertical)
      .push(Plushie::Widget::Text.new("content", "Long text..."))
    node = s.build
    assert_equal "scrollable", node.type
    assert_equal 300, node.props[:height]
    assert_equal 1, node.children.length
  end

  def test_canvas_build
    c = Plushie::Widget::Canvas.new("chart",
      width: 400, height: 300,
      shapes: [{type: "rect", x: 0, y: 0, w: 400, h: 300}])
    node = c.build
    assert_equal "canvas", node.type
    assert_equal 400, node.props[:width]
    assert_equal 1, node.props[:shapes].length
  end

  def test_canvas_add_layer
    c = Plushie::Widget::Canvas.new("chart", width: 200, height: 200)
      .add_layer("bg", [{type: "rect", x: 0, y: 0, w: 200, h: 200}])
      .add_layer("fg", [{type: "circle", x: 100, y: 100, r: 50}])
    node = c.build
    assert_equal 2, node.props[:layers].keys.length
    assert_equal "rect", node.props[:layers]["bg"].first[:type]
    assert_equal "circle", node.props[:layers]["fg"].first[:type]
  end

  def test_table_build
    cols = [{key: "name", label: "Name"}, {key: "age", label: "Age"}]
    rows = [{name: "Alice", age: 30}, {name: "Bob", age: 25}]
    t = Plushie::Widget::Table.new("people", columns: cols, rows: rows)
    node = t.build
    assert_equal "table", node.type
    assert_equal 2, node.props[:columns].length
    assert_equal 2, node.props[:rows].length
  end
end
