# frozen_string_literal: true

require "test_helper"

class TestCanvasShapes < Minitest::Test
  S = Plushie::Canvas::Shape

  # -- Typed shape structs ---------------------------------------------------

  def test_rect_struct
    shape = S.rect(10, 20, 100, 50)
    assert_instance_of S::Rect, shape
    assert_equal 10, shape.x
    assert_equal 20, shape.y
    assert_equal 100, shape.w
    assert_equal 50, shape.h
  end

  def test_rect_with_opts
    shape = S.rect(0, 0, 50, 50, fill: "#ff0000", stroke: "#000")
    assert_equal "#ff0000", shape.fill
    assert_equal "#000", shape.stroke
  end

  def test_rect_to_wire
    shape = S.rect(10, 20, 100, 50, fill: "#ff0000")
    wire = shape.to_wire
    assert_equal "rect", wire[:type]
    assert_equal 10, wire[:x]
    assert_equal "#ff0000", wire[:fill]
    refute wire.key?(:stroke) # nil fields stripped
  end

  def test_circle_struct
    shape = S.circle(50, 50, 25, fill: "blue")
    assert_instance_of S::Circle, shape
    assert_equal 50, shape.x
    assert_equal 50, shape.y
    assert_equal 25, shape.r
    assert_equal "blue", shape.fill
  end

  def test_circle_to_wire
    wire = S.circle(50, 50, 25).to_wire
    assert_equal "circle", wire[:type]
    assert_equal 25, wire[:r]
  end

  def test_line_struct
    shape = S.line(0, 0, 100, 100)
    assert_instance_of S::Line, shape
    assert_equal 0, shape.x1
    assert_equal 100, shape.x2
  end

  def test_line_to_wire
    wire = S.line(0, 0, 100, 100).to_wire
    assert_equal "line", wire[:type]
  end

  def test_canvas_text_struct
    shape = S.canvas_text(10, 20, "Hello")
    assert_instance_of S::CanvasText, shape
    assert_equal "Hello", shape.content
  end

  def test_canvas_text_to_wire
    wire = S.canvas_text(10, 20, "Hello", size: 16).to_wire
    assert_equal "text", wire[:type]
    assert_equal "Hello", wire[:content]
    assert_equal 16, wire[:size]
  end

  def test_path_struct
    cmds = [S.move_to(0, 0), S.line_to(100, 100), S.close]
    shape = S.path(cmds, fill: "#000")
    assert_instance_of S::Path, shape
    assert_equal "#000", shape.fill
  end

  def test_path_to_wire
    cmds = [S.move_to(0, 0), S.line_to(50, 50)]
    wire = S.path(cmds, stroke: "#000").to_wire
    assert_equal "path", wire[:type]
    assert_kind_of Array, wire[:commands]
  end

  def test_group_struct
    children = [S.rect(0, 0, 10, 10)]
    shape = S.group(children, opacity: 0.8)
    assert_instance_of S::Group, shape
    assert_in_delta 0.8, shape.opacity
  end

  def test_group_to_wire
    children = [S.rect(0, 0, 10, 10)]
    wire = S.group(children, opacity: 0.5).to_wire
    assert_equal "group", wire[:type]
    assert_in_delta 0.5, wire[:opacity]
    # Nested shapes are converted via to_wire
    assert_equal "rect", wire[:shapes].first[:type]
  end

  # -- Canvas image ----------------------------------------------------------

  def test_canvas_image_struct
    shape = S.canvas_image("icon.png", 10, 20, 64, 64)
    assert_instance_of S::CanvasImage, shape
    assert_equal "icon.png", shape.source
    assert_equal 10, shape.x
    assert_equal 20, shape.y
    assert_equal 64, shape.w
    assert_equal 64, shape.h
    assert_nil shape.rotation
    assert_nil shape.opacity
  end

  def test_canvas_image_with_opts
    shape = S.canvas_image("photo.jpg", 0, 0, 200, 150, rotation: 0.5, opacity: 0.8)
    assert_in_delta 0.5, shape.rotation
    assert_in_delta 0.8, shape.opacity
  end

  def test_canvas_image_to_wire
    wire = S.canvas_image("icon.png", 10, 20, 64, 64).to_wire
    assert_equal "image", wire[:type]
    assert_equal "icon.png", wire[:source]
    assert_equal 10, wire[:x]
    assert_equal 64, wire[:w]
    refute wire.key?(:rotation)
    refute wire.key?(:opacity)
  end

  def test_canvas_image_to_wire_with_opts
    wire = S.canvas_image("img.png", 0, 0, 100, 100, rotation: 1.5).to_wire
    assert_in_delta 1.5, wire[:rotation]
  end

  # -- Canvas SVG ------------------------------------------------------------

  def test_canvas_svg_struct
    shape = S.canvas_svg("icon.svg", 10, 20, 32, 32)
    assert_instance_of S::CanvasSvg, shape
    assert_equal "icon.svg", shape.source
    assert_equal 32, shape.w
    assert_nil shape.interactive
  end

  def test_canvas_svg_to_wire
    wire = S.canvas_svg("icon.svg", 10, 20, 32, 32).to_wire
    assert_equal "svg", wire[:type]
    assert_equal "icon.svg", wire[:source]
    assert_equal 10, wire[:x]
    refute wire.key?(:interactive)
  end

  # -- Stroke ----------------------------------------------------------------

  def test_stroke_struct
    s = S.stroke("#ff0000", 2)
    assert_instance_of S::Stroke, s
    assert_equal "#ff0000", s.color
    assert_equal 2, s.width
    assert_nil s.cap
    assert_nil s.join
    assert_nil s.dash
  end

  def test_stroke_with_opts
    s = S.stroke("#000", 3, cap: "round", join: "bevel")
    assert_equal "round", s.cap
    assert_equal "bevel", s.join
  end

  def test_stroke_to_wire
    wire = S.stroke("#000", 2).to_wire
    assert_equal "#000", wire[:color]
    assert_equal 2, wire[:width]
    refute wire.key?(:cap)
    refute wire.key?(:dash)
  end

  def test_stroke_with_dash_to_wire
    dash = S::Dash.new(segments: [4, 2], offset: 0)
    wire = S.stroke("#000", 1, dash: dash).to_wire
    assert_equal({segments: [4, 2], offset: 0}, wire[:dash])
  end

  def test_stroke_hash_access
    s = S.stroke("#f00", 2)
    assert_equal "#f00", s[:color]
  end

  # -- Dash ------------------------------------------------------------------

  def test_dash_struct
    d = S::Dash.new(segments: [4, 2], offset: 0)
    assert_instance_of S::Dash, d
    assert_equal [4, 2], d.segments
    assert_equal 0, d.offset
  end

  def test_dash_to_wire
    wire = S::Dash.new(segments: [10, 5], offset: 3).to_wire
    assert_equal [10, 5], wire[:segments]
    assert_equal 3, wire[:offset]
  end

  # -- LinearGradient --------------------------------------------------------

  def test_linear_gradient_struct
    g = S.linear_gradient([0, 0], [100, 0], [[0.0, "#ff0000"], [1.0, "#0000ff"]])
    assert_instance_of S::LinearGradient, g
    assert_equal [0, 0], g.from
    assert_equal [100, 0], g.to
  end

  def test_linear_gradient_to_wire
    g = S.linear_gradient([0, 0], [200, 0], [[0, "red"], [1, "blue"]])
    wire = g.to_wire
    assert_equal "linear", wire[:type]
    assert_equal [0, 0], wire[:start]
    assert_equal [200, 0], wire[:end]
    assert_equal [[0, "red"], [1, "blue"]], wire[:stops]
  end

  def test_linear_gradient_hash_access
    g = S.linear_gradient([0, 0], [100, 0], [[0, "red"]])
    assert_equal "linear", g[:type]
  end

  # -- ShapeStyle ------------------------------------------------------------

  def test_shape_style_struct
    style = S::ShapeStyle.new(fill: "#ff0000", opacity: 0.5)
    assert_instance_of S::ShapeStyle, style
    assert_equal "#ff0000", style.fill
    assert_in_delta 0.5, style.opacity
    assert_nil style.stroke
  end

  def test_shape_style_to_wire
    wire = S::ShapeStyle.new(fill: "red", opacity: 0.8).to_wire
    assert_equal "red", wire[:fill]
    assert_in_delta 0.8, wire[:opacity]
    refute wire.key?(:stroke)
  end

  def test_shape_style_empty_to_wire
    wire = S::ShapeStyle.new.to_wire
    assert_empty wire
  end

  # -- DragBounds ------------------------------------------------------------

  def test_drag_bounds_struct
    b = S::DragBounds.new(min_x: 0, max_x: 400)
    assert_instance_of S::DragBounds, b
    assert_equal 0, b.min_x
    assert_equal 400, b.max_x
    assert_nil b.min_y
    assert_nil b.max_y
  end

  def test_drag_bounds_to_wire
    wire = S::DragBounds.new(min_x: 0, max_x: 100, min_y: 10, max_y: 200).to_wire
    assert_equal 0, wire[:min_x]
    assert_equal 100, wire[:max_x]
    assert_equal 10, wire[:min_y]
    assert_equal 200, wire[:max_y]
  end

  def test_drag_bounds_nil_stripped
    wire = S::DragBounds.new(min_x: 0).to_wire
    assert_equal({min_x: 0}, wire)
  end

  # -- HitRect ---------------------------------------------------------------

  def test_hit_rect_struct
    hr = S::HitRect.new(x: 0, y: 0, w: 100, h: 50)
    assert_instance_of S::HitRect, hr
    assert_equal 100, hr.w
    assert_equal 50, hr.h
  end

  def test_hit_rect_to_wire
    wire = S::HitRect.new(x: 5, y: 10, w: 80, h: 40).to_wire
    assert_equal({x: 5, y: 10, w: 80, h: 40}, wire)
  end

  # -- Interactive -----------------------------------------------------------

  def test_interactive_struct
    i = S::Interactive.new(id: "btn", on_click: true, cursor: "pointer")
    assert_instance_of S::Interactive, i
    assert_equal "btn", i.id
    assert_equal true, i.on_click
    assert_equal "pointer", i.cursor
    assert_nil i.draggable
  end

  def test_interactive_to_wire
    i = S::Interactive.new(id: "btn", on_click: true)
    wire = i.to_wire
    assert_equal "btn", wire[:id]
    assert_equal true, wire[:on_click]
    refute wire.key?(:draggable)
    refute wire.key?(:cursor)
  end

  def test_interactive_nested_structs_to_wire
    bounds = S::DragBounds.new(min_x: 0, max_x: 200)
    style = S::ShapeStyle.new(fill: "red")
    hr = S::HitRect.new(x: 0, y: 0, w: 50, h: 50)
    i = S::Interactive.new(
      id: "drag",
      draggable: true,
      drag_bounds: bounds,
      hover_style: style,
      hit_rect: hr
    )
    wire = i.to_wire
    assert_equal({min_x: 0, max_x: 200}, wire[:drag_bounds])
    assert_equal({fill: "red"}, wire[:hover_style])
    assert_equal({x: 0, y: 0, w: 50, h: 50}, wire[:hit_rect])
  end

  # -- Transform commands ----------------------------------------------------

  def test_push_transform
    t = S.push_transform
    assert_instance_of S::PushTransform, t
    assert_equal({type: "push_transform"}, t.to_wire)
  end

  def test_pop_transform
    t = S.pop_transform
    assert_instance_of S::PopTransform, t
    assert_equal({type: "pop_transform"}, t.to_wire)
  end

  def test_translate
    t = S.translate(100, 50)
    assert_instance_of S::Translate, t
    assert_equal 100, t.x
    assert_equal 50, t.y
    assert_equal({type: "translate", x: 100, y: 50}, t.to_wire)
  end

  def test_rotate
    r = S.rotate(Math::PI / 4)
    assert_instance_of S::Rotate, r
    assert_in_delta Math::PI / 4, r.angle
    wire = r.to_wire
    assert_equal "rotate", wire[:type]
    assert_in_delta Math::PI / 4, wire[:angle]
  end

  def test_scale
    s = S.scale(2.0, 0.5)
    assert_instance_of S::Scale, s
    assert_in_delta 2.0, s.x
    assert_in_delta 0.5, s.y
    assert_equal({type: "scale", x: 2.0, y: 0.5}, s.to_wire)
  end

  # -- Clipping commands -----------------------------------------------------

  def test_push_clip
    c = S.push_clip(10, 20, 100, 80)
    assert_instance_of S::PushClip, c
    assert_equal 10, c.x
    assert_equal 20, c.y
    assert_equal 100, c.w
    assert_equal 80, c.h
    assert_equal({type: "push_clip", x: 10, y: 20, w: 100, h: 80}, c.to_wire)
  end

  def test_pop_clip
    c = S.pop_clip
    assert_instance_of S::PopClip, c
    assert_equal({type: "pop_clip"}, c.to_wire)
  end

  # -- Path commands ---------------------------------------------------------

  def test_move_to
    assert_equal ["move_to", 10, 20], S.move_to(10, 20)
  end

  def test_line_to
    assert_equal ["line_to", 50, 60], S.line_to(50, 60)
  end

  def test_close
    assert_equal ["close"], S.close
  end

  def test_bezier_to
    cmd = S.bezier_to(10, 20, 30, 40, 50, 60)
    assert_equal "bezier_to", cmd[0]
    assert_equal 6, cmd.length - 1
  end

  def test_quadratic_to
    cmd = S.quadratic_to(10, 20, 30, 40)
    assert_equal "quadratic_to", cmd[0]
  end

  def test_arc
    cmd = S.arc(50, 50, 25, 0, Math::PI)
    assert_equal "arc", cmd[0]
  end

  # -- Data.define immutability ----------------------------------------------

  def test_structs_are_frozen
    assert S.rect(0, 0, 10, 10).frozen?
    assert S.circle(0, 0, 5).frozen?
    assert S.stroke("#000", 1).frozen?
    assert S::Dash.new(segments: [4, 2], offset: 0).frozen?
    assert S.linear_gradient([0, 0], [1, 0], []).frozen?
    assert S::ShapeStyle.new.frozen?
    assert S::DragBounds.new.frozen?
    assert S::HitRect.new(x: 0, y: 0, w: 1, h: 1).frozen?
    assert S::Interactive.new(id: "x").frozen?
    assert S.push_transform.frozen?
    assert S.pop_transform.frozen?
    assert S.translate(0, 0).frozen?
    assert S.rotate(0).frozen?
    assert S.scale(1, 1).frozen?
    assert S.push_clip(0, 0, 1, 1).frozen?
    assert S.pop_clip.frozen?
    assert S.canvas_image("x", 0, 0, 1, 1).frozen?
    assert S.canvas_svg("x", 0, 0, 1, 1).frozen?
  end
end
