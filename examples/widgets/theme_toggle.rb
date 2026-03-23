# frozen_string_literal: true

require "plushie"

# Canvas-based theme toggle switch.
#
# Renders an animated toggle with a sun/moon face that rotates during
# the transition. The progress value (0.0 = light, 1.0 = dark) drives
# all interpolation -- the caller is responsible for animating it.
#
#   ThemeToggle.render("theme-toggle", model.toggle_progress)
#
# Events:
# - canvas_element_click with element_id "switch"
module ThemeToggle
  include Plushie::UI
  extend self

  TRACK_W = 64
  TRACK_H = 32
  THUMB_R = 13

  def render(id, progress)
    eased = smoothstep(progress)
    thumb_x = lerp(TRACK_H / 2.0, TRACK_W - TRACK_H / 2.0, eased)
    track_color = lerp_color([253, 230, 138], [91, 33, 182], eased)
    rotation = eased * Math::PI
    face_color = (progress < 0.5) ? "#665500" : "#4c1d95"

    canvas(id, width: TRACK_W, height: TRACK_H) do
      layer("toggle") do
        canvas_group("switch",
          on_click: true,
          cursor: "pointer",
          hit_rect: Plushie::Canvas::Shape::HitRect.new(x: 0, y: 0, w: TRACK_W, h: TRACK_H),
          a11y: {role: :switch, label: "Dark humor"}) do
          # Track (rounded rect via path since canvas_rect has no radius)
          r = TRACK_H / 2.0
          canvas_path([
            Plushie::Canvas::Shape.move_to(r, 0),
            Plushie::Canvas::Shape.line_to(TRACK_W - r, 0),
            Plushie::Canvas::Shape.arc(TRACK_W - r, r, r, -Math::PI / 2, Math::PI / 2),
            Plushie::Canvas::Shape.line_to(r, TRACK_H),
            Plushie::Canvas::Shape.arc(r, r, r, Math::PI / 2, 3 * Math::PI / 2)
          ], fill: track_color)

          # Thumb circle
          canvas_circle(thumb_x, TRACK_H / 2.0, THUMB_R, fill: "#ffffff")

          # Face -- nested group with transforms instead of push/pop
          canvas_group(transforms: [
            Plushie::Canvas::Shape.translate(thumb_x, TRACK_H / 2.0),
            Plushie::Canvas::Shape.rotate(rotation)
          ]) do
            # Left eye
            canvas_circle(-3.5, -3, 2, fill: face_color)
            # Right eye
            canvas_circle(3.5, -3, 2, fill: face_color)
            # Mouth (smile path)
            canvas_path(smile_path, stroke: Plushie::Canvas::Shape.stroke(face_color, 2))
          end
        end
      end
    end
  end

  private

  def smoothstep(t)
    return 0.0 if t <= 0.0
    return 1.0 if t >= 1.0

    t * t * (3 - 2 * t)
  end

  def lerp(a, b, t)
    a + (b - a) * t
  end

  def lerp_color(rgb1, rgb2, t)
    r = lerp(rgb1[0], rgb2[0], t).round
    g = lerp(rgb1[1], rgb2[1], t).round
    b = lerp(rgb1[2], rgb2[2], t).round
    "#%02x%02x%02x" % [r, g, b]
  end

  def smile_path
    [
      Plushie::Canvas::Shape.move_to(-5, 1),
      Plushie::Canvas::Shape.line_to(-3, 5),
      Plushie::Canvas::Shape.line_to(3, 5),
      Plushie::Canvas::Shape.line_to(5, 1)
    ]
  end
end
