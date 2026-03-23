# frozen_string_literal: true

# App rating page for Plushie.
#
# Demonstrates custom canvas widgets (star rating, theme toggle) composed
# with styled containers using the full DSL. The "Dark humor" toggle
# animates and flips the entire page theme.

require "plushie"
require_relative "widgets/star_rating"
require_relative "widgets/theme_toggle"

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
    in Event::Widget[type: :canvas_element_click, id: "stars", data:]
      n = parse_star_index(data)
      n ? model.with(rating: n + 1) : model

    in Event::Widget[type: :canvas_element_enter, id: "stars", data:]
      n = parse_star_index(data)
      n ? model.with(hover_star: n + 1) : model

    in Event::Widget[type: :canvas_element_leave, id: "stars"]
      model.with(hover_star: nil)

    in Event::Widget[type: :canvas_element_focused, id: "stars", data:]
      n = parse_star_index(data)
      n ? model.with(focused_star: n) : model

    # Theme toggle
    in Event::Widget[type: :canvas_element_click, id: "theme-toggle"]
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
    element_id = data && data["element_id"]
    return nil unless element_id.is_a?(String) && element_id.start_with?("star-")

    element_id.delete_prefix("star-").to_i
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

        StarRating.render("stars", model.rating,
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
      ThemeToggle.render("theme-toggle", model.toggle_progress)
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
        StarRating.render("rstars-#{i}", review[:stars],
          readonly: true, scale: 0.4, theme_progress: p)
        text("rname-#{i}", review[:user], size: 12, color: t[:text_secondary])
        space("rsp-#{i}", width: :fill)
        text("rtime-#{i}", review[:time], size: 12, color: t[:text_muted])
      end

      text("rtext-#{i}", "\u201C#{review[:text]}\u201D", size: 14, color: t[:text])
    end
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
end

Plushie.run(RatePlushie) if __FILE__ == $PROGRAM_NAME
