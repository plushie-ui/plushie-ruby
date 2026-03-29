# frozen_string_literal: true

require "plushie"

# Canvas-based star rating widget.
#
# Renders 5 stars as a radio group. Interactive by default (click to
# rate, hover to preview, Tab/arrow to navigate, Enter/Space to select).
# Pass readonly: true for a display-only version.
#
#   StarRating.new("my-rating", rating: model.rating, theme_progress: p).build
#   StarRating.new("review-stars", rating: 4, readonly: true, scale: 0.5).build
#
# Events:
# - :select with {value: n} when the user clicks a star
class StarRating
  include Plushie::Widget

  widget :star_rating

  prop :rating, :number, default: 0
  prop :readonly, :boolean, default: false
  prop :scale, :number, default: 1.0
  prop :theme_progress, :number, default: 0.0

  state :hover, default: nil

  event :select

  STAR_COUNT = 5

  def self.init = {hover: nil}

  # -- Event transformation --------------------------------------------------

  def self.handle_event(event, state)
    case event
    in Event::Widget[type: :canvas_element_click, data:]
      n = parse_star_index(data)
      n ? [:emit, :select, n + 1] : [:consumed, state]

    in Event::Widget[type: :canvas_element_enter, data:]
      n = parse_star_index(data)
      n ? [:update_state, {hover: n + 1}] : [:consumed, state]

    in Event::Widget[type: :canvas_element_leave]
      [:update_state, {hover: nil}]

    else
      [:consumed, state]
    end
  end

  # -- Rendering -------------------------------------------------------------

  def self.render(id, props, state)
    include Plushie::UI

    rating = props[:rating] || 0
    readonly = props[:readonly] || false
    scale = props[:scale] || 1.0
    theme_progress = props[:theme_progress] || 0.0

    outer_r = 13 * scale
    inner_r = 5 * scale
    size = (30 * scale).round
    gap = (2 * scale).round
    hover = state[:hover]
    display = hover || rating
    width = STAR_COUNT * size + (STAR_COUNT - 1) * gap

    commands = star_commands(outer_r, inner_r)

    if readonly
      canvas(id, width: width, height: size,
        alt: "#{rating} out of #{STAR_COUNT} stars") do
        layer("stars") do
          STAR_COUNT.times do |i|
            canvas_group(x: i * (size + gap) + size / 2, y: size / 2) do
              canvas_path(commands, fill: star_color(i < rating, false, theme_progress))
            end
          end
        end
      end
    else
      canvas(id, width: width, height: size,
        alt: "Star rating", role: "radiogroup") do
        layer("stars") do
          STAR_COUNT.times do |i|
            filled = i < display
            preview = !hover.nil? && i < hover && i >= rating

            canvas_group("star-#{i}",
              x: i * (size + gap) + size / 2,
              y: size / 2,
              on_click: true,
              on_hover: true,
              cursor: "pointer",
              focus_style: {stroke: {color: "#3b82f6", width: 2 * scale}},
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

  def self.parse_star_index(data)
    element_id = data && (data[:element_id] || data["element_id"])
    return nil unless element_id.is_a?(String) && element_id.start_with?("star-")

    element_id.delete_prefix("star-").to_i
  end

  def self.star_commands(outer_r, inner_r)
    points = (0..9).map do |i|
      angle = i * Math::PI / 5 - Math::PI / 2
      r = i.even? ? outer_r : inner_r
      [r * Math.cos(angle), r * Math.sin(angle)]
    end

    fx, fy = points.first
    rest = points[1..].map { |x, y| Plushie::Canvas::Shape.line_to(x, y) }
    [Plushie::Canvas::Shape.move_to(fx, fy), *rest, Plushie::Canvas::Shape.close]
  end

  def self.star_color(filled, preview, progress)
    if preview
      fade([255, 200, 50], [200, 160, 80], progress)
    elsif filled
      fade([255, 180, 0], [255, 200, 50], progress)
    else
      fade([224, 224, 224], [60, 60, 80], progress)
    end
  end

  def self.fade(rgb1, rgb2, t)
    r = (rgb1[0] + (rgb2[0] - rgb1[0]) * t).round
    g = (rgb1[1] + (rgb2[1] - rgb1[1]) * t).round
    b = (rgb1[2] + (rgb2[2] - rgb1[2]) * t).round
    "#%02x%02x%02x" % [r, g, b]
  end

  private_class_method :parse_star_index, :star_commands, :star_color, :fade
end
