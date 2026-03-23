# frozen_string_literal: true

# App rating page for Plushie.
#
# Demonstrates custom canvas widgets (star rating, theme toggle) composed
# with styled containers using the full DSL. The "Dark humor" toggle
# animates and flips the entire page theme.

require "plushie"

class RatePlushie
  include Plushie::App

  INITIAL_REVIEWS = [
    {stars: 5, user: "elixir_fan_42", time: "2d ago",
     text: "Finally, native GUIs that don't make me want to cry."},
    {stars: 5, user: "beam_me_up", time: "3d ago",
     text: "The Elm architecture feels right at home here."},
    {stars: 4, user: "rustacean", time: "5d ago",
     text: "Solid Iced wrapper. Docked a star because I had to write Elixir."},
    {stars: 3, user: "web_refugee", time: "1w ago",
     text: "Where is my CSS grid? Also it works perfectly. Three stars."},
    {stars: 5, user: "otp_enjoyer", time: "1w ago",
     text: "Let it crash, but make it beautiful."},
    {stars: 1, user: "electron_mass", time: "2w ago",
     text: "No browser engine. No JavaScript runtime. What am I even paying for?"}
  ].freeze

  Model = Plushie::Model.define(
    :rating, :hover_star, :focused_star,
    :toggle_progress, :toggle_target,
    :reviews, :review_name, :review_comment
  )

  # -- Init / Update / Subscribe -----------------------------------------------

  def init(_opts)
    Model.new(
      rating: 0,
      hover_star: nil,
      focused_star: nil,
      toggle_progress: 0.0,
      toggle_target: 0.0,
      reviews: INITIAL_REVIEWS,
      review_name: "",
      review_comment: ""
    )
  end

  def update(model, event)
    case event
    # Star rating interactions
    in Event::Widget[type: :canvas_shape_click, id: "stars", data:]
      n = parse_star_index(data)
      n ? model.with(rating: n + 1) : model

    in Event::Widget[type: :canvas_shape_enter, id: "stars", data:]
      n = parse_star_index(data)
      n ? model.with(hover_star: n + 1) : model

    in Event::Widget[type: :canvas_shape_leave, id: "stars"]
      model.with(hover_star: nil)

    in Event::Widget[type: :canvas_shape_focused, id: "stars", data:]
      n = parse_star_index(data)
      n ? model.with(focused_star: n) : model

    # Theme toggle
    in Event::Widget[type: :canvas_shape_click, id: "theme-toggle"]
      target = (model.toggle_target == 0.0) ? 1.0 : 0.0
      model.with(toggle_target: target)

    # Review form
    in Event::Widget[type: :input, id: "review-name", value:]
      model.with(review_name: value)

    in Event::Widget[type: :input, id: "review-comment", value:]
      model.with(review_comment: value)

    in Event::Widget[type: :click, id: "submit-review"]
      submit_review(model)

    in Event::Widget[type: :submit, id: "review-name"]
      submit_review(model)

    # Animation
    in Event::Timer[tag: :animate]
      model.with(toggle_progress: approach(model.toggle_progress, model.toggle_target, 0.06))

    else
      model
    end
  end

  def subscribe(model)
    if model.toggle_progress != model.toggle_target
      [Subscription.every(16, :animate)]
    else
      []
    end
  end

  # -- View (composed from helper methods) -------------------------------------

  def view(model)
    p = smoothstep(model.toggle_progress)
    t = theme(p)

    window("main", title: "Rate Plushie") do
      container("page",
        padding: {top: 32, bottom: 32, left: 24, right: 24},
        background: t[:page_bg],
        width: :fill, height: :fill) do
        column(spacing: 24, width: :fill) do
          text("heading", "Rate Plushie", size: 28, color: t[:text])
          rating_card(model, p, t)
          text("reviews-heading", "Reviews", size: 20, color: t[:text])
          reviews_list(model.reviews, p, t)
        end
      end
    end
  end

  private

  def parse_star_index(data)
    shape_id = data && data["shape_id"]
    return nil unless shape_id.is_a?(String) && shape_id.start_with?("star-")

    shape_id.delete_prefix("star-").to_i
  end

  def submit_review(model)
    name = model.review_name.strip
    comment = model.review_comment.strip

    if !name.empty? && !comment.empty? && model.rating > 0
      review = {stars: model.rating, user: name, time: "just now", text: comment}
      model.with(reviews: [review, *model.reviews], review_name: "", review_comment: "", rating: 0)
    else
      model
    end
  end

  # -- View: rating card -------------------------------------------------------

  def rating_card(model, p, t)
    container("rating-card",
      padding: 24, width: :fill,
      border: {width: 1, color: t[:card_border], rounded: 12},
      background: t[:card_bg]) do
      column(spacing: 20) do
        text("prompt", "How would you rate Plushie?", size: 14, color: t[:text_secondary])

        star_rating_canvas("stars", model.rating,
          hover: model.hover_star, focused: model.focused_star,
          theme_progress: p)

        rule
        review_form(model, t)
        theme_row(model, t)
      end
    end
  end

  # -- View: review form -------------------------------------------------------

  def review_form(model, _t)
    column("review-form", spacing: 12, width: :fill) do
      text_input("review-name", model.review_name, placeholder: "Your name")
      text_editor("review-comment", model.review_comment,
        placeholder: "Write your review...", height: 80)
      button("submit-review", "Submit Review")
    end
  end

  # -- View: theme toggle row --------------------------------------------------

  def theme_row(model, t)
    row("theme-row", align_y: :center) do
      space("theme-spacer", width: :fill)
      text("toggle-label", "Dark humor", color: t[:text_secondary])
      theme_toggle_canvas("theme-toggle", model.toggle_progress)
    end
  end

  # -- View: reviews list ------------------------------------------------------

  def reviews_list(reviews, p, t)
    column("reviews", spacing: 0, width: :fill) do
      reviews.each_with_index do |review, i|
        rule("sep-#{i}") if i > 0
        review_card(review, i, p, t)
      end
    end
  end

  def review_card(review, i, p, t)
    column("review-#{i}", spacing: 4, padding: 12, width: :fill) do
      row("rhdr-#{i}", spacing: 8, align_y: :center) do
        star_rating_canvas("rstars-#{i}", review[:stars],
          readonly: true, scale: 0.4, theme_progress: p)
        text("rname-#{i}", review[:user], size: 12, color: t[:text_secondary])
        space("rsp-#{i}", width: :fill)
        text("rtime-#{i}", review[:time], size: 12, color: t[:text_muted])
      end

      text("rtext-#{i}", "\u201C#{review[:text]}\u201D", size: 14, color: t[:text])
    end
  end

  # -- Star rating canvas widget -----------------------------------------------

  def star_rating_canvas(id, rating, hover: nil, focused: nil, theme_progress: 0.0, readonly: false, scale: 1.0)
    outer_r = 13 * scale
    inner_r = 5 * scale
    size = (30 * scale).round
    gap = (2 * scale).round
    display = hover || rating
    width = 5 * size + 4 * gap
    focus_r = outer_r + 3 * scale

    commands = star_commands(outer_r, inner_r)

    canvas(id, width: width, height: size) do
      layer("stars") do
        5.times do |i|
          star_cx = i * (size + gap) + size / 2
          star_cy = size / 2
          filled = i < display
          preview = !readonly && !hover.nil? && i < hover && i >= rating
          is_focused = !readonly && focused == i

          interactive_wire = unless readonly
            Plushie::Canvas::Shape::Interactive.new(
              id: "star-#{i}",
              on_click: true,
              on_hover: true,
              cursor: "pointer",
              a11y: {role: :button, label: "#{i + 1} star#{"s" unless i == 0}"}
            ).to_wire
          end

          canvas_group(x: star_cx, y: star_cy, interactive: interactive_wire) do
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

  # -- Theme toggle canvas widget ----------------------------------------------

  TRACK_W = 64
  TRACK_H = 32
  THUMB_R = 13

  def theme_toggle_canvas(id, progress)
    eased = smoothstep(progress)
    thumb_x = lerp(TRACK_H / 2.0, TRACK_W - TRACK_H / 2.0, eased)
    track_color = lerp_color([253, 230, 138], [91, 33, 182], eased)
    rotation = eased * Math::PI
    face_color = (progress < 0.5) ? "#665500" : "#4c1d95"

    canvas(id, width: TRACK_W, height: TRACK_H) do
      layer("toggle") do
        interactive_wire = Plushie::Canvas::Shape::Interactive.new(
          id: "switch",
          on_click: true,
          cursor: "pointer",
          hit_rect: Plushie::Canvas::Shape::HitRect.new(x: 0, y: 0, w: TRACK_W, h: TRACK_H),
          a11y: {role: :switch, label: "Dark humor"}
        ).to_wire

        canvas_group(interactive: interactive_wire) do
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

          # Face with transform (push, translate, rotate, shapes, pop)
          _plushie_add_canvas_shape(Plushie::Canvas::Shape::PushTransform.new)
          _plushie_add_canvas_shape(Plushie::Canvas::Shape::Translate.new(x: thumb_x, y: TRACK_H / 2.0))
          _plushie_add_canvas_shape(Plushie::Canvas::Shape::Rotate.new(angle: rotation))

          # Left eye
          canvas_circle(-3.5, -3, 2, fill: face_color)
          # Right eye
          canvas_circle(3.5, -3, 2, fill: face_color)
          # Mouth (smile path)
          canvas_path(smile_path, stroke: Plushie::Canvas::Shape.stroke(face_color, 2))

          _plushie_add_canvas_shape(Plushie::Canvas::Shape::PopTransform.new)
        end
      end
    end
  end

  def smile_path
    [
      Plushie::Canvas::Shape.move_to(-5, 1),
      Plushie::Canvas::Shape.line_to(-3, 5),
      Plushie::Canvas::Shape.line_to(3, 5),
      Plushie::Canvas::Shape.line_to(5, 1)
    ]
  end

  # -- Theme interpolation -----------------------------------------------------

  def theme(p)
    {
      page_bg: fade([248, 248, 250], [19, 19, 31], p),
      card_bg: fade([255, 255, 255], [28, 28, 50], p),
      card_border: fade([224, 224, 224], [42, 42, 74], p),
      text: fade([26, 26, 26], [240, 240, 245], p),
      text_secondary: fade([102, 102, 102], [153, 153, 187], p),
      text_muted: fade([170, 170, 170], [85, 85, 119], p)
    }
  end

  def fade(rgb1, rgb2, t)
    r = (rgb1[0] + (rgb2[0] - rgb1[0]) * t).round
    g = (rgb1[1] + (rgb2[1] - rgb1[1]) * t).round
    b = (rgb1[2] + (rgb2[2] - rgb1[2]) * t).round
    "#%02x%02x%02x" % [r, g, b]
  end

  def smoothstep(t)
    return 0.0 if t <= 0.0
    return 1.0 if t >= 1.0

    t * t * (3 - 2 * t)
  end

  def approach(current, target, step)
    if current < target
      [current + step, target].min
    elsif current > target
      [current - step, target].max
    else
      current
    end
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
end

Plushie.run(RatePlushie) if __FILE__ == $PROGRAM_NAME
