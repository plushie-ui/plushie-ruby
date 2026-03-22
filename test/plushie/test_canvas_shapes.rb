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

  # -- Style helpers ---------------------------------------------------------

  def test_stroke_helper
    s = S.stroke("#ff0000", 2, dash: [4, 2])
    assert_equal "#ff0000", s[:color]
    assert_equal 2, s[:width]
    assert_equal [4, 2], s[:dash]
  end

  def test_linear_gradient_helper
    g = S.linear_gradient([0, 0], [100, 0], [[0, "#ff0000"], [1, "#0000ff"]])
    assert_equal "linear", g[:type]
    assert_equal [0, 0], g[:from]
    assert_equal [100, 0], g[:to]
    assert_equal 2, g[:stops].length
  end
end
