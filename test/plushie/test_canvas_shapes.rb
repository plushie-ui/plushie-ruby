# frozen_string_literal: true

require "test_helper"

class TestCanvasShapes < Minitest::Test
  S = Plushie::Canvas::Shape

  def test_rect
    shape = S.rect(10, 20, 100, 50)
    assert_equal "rect", shape[:type]
    assert_equal 10, shape[:x]
    assert_equal 20, shape[:y]
    assert_equal 100, shape[:w]
    assert_equal 50, shape[:h]
  end

  def test_rect_with_fill_and_stroke
    shape = S.rect(0, 0, 50, 50, fill: "#ff0000", stroke: {color: "#000", width: 2})
    assert_equal "#ff0000", shape[:fill]
    assert_equal "#000", shape[:stroke][:color]
    assert_equal 2, shape[:stroke][:width]
  end

  def test_circle
    shape = S.circle(50, 50, 25, fill: "blue")
    assert_equal "circle", shape[:type]
    assert_equal 50, shape[:x]
    assert_equal 50, shape[:y]
    assert_equal 25, shape[:r]
    assert_equal "blue", shape[:fill]
  end

  def test_line
    shape = S.line(0, 0, 100, 100)
    assert_equal "line", shape[:type]
    assert_equal 0, shape[:x1]
    assert_equal 0, shape[:y1]
    assert_equal 100, shape[:x2]
    assert_equal 100, shape[:y2]
  end

  def test_canvas_text
    shape = S.canvas_text(10, 20, "Hello")
    assert_equal "text", shape[:type]
    assert_equal "Hello", shape[:content]
    assert_equal 10, shape[:x]
    assert_equal 20, shape[:y]
  end

  def test_path_with_commands
    cmds = [S.move_to(0, 0), S.line_to(100, 0), S.line_to(50, 80), S.close]
    shape = S.path(cmds, fill: "green")
    assert_equal "path", shape[:type]
    assert_equal 4, shape[:commands].length
    assert_equal "green", shape[:fill]
  end

  def test_move_to
    assert_equal ["move_to", 10, 20], S.move_to(10, 20)
  end

  def test_line_to
    assert_equal ["line_to", 30, 40], S.line_to(30, 40)
  end

  def test_close
    assert_equal ["close"], S.close
  end

  def test_bezier_to
    cmd = S.bezier_to(1, 2, 3, 4, 5, 6)
    assert_equal ["bezier_to", 1, 2, 3, 4, 5, 6], cmd
  end

  def test_quadratic_to
    cmd = S.quadratic_to(1, 2, 3, 4)
    assert_equal ["quadratic_to", 1, 2, 3, 4], cmd
  end

  def test_arc
    cmd = S.arc(50, 50, 25, 0, Math::PI)
    assert_equal "arc", cmd[0]
    assert_equal 50, cmd[1]
    assert_in_delta Math::PI, cmd[5]
  end

  def test_stroke_helper
    s = S.stroke("#000", 2, line_cap: "round")
    assert_equal "#000", s[:color]
    assert_equal 2, s[:width]
    assert_equal "round", s[:line_cap]
  end

  def test_linear_gradient
    g = S.linear_gradient([0, 0], [100, 0], [[0, "#f00"], [1, "#00f"]])
    assert_equal "linear", g[:type]
    assert_equal [0, 0], g[:from]
    assert_equal [100, 0], g[:to]
    assert_equal 2, g[:stops].length
  end

  def test_group
    shapes = [S.rect(0, 0, 10, 10), S.circle(5, 5, 3)]
    g = S.group(shapes)
    assert_equal "group", g[:type]
    assert_equal 2, g[:shapes].length
  end

  def test_interactive_option
    shape = S.rect(0, 0, 10, 10, interactive: {id: "box1", on_click: true})
    assert_equal({id: "box1", on_click: true}, shape[:interactive])
  end
end
