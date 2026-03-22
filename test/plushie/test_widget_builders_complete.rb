# frozen_string_literal: true

require "test_helper"

class TestWidgetBuildersComplete < Minitest::Test
  # -- Leaf widgets --

  def test_toggler_new_and_build
    t = Plushie::Widget::Toggler.new("dark", true, label: "Dark mode", size: 20)
    assert_equal "dark", t.id
    assert_equal true, t.is_toggled

    node = t.build
    assert_equal "toggler", node.type
    assert_equal true, node.props[:is_toggled]
    assert_equal "Dark mode", node.props[:label]
    assert_equal 20, node.props[:size]
  end

  def test_toggler_chainable_setters
    t = Plushie::Widget::Toggler.new("t", false)
    t2 = t.set_disabled(true).set_spacing(8)
    assert_nil t.disabled
    assert_equal true, t2.disabled
    assert_equal 8, t2.spacing
  end

  def test_vertical_slider_new_and_build
    vs = Plushie::Widget::VerticalSlider.new("vol", [0, 100], 50, step: 5)
    node = vs.build
    assert_equal "vertical_slider", node.type
    assert_equal [0, 100], node.props[:range]
    assert_equal 50, node.props[:value]
    assert_equal 5, node.props[:step]
  end

  def test_vertical_slider_nil_skipping
    vs = Plushie::Widget::VerticalSlider.new("v", [0, 10], 5)
    node = vs.build
    refute node.props.key?(:shift_step)
    refute node.props.key?(:rail_color)
  end

  def test_pick_list_new_and_build
    pl = Plushie::Widget::PickList.new("color", %w[Red Green Blue],
      selected: "Red", placeholder: "Choose...")
    node = pl.build
    assert_equal "pick_list", node.type
    assert_equal %w[Red Green Blue], node.props[:options]
    assert_equal "Red", node.props[:selected]
    assert_equal "Choose...", node.props[:placeholder]
  end

  def test_pick_list_chainable_setters
    pl = Plushie::Widget::PickList.new("p", %w[A B])
    pl2 = pl.set_text_size(14).set_on_open(true)
    assert_equal 14, pl2.text_size
    assert_equal true, pl2.on_open
  end

  def test_combo_box_new_and_build
    cb = Plushie::Widget::ComboBox.new("fruit", %w[Apple Banana],
      selected: "Apple", placeholder: "Search...")
    node = cb.build
    assert_equal "combo_box", node.type
    assert_equal %w[Apple Banana], node.props[:options]
    assert_equal "Apple", node.props[:selected]
    assert_equal "Search...", node.props[:placeholder]
  end

  def test_combo_box_chainable_setters
    cb = Plushie::Widget::ComboBox.new("c", %w[X Y])
    cb2 = cb.set_on_option_hovered(true).set_menu_height(200)
    assert_equal true, cb2.on_option_hovered
    assert_equal 200, cb2.menu_height
  end

  def test_radio_new_and_build
    r = Plushie::Widget::Radio.new("opt_a", "a", "a",
      label: "Option A", group: "choices")
    node = r.build
    assert_equal "radio", node.type
    assert_equal "a", node.props[:value]
    assert_equal "a", node.props[:selected]
    assert_equal "Option A", node.props[:label]
    assert_equal "choices", node.props[:group]
  end

  def test_radio_chainable_setters
    r = Plushie::Widget::Radio.new("r", "x", "x")
    r2 = r.set_spacing(10).set_size(16)
    assert_equal 10, r2.spacing
    assert_equal 16, r2.size
  end

  def test_progress_bar_new_and_build
    pb = Plushie::Widget::ProgressBar.new("upload", [0, 100], 42,
      style: :primary, label: "Upload")
    node = pb.build
    assert_equal "progress_bar", node.type
    assert_equal [0, 100], node.props[:range]
    assert_equal 42, node.props[:value]
    assert_equal :primary, node.props[:style]
    assert_equal "Upload", node.props[:label]
  end

  def test_progress_bar_chainable_setters
    pb = Plushie::Widget::ProgressBar.new("p", [0, 50], 25)
    pb2 = pb.set_vertical(true).set_width(:fill)
    assert_equal true, pb2.vertical
    assert_equal :fill, pb2.width
  end

  def test_text_editor_new_and_build
    ed = Plushie::Widget::TextEditor.new("editor",
      content: "Hello", placeholder: "Type...", size: 14)
    node = ed.build
    assert_equal "text_editor", node.type
    assert_equal "Hello", node.props[:content]
    assert_equal "Type...", node.props[:placeholder]
    assert_equal 14, node.props[:size]
  end

  def test_text_editor_chainable_setters
    ed = Plushie::Widget::TextEditor.new("e")
    ed2 = ed.set_highlight_syntax("rb").set_highlight_theme("solarized_dark")
    assert_equal "rb", ed2.highlight_syntax
    assert_equal "solarized_dark", ed2.highlight_theme
  end

  def test_svg_new_and_build
    svg = Plushie::Widget::Svg.new("logo", "logo.svg",
      width: 64, height: 64, opacity: 0.8)
    node = svg.build
    assert_equal "svg", node.type
    assert_equal "logo.svg", node.props[:source]
    assert_equal 64, node.props[:width]
    assert_equal 0.8, node.props[:opacity]
  end

  def test_svg_nil_skipping
    svg = Plushie::Widget::Svg.new("s", "icon.svg")
    node = svg.build
    refute node.props.key?(:rotation)
    refute node.props.key?(:color)
  end

  def test_markdown_new_and_build
    md = Plushie::Widget::Markdown.new("docs", "# Title\nBody",
      text_size: 16, code_theme: "base16_ocean")
    node = md.build
    assert_equal "markdown", node.type
    assert_equal "# Title\nBody", node.props[:content]
    assert_equal 16, node.props[:text_size]
    assert_equal "base16_ocean", node.props[:code_theme]
  end

  def test_markdown_chainable_setters
    md = Plushie::Widget::Markdown.new("m", "text")
    md2 = md.set_h1_size(32).set_spacing(12)
    assert_equal 32, md2.h1_size
    assert_equal 12, md2.spacing
  end

  def test_qr_code_new_and_build
    qr = Plushie::Widget::QrCode.new("link", "https://example.com",
      cell_size: 6, error_correction: :high)
    node = qr.build
    assert_equal "qr_code", node.type
    assert_equal "https://example.com", node.props[:data]
    assert_equal 6, node.props[:cell_size]
    assert_equal :high, node.props[:error_correction]
  end

  def test_qr_code_chainable_setters
    qr = Plushie::Widget::QrCode.new("q", "data")
    qr2 = qr.set_cell_color("#000").set_background_color("#fff")
    assert_equal "#000", qr2.cell_color
    assert_equal "#fff", qr2.background_color
  end

  def test_rich_text_new_and_build
    rt = Plushie::Widget::RichText.new("msg",
      spans: [{text: "Hello", size: 16}], size: 14)
    node = rt.build
    assert_equal "rich_text", node.type
    assert_equal [{text: "Hello", size: 16}], node.props[:spans]
    assert_equal 14, node.props[:size]
  end

  def test_rich_text_chainable_setters
    rt = Plushie::Widget::RichText.new("r")
    rt2 = rt.set_wrapping(:word).set_ellipsis("end")
    assert_equal :word, rt2.wrapping
    assert_equal "end", rt2.ellipsis
  end

  def test_rule_new_and_build
    r = Plushie::Widget::Rule.new("divider",
      direction: :horizontal, height: 2, style: :default)
    node = r.build
    assert_equal "rule", node.type
    assert_equal :horizontal, node.props[:direction]
    assert_equal 2, node.props[:height]
    assert_equal :default, node.props[:style]
  end

  def test_rule_nil_skipping
    r = Plushie::Widget::Rule.new("r")
    node = r.build
    refute node.props.key?(:direction)
    refute node.props.key?(:height)
  end

  def test_space_new_and_build
    sp = Plushie::Widget::Space.new("gap", width: 20, height: 10)
    node = sp.build
    assert_equal "space", node.type
    assert_equal 20, node.props[:width]
    assert_equal 10, node.props[:height]
  end

  def test_space_nil_skipping
    sp = Plushie::Widget::Space.new("s")
    node = sp.build
    refute node.props.key?(:width)
    refute node.props.key?(:height)
  end

  # -- Container widgets --

  def test_tooltip_new_and_build
    tt = Plushie::Widget::Tooltip.new("help", "Click for help",
      position: :top, gap: 4)
      .push(Plushie::Widget::Button.new("btn", "?"))
    node = tt.build
    assert_equal "tooltip", node.type
    assert_equal "Click for help", node.props[:tip]
    assert_equal :top, node.props[:position]
    assert_equal 4, node.props[:gap]
    assert_equal 1, node.children.length
    assert_equal "btn", node.children[0].id
  end

  def test_tooltip_chainable_setters
    tt = Plushie::Widget::Tooltip.new("t", "tip")
    tt2 = tt.set_delay(500).set_padding(8)
    assert_equal 500, tt2.delay
    assert_equal 8, tt2.padding
  end

  def test_grid_new_and_build
    g = Plushie::Widget::Grid.new("items", columns: 3, spacing: 8)
      .push(Plushie::Widget::Text.new("a", "A"))
      .push(Plushie::Widget::Text.new("b", "B"))
    node = g.build
    assert_equal "grid", node.type
    assert_equal 3, node.props[:columns]
    assert_equal 8, node.props[:spacing]
    assert_equal 2, node.children.length
  end

  def test_grid_chainable_setters
    g = Plushie::Widget::Grid.new("g")
    g2 = g.set_fluid(200).set_column_width(:fill)
    assert_equal 200, g2.fluid
    assert_equal :fill, g2.column_width
  end

  def test_keyed_column_new_and_build
    kc = Plushie::Widget::KeyedColumn.new("list", spacing: 4, max_width: 600)
      .push(Plushie::Widget::Text.new("item1", "First"))
    node = kc.build
    assert_equal "keyed_column", node.type
    assert_equal 4, node.props[:spacing]
    assert_equal 600, node.props[:max_width]
    assert_equal 1, node.children.length
  end

  def test_keyed_column_chainable_setters
    kc = Plushie::Widget::KeyedColumn.new("k")
    kc2 = kc.set_padding(10).set_width(:fill)
    assert_equal 10, kc2.padding
    assert_equal :fill, kc2.width
  end

  def test_pin_new_and_build
    p = Plushie::Widget::Pin.new("badge", x: 100, y: 50)
      .push(Plushie::Widget::Text.new("label", "!"))
    node = p.build
    assert_equal "pin", node.type
    assert_equal 100, node.props[:x]
    assert_equal 50, node.props[:y]
    assert_equal 1, node.children.length
  end

  def test_pin_chainable_setters
    p = Plushie::Widget::Pin.new("p")
    p2 = p.set_x(10).set_y(20).set_width(50)
    assert_equal 10, p2.x
    assert_equal 20, p2.y
    assert_equal 50, p2.width
  end

  def test_floating_new_and_build
    f = Plushie::Widget::Floating.new("popup",
      translate_x: 10, translate_y: 20, scale: 1.5)
      .push(Plushie::Widget::Text.new("msg", "Hello"))
    node = f.build
    assert_equal "float", node.type
    assert_equal 10, node.props[:translate_x]
    assert_equal 20, node.props[:translate_y]
    assert_equal 1.5, node.props[:scale]
    assert_equal 1, node.children.length
  end

  def test_floating_chainable_setters
    f = Plushie::Widget::Floating.new("f")
    f2 = f.set_width(:fill).set_height(100)
    assert_equal :fill, f2.width
    assert_equal 100, f2.height
  end

  def test_mouse_area_new_and_build
    ma = Plushie::Widget::MouseArea.new("clickable",
      cursor: :pointer, on_right_press: true, on_scroll: true)
      .push(Plushie::Widget::Text.new("label", "Right-click me"))
    node = ma.build
    assert_equal "mouse_area", node.type
    assert_equal :pointer, node.props[:cursor]
    assert_equal true, node.props[:on_right_press]
    assert_equal true, node.props[:on_scroll]
    assert_equal 1, node.children.length
  end

  def test_mouse_area_chainable_setters
    ma = Plushie::Widget::MouseArea.new("m")
    ma2 = ma.set_on_double_click(true).set_event_rate(30)
    assert_equal true, ma2.on_double_click
    assert_equal 30, ma2.event_rate
  end

  def test_sensor_new_and_build
    s = Plushie::Widget::Sensor.new("detect", delay: 100, anticipate: 50)
      .push(Plushie::Widget::Text.new("content", "Watched"))
    node = s.build
    assert_equal "sensor", node.type
    assert_equal 100, node.props[:delay]
    assert_equal 50, node.props[:anticipate]
    assert_equal 1, node.children.length
  end

  def test_sensor_chainable_setters
    s = Plushie::Widget::Sensor.new("s")
    s2 = s.set_on_resize("resized").set_event_rate(10)
    assert_equal "resized", s2.on_resize
    assert_equal 10, s2.event_rate
  end

  def test_themer_new_and_build
    t = Plushie::Widget::Themer.new("dark", :dark)
      .push(Plushie::Widget::Text.new("msg", "Dark themed"))
    node = t.build
    assert_equal "themer", node.type
    assert_equal :dark, node.props[:theme]
    assert_equal 1, node.children.length
  end

  def test_themer_chainable_setters
    t = Plushie::Widget::Themer.new("t", :light)
    t2 = t.set_theme(:nord)
    assert_equal :nord, t2.theme
    # Original unchanged
    assert_equal :light, t.theme
  end

  def test_pane_grid_new_and_build
    pg = Plushie::Widget::PaneGrid.new("editor",
      spacing: 4, min_size: 50, panes: %w[left right])
      .push(Plushie::Widget::Text.new("left", "Left"))
      .push(Plushie::Widget::Text.new("right", "Right"))
    node = pg.build
    assert_equal "pane_grid", node.type
    assert_equal 4, node.props[:spacing]
    assert_equal 50, node.props[:min_size]
    assert_equal %w[left right], node.props[:panes]
    assert_equal 2, node.children.length
  end

  def test_pane_grid_chainable_setters
    pg = Plushie::Widget::PaneGrid.new("pg")
    pg2 = pg.set_divider_color("#ccc").set_divider_width(2)
    assert_equal "#ccc", pg2.divider_color
    assert_equal 2, pg2.divider_width
  end

  def test_overlay_new_and_build
    o = Plushie::Widget::Overlay.new("menu",
      position: :below, gap: 4, flip: true)
      .push(Plushie::Widget::Button.new("trigger", "Open"))
      .push(Plushie::Widget::Text.new("content", "Items"))
    node = o.build
    assert_equal "overlay", node.type
    assert_equal :below, node.props[:position]
    assert_equal 4, node.props[:gap]
    assert_equal true, node.props[:flip]
    assert_equal 2, node.children.length
  end

  def test_overlay_chainable_setters
    o = Plushie::Widget::Overlay.new("o")
    o2 = o.set_offset_x(10).set_offset_y(5).set_align(:start)
    assert_equal 10, o2.offset_x
    assert_equal 5, o2.offset_y
    assert_equal :start, o2.align
  end

  def test_responsive_new_and_build
    r = Plushie::Widget::Responsive.new("layout", width: :fill, height: :fill)
      .push(Plushie::Widget::Text.new("content", "Responsive"))
    node = r.build
    assert_equal "responsive", node.type
    assert_equal :fill, node.props[:width]
    assert_equal :fill, node.props[:height]
    assert_equal 1, node.children.length
  end

  def test_responsive_nil_skipping
    r = Plushie::Widget::Responsive.new("r")
    node = r.build
    refute node.props.key?(:width)
    refute node.props.key?(:height)
  end

  def test_stack_new_and_build
    s = Plushie::Widget::Stack.new("layers", width: :fill, clip: true)
      .push(Plushie::Widget::Text.new("bg", "Background"))
      .push(Plushie::Widget::Text.new("fg", "Foreground"))
    node = s.build
    assert_equal "stack", node.type
    assert_equal :fill, node.props[:width]
    assert_equal true, node.props[:clip]
    assert_equal 2, node.children.length
  end

  def test_stack_chainable_setters
    s = Plushie::Widget::Stack.new("s")
    s2 = s.set_height(300).set_clip(false)
    assert_equal 300, s2.height
    assert_equal false, s2.clip
  end

  # -- Immutability: push does not mutate original --

  def test_container_push_immutability
    [
      Plushie::Widget::Tooltip.new("t", "tip"),
      Plushie::Widget::Grid.new("g"),
      Plushie::Widget::KeyedColumn.new("kc"),
      Plushie::Widget::Pin.new("p"),
      Plushie::Widget::Floating.new("f"),
      Plushie::Widget::MouseArea.new("ma"),
      Plushie::Widget::Sensor.new("s"),
      Plushie::Widget::Themer.new("th", :dark),
      Plushie::Widget::PaneGrid.new("pg"),
      Plushie::Widget::Overlay.new("o"),
      Plushie::Widget::Responsive.new("r"),
      Plushie::Widget::Stack.new("st")
    ].each do |widget|
      child = Plushie::Widget::Text.new("c", "child")
      w2 = widget.push(child)
      assert_equal 0, widget.children.length,
        "push mutated original #{widget.class}"
      assert_equal 1, w2.children.length
    end
  end
end
