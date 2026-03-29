# frozen_string_literal: true

require "plushie"

# Animated theme toggle with a face on the thumb.
#
# A toggle switch where the thumb has a drawn face. Light mode shows a
# smiley; dark mode shows the face rotated upside down. The face rotates
# during the transition. Animation is managed internally.
#
#   ThemeToggle.new("my-toggle").build
#
# Events:
# - :toggle with {value: bool} when the user clicks the switch
class ThemeToggle
  include Plushie::Widget

  widget :theme_toggle

  state :progress, default: 0.0
  state :target, default: 0.0

  event :toggle

  TRACK_W = 64
  TRACK_H = 32
  THUMB_R = 13

  def self.init
    {progress: 0.0, target: 0.0}
  end

  # -- Event transformation --------------------------------------------------

  def self.handle_event(event, state)
    case event
    in Event::Widget[type: :canvas_element_click, data: {element_id: "switch", **}]
      new_target = (state[:target] == 0.0) ? 1.0 : 0.0
      [:emit, :toggle, new_target >= 0.5, {progress: state[:progress], target: new_target}]

    in Event::Timer[tag: :animate]
      new_progress = approach(state[:progress], state[:target], 0.06)
      [:update_state, {progress: new_progress, target: state[:target]}]

    else
      [:consumed, state]
    end
  end

  # -- Widget-scoped subscriptions -------------------------------------------

  def self.subscribe(_props, state)
    if state[:progress] != state[:target]
      [Plushie::Subscription.every(16, :animate)]
    else
      []
    end
  end

  # -- Rendering -------------------------------------------------------------

  def self.render(id, _props, state)
    include Plushie::UI

    progress = state[:progress]
    eased = smoothstep(progress)
    thumb_x = lerp(TRACK_H / 2.0, TRACK_W - TRACK_H / 2.0, eased)
    track_color = lerp_color([253, 230, 138], [91, 33, 182], eased)
    rotation = eased * Math::PI
    face_color = (progress < 0.5) ? "#665500" : "#4c1d95"

    ring_pad = 4

    canvas(id,
      width: TRACK_W + ring_pad * 2,
      height: TRACK_H + ring_pad * 2,
      alt: "Theme toggle") do
      layer("toggle") do
        canvas_group("switch",
          x: ring_pad,
          y: ring_pad,
          on_click: true,
          cursor: "pointer",
          hit_rect: {x: 0, y: 0, w: TRACK_W, h: TRACK_H},
          focus_ring_radius: TRACK_H / 2 + ring_pad,
          a11y: {role: :switch, label: "Dark humor", toggled: progress >= 0.5}) do
          canvas_rect(0, 0, TRACK_W, TRACK_H, fill: track_color, radius: TRACK_H / 2)
          canvas_circle(thumb_x, TRACK_H / 2.0, THUMB_R, fill: "#ffffff")

          canvas_group(transforms: [
            Plushie::Canvas::Shape.translate(thumb_x, TRACK_H / 2.0),
            Plushie::Canvas::Shape.rotate(rotation)
          ]) do
            canvas_circle(-3.5, -3, 2, fill: face_color)
            canvas_circle(3.5, -3, 2, fill: face_color)
            canvas_path(smile_path, stroke: Plushie::Canvas::Shape.stroke(face_color, 2))
          end
        end
      end
    end
  end

  def self.approach(current, target, step)
    if current < target
      [current + step, target].min
    elsif current > target
      [current - step, target].max
    else
      current
    end
  end

  def self.smoothstep(t)
    return 0.0 if t <= 0.0
    return 1.0 if t >= 1.0

    t * t * (3 - 2 * t)
  end

  def self.lerp(a, b, t)
    a + (b - a) * t
  end

  def self.lerp_color(rgb1, rgb2, t)
    r = lerp(rgb1[0], rgb2[0], t).round
    g = lerp(rgb1[1], rgb2[1], t).round
    b = lerp(rgb1[2], rgb2[2], t).round
    "#%02x%02x%02x" % [r, g, b]
  end

  def self.smile_path
    [
      Plushie::Canvas::Shape.move_to(-5, 1),
      Plushie::Canvas::Shape.line_to(-3, 5),
      Plushie::Canvas::Shape.line_to(3, 5),
      Plushie::Canvas::Shape.line_to(5, 1)
    ]
  end

  private_class_method :approach, :smoothstep, :lerp, :lerp_color, :smile_path
end
