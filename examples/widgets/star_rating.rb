# frozen_string_literal: true

require "plushie"

# Canvas-based star rating widget.
#
# Renders 5 stars as a radio group. Interactive by default (click to
# rate, hover to preview, Tab/arrow to navigate, Enter/Space to select).
# Pass readonly: true for a display-only version.
#
#   StarRating.render("my-rating", model.rating,
#     hover: model.hover_star, focused: model.focused_star,
#     theme_progress: p)
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

    commands = star_commands(outer_r, inner_r)

    canvas_opts = {width: width, height: size}
    if readonly
      canvas_opts[:alt] = "#{rating} out of #{STAR_COUNT} stars"
      canvas_opts[:role] = "img"
    else
      canvas_opts[:role] = "radiogroup"
      canvas_opts[:arrow_mode] = "wrap"
    end

    canvas(id, **canvas_opts) do
      layer("stars") do
        STAR_COUNT.times do |i|
          star_cx = i * (size + gap) + size / 2
          star_cy = size / 2
          filled = i < display
          preview = !readonly && !hover.nil? && i < hover && i >= rating

          if readonly
            canvas_group(x: star_cx, y: star_cy) do
              canvas_path(commands, fill: star_color(filled, preview, theme_progress))
            end
          else
            canvas_group("star-#{i}",
              x: star_cx, y: star_cy,
              on_click: true,
              on_hover: true,
              cursor: "pointer",
              focus_style: {stroke: "#3b82f6", stroke_width: 2 * scale},
              show_focus_ring: false,
              a11y: {
                role: :radio,
                label: "#{i + 1} star#{"s" unless i == 0}",
                selected: rating >= i + 1,
                position_in_set: i + 1,
                size_of_set: STAR_COUNT
              }) do
              canvas_path(commands, fill: star_color(filled, preview, theme_progress))
            end
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
