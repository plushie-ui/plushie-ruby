# frozen_string_literal: true

require "plushie"

# Canvas-based HSV color picker widget.
#
# Renders a hue ring surrounding a saturation/value square with cursors
# indicating the current selection. The caller handles hit testing and
# drag state -- this module only handles rendering.
#
#   ColorPickerWidget.render("picker", model.hue, model.saturation, model.value)
#
# Events:
# - Canvas press/move/release on the canvas id for drag interaction
module ColorPickerWidget
  include Plushie::UI
  extend self

  CANVAS_SIZE = 400
  CX = CANVAS_SIZE / 2
  CY = CANVAS_SIZE / 2
  OUTER_R = 190
  INNER_R = 150
  MID_R = (INNER_R + OUTER_R) / 2
  SQ_ORIGIN = 100
  SQ_SIZE = 200
  SEGMENTS = 72
  CURSOR_R = 7

  def render(id, hue, saturation, value)
    canvas(id, width: CANVAS_SIZE, height: CANVAS_SIZE,
      on_press: true, on_release: true, on_move: true) do
      layer("a_ring") do
        ring_shapes
      end

      layer("b_sv_hue") do
        sv_hue_shapes(hue)
      end

      layer("c_sv_dark") do
        sv_dark_shapes
      end

      layer("d_cursors") do
        cursor_shapes(hue, saturation, value)
      end
    end
  end

  private

  def ring_shapes
    deg_per_segment = 360.0 / SEGMENTS

    SEGMENTS.times do |i|
      hue_deg = i * deg_per_segment
      a1 = (hue_deg - 90) * Math::PI / 180
      a2 = (hue_deg + deg_per_segment - 90) * Math::PI / 180

      canvas_path([
        Plushie::Canvas::Shape.move_to(CX + INNER_R * Math.cos(a1), CY + INNER_R * Math.sin(a1)),
        Plushie::Canvas::Shape.line_to(CX + OUTER_R * Math.cos(a1), CY + OUTER_R * Math.sin(a1)),
        Plushie::Canvas::Shape.line_to(CX + OUTER_R * Math.cos(a2), CY + OUTER_R * Math.sin(a2)),
        Plushie::Canvas::Shape.line_to(CX + INNER_R * Math.cos(a2), CY + INNER_R * Math.sin(a2)),
        Plushie::Canvas::Shape.close
      ], fill: hsv_to_hex(hue_deg, 1.0, 1.0))
    end
  end

  def sv_hue_shapes(hue)
    hue_color = hsv_to_hex(hue, 1.0, 1.0)

    canvas_rect(SQ_ORIGIN, SQ_ORIGIN, SQ_SIZE, SQ_SIZE,
      fill: Plushie::Canvas::Shape.linear_gradient(
        [SQ_ORIGIN, SQ_ORIGIN],
        [SQ_ORIGIN + SQ_SIZE, SQ_ORIGIN],
        [[0.0, "#ffffff"], [1.0, hue_color]]
      ))
  end

  def sv_dark_shapes
    canvas_rect(SQ_ORIGIN, SQ_ORIGIN, SQ_SIZE, SQ_SIZE,
      fill: Plushie::Canvas::Shape.linear_gradient(
        [SQ_ORIGIN, SQ_ORIGIN],
        [SQ_ORIGIN, SQ_ORIGIN + SQ_SIZE],
        [[0.0, "#00000000"], [1.0, "#000000ff"]]
      ))
  end

  def cursor_shapes(hue, saturation, value)
    angle = (hue - 90) * Math::PI / 180
    ring_x = CX + MID_R * Math.cos(angle)
    ring_y = CY + MID_R * Math.sin(angle)

    sv_x = SQ_ORIGIN + saturation * SQ_SIZE
    sv_y = SQ_ORIGIN + (1.0 - value) * SQ_SIZE

    cursor_stroke = Plushie::Canvas::Shape.stroke("#333333", 2)

    canvas_circle(ring_x, ring_y, CURSOR_R, fill: "#ffffff", stroke: cursor_stroke)
    canvas_circle(sv_x, sv_y, CURSOR_R, fill: "#ffffff", stroke: cursor_stroke)
  end

  def hsv_to_hex(h, s, v)
    h = fmod(h, 360.0)
    h += 360.0 if h < 0

    c = v * s
    h_sector = h / 60.0
    x = c * (1.0 - (fmod(h_sector, 2.0) - 1.0).abs)
    m = v - c

    r1, g1, b1 =
      if h_sector < 1 then [c, x, 0.0]
      elsif h_sector < 2 then [x, c, 0.0]
      elsif h_sector < 3 then [0.0, c, x]
      elsif h_sector < 4 then [0.0, x, c]
      elsif h_sector < 5 then [x, 0.0, c]
      else [c, 0.0, x]
      end

    r = ((r1 + m) * 255).round
    g = ((g1 + m) * 255).round
    b = ((b1 + m) * 255).round

    "#%02x%02x%02x" % [r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255)]
  end

  def fmod(a, b)
    a - b * (a / b).floor
  end
end
