# frozen_string_literal: true

# App rating page for Plushie.
#
# Demonstrates custom canvas widgets (StarRating, ThemeToggle) composed
# with styled containers using the full DSL. The "Dark humor" toggle
# animates the emoji and flips the entire page theme.
#
# The review form showcases form validation with:
# - Per-field error state tracked in the model
# - Visual error styling via StyleMap (border + background tint)
# - Accessible error wiring via a11y (required, invalid, error_message)
# - Validate-on-submit with clear-on-change for responsive UX

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
    :rating, :dark_mode,
    :reviews, :review_name, :review_comment, :errors
  )

  # -- Init / Update / Subscribe -----------------------------------------------

  def init(_opts)
    Model.new(
      rating: 0,
      dark_mode: false,
      reviews: INITIAL_REVIEWS,
      review_name: "",
      review_comment: "",
      errors: {}
    )
  end

  def update(model, event)
    case event
    # Star rating emits :select with the number of stars.
    in Event::Widget[type: :select, id: "stars", data:]
      stars = data["value"]
      model.with(rating: stars, errors: model.errors.except(:rating))

    # Theme toggle emits :toggle with the new state.
    in Event::Widget[type: :toggle, id: "theme-toggle", data:]
      model.with(dark_mode: data["value"])

    in Event::Widget[type: :input, id: "review-name", value:]
      model.with(review_name: value, errors: model.errors.except(:name))

    in Event::Widget[type: :input, id: "review-comment", value:]
      model.with(review_comment: value, errors: model.errors.except(:comment))

    in Event::Widget[type: :click, id: "submit-review"]
      submit_review(model)

    in Event::Widget[type: :submit, id: "review-name"]
      submit_review(model)

    else
      model
    end
  end

  def subscribe(_model)
    []
  end

  # -- View ------------------------------------------------------------------

  def view(model)
    p = model.dark_mode ? 1.0 : 0.0
    t = theme(p)

    page_theme = Plushie::Type::Theme.custom("rate-plushie",
      background: t[:page_bg],
      text: t[:text],
      primary: fade([59, 130, 246], [139, 92, 246], p))

    window("main", title: "Rate Plushie") do
      themer("page-theme", theme: page_theme) do
        container("page",
          padding: {top: 32, bottom: 32, left: 24, right: 24},
          background: t[:page_bg],
          width: :fill, height: :fill) do
          column(spacing: 24, width: :fill) do
            text("heading", "Rate Plushie", size: 28, color: t[:text],
              a11y: {role: :heading, level: 1})
            rating_card(model, p, t)
            text("reviews-heading", "Reviews", size: 20, color: t[:text],
              a11y: {role: :heading, level: 2})
            reviews_list(model.reviews, p, t)
          end
        end
      end
    end
  end

  private

  def submit_review(model)
    errors = validate_review(model)

    if errors.empty?
      name = model.review_name.strip
      comment = model.review_comment.strip
      review = {stars: model.rating, user: name, time: "just now", text: comment}

      model.with(
        reviews: [review, *model.reviews],
        review_name: "", review_comment: "",
        rating: 0, errors: {}
      )
    else
      model.with(errors: errors)
    end
  end

  def validate_review(model)
    errors = {}
    errors[:name] = "Name is required" if model.review_name.strip.empty?
    errors[:comment] = "Review text is required" if model.review_comment.strip.empty?
    errors[:rating] = "Please select a rating" if model.rating <= 0
    errors
  end

  # -- View: rating card -----------------------------------------------------

  def rating_card(model, p, t)
    container("rating-card",
      padding: 24, width: :fill,
      border: {width: 1, color: t[:card_border], rounded: 12},
      background: t[:card_bg]) do
      column(spacing: 20, width: :fill) do
        text("prompt", "How would you rate Plushie?", size: 14, color: t[:text_secondary])

        column("stars-group", spacing: 4) do
          StarRating.new("stars", rating: model.rating, theme_progress: p)

          if (error = model.errors[:rating])
            text("stars-error", error,
              size: 12, color: t[:error_text],
              a11y: {role: :alert, live: :polite})
          end
        end

        rule
        review_form(model, t)
        theme_row(model, t)
      end
    end
  end

  # -- View: review form -----------------------------------------------------

  def review_form(model, t)
    column("review-form", spacing: 12, width: :fill) do
      column("name-field", spacing: 4, width: :fill) do
        text_input("review-name", model.review_name,
          placeholder: "Your name", on_submit: true,
          style: input_style(model.errors[:name], t),
          a11y: {
            label: "Your name",
            required: true,
            invalid: !model.errors[:name].nil?,
            error_message: model.errors[:name] ? "review-name-error" : nil
          })

        if (error = model.errors[:name])
          text("review-name-error", error,
            size: 12, color: t[:error_text],
            a11y: {role: :alert, live: :polite})
        end
      end

      column("comment-field", spacing: 4, width: :fill) do
        text_editor("review-comment", model.review_comment,
          placeholder: "Write your review...", height: 80,
          style: input_style(model.errors[:comment], t),
          a11y: {
            label: "Review text",
            required: true,
            invalid: !model.errors[:comment].nil?,
            error_message: model.errors[:comment] ? "review-comment-error" : nil
          })

        if (error = model.errors[:comment])
          text("review-comment-error", error,
            size: 12, color: t[:error_text],
            a11y: {role: :alert, live: :polite})
        end
      end

      button("submit-review", "Submit Review")
    end
  end

  def input_style(error, t)
    return :default unless error

    error_border = Plushie::Type::Border.new(
      color: t[:error_border], width: 2, rounded: 4
    )

    Plushie::Type::StyleMap.new(
      border: error_border,
      background: t[:error_bg],
      focused: {border: error_border}
    )
  end

  # -- View: theme toggle row ------------------------------------------------

  def theme_row(_model, t)
    row("theme-row", align_y: :center) do
      space("theme-spacer", width: :fill)
      text("toggle-label", "Dark humor", color: t[:text_secondary])
      ThemeToggle.new("theme-toggle")
    end
  end

  # -- View: reviews list ----------------------------------------------------

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
        StarRating.new("rstars-#{i}", rating: review[:stars], readonly: true, scale: 0.4, theme_progress: p)
        text("rname-#{i}", review[:user], size: 12, color: t[:text_secondary])
        space("rsp-#{i}", width: :fill)
        text("rtime-#{i}", review[:time], size: 12, color: t[:text_muted])
      end

      text("rtext-#{i}", "\u201C#{review[:text]}\u201D", size: 14, color: t[:text])
    end
  end

  # -- Theme -----------------------------------------------------------------

  def theme(p)
    {
      page_bg: fade([248, 248, 250], [19, 19, 31], p),
      card_bg: fade([255, 255, 255], [28, 28, 50], p),
      card_border: fade([224, 224, 224], [42, 42, 74], p),
      text: fade([26, 26, 26], [240, 240, 245], p),
      text_secondary: fade([102, 102, 102], [153, 153, 187], p),
      text_muted: fade([170, 170, 170], [85, 85, 119], p),
      error_text: fade([185, 28, 28], [255, 100, 100], p),
      error_border: fade([220, 38, 38], [255, 80, 80], p),
      error_bg: fade([254, 242, 242], [50, 20, 20], p)
    }
  end

  def fade(rgb1, rgb2, t)
    r = (rgb1[0] + (rgb2[0] - rgb1[0]) * t).round
    g = (rgb1[1] + (rgb2[1] - rgb1[1]) * t).round
    b = (rgb1[2] + (rgb2[2] - rgb1[2]) * t).round
    "#%02x%02x%02x" % [r, g, b]
  end
end

Plushie.run(RatePlushie) if __FILE__ == $PROGRAM_NAME
