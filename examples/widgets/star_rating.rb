# frozen_string_literal: true

require "plushie"

# Canvas-based star rating widget.
#
# Renders 5 stars as a radio group. Interactive by default (click to
# rate, hover to preview, Tab/arrow to navigate, Enter/Space to select).
# Pass readonly: true for a display-only version.
#
#   StarRating.render("my-rating", model.rating,
#     hover: model.hover_star, theme_progress: p)
#
#   StarRating.render("review-stars", 4, readonly: true, scale: 0.5)
#
# Events:
# - canvas_element_click with element_id "star-0" through "star-4"
# - canvas_element_enter / canvas_element_leave for hover
# - canvas_element_focused with element_id for keyboard focus
module StarRating
  include Plushie::UI
  extend self

  STAR_COUNT = 5

  def render(id, rating, hover: nil, focused: nil, theme_progress: 0.0, readonly: false, scale: 1.0)
    outer_r = 13 * scale
    inner_r = 5 * scale
    size = (30 * scale).round
    gap = (2 * scale).round
    display = hover || rating
    width = STAR_COUNT * size + (STAR_COUNT - 1) * gap
    focus_r = outer_r + 3 * scale

    commands = star_commands(outer_r, inner_r)

    canvas(id, width: width, height: size) do
      layer("stars") do
        STAR_COUNT.times do |i|
          star_cx = i * (size + gap) + size / 2
          star_cy = size / 2
          filled = i < display
          preview = !readonly && !hover.nil? && i < hover && i >= rating
          is_focused = !readonly && focused == i

          group_opts = {x: star_cx, y: star_cy}
          unless readonly
            group_opts.merge!(
              on_click: true,
              on_hover: true,
              cursor: "pointer",
              a11y: {role: :button, label: "#{i + 1} star#{"s" unless i == 0}"}
            )
          end

          canvas_group(readonly ? nil : "star-#{i}", **group_opts) do
            if is_focused
              canvas_circle(0, 0, focus_r,
                stroke: Plushie::Canvas::Shape.stroke("#3b82f6", 2 * scale))
            end
            canvas_path(commands, fill: star_color(filled, preview, theme_progress))
          end
        end
      end
    end
  end

  private

  def star_commands(outer_r, inner_r)
    points = (0..9).map do |i|
      angle = i * Math::PI / 5 - Math::PI / 2
      r = i.even? ? outer_r : inner_r
      [r * Math.cos(angle), r * Math.sin(angle)]
    end

    fx, fy = points.first
    rest = points[1..].map { |x, y| Plushie::Canvas::Shape.line_to(x, y) }
    [Plushie::Canvas::Shape.move_to(fx, fy), *rest, Plushie::Canvas::Shape.close]
  end

  def star_color(filled, preview, progress)
    if filled && !preview
      "#f59e0b"
    elsif preview
      "#fcd34d"
    else
      r = (209 + (74 - 209) * progress).round
      g = (213 + (74 - 213) * progress).round
      b = (219 + (94 - 219) * progress).round
      "#%02x%02x%02x" % [r, g, b]
    end
  end
end
