# frozen_string_literal: true

require "test_helper"

class DocsAccessibilityTest < Minitest::Test
  include Plushie::UI

  # -- a11y prop with role and label --

  def test_a11y_role_and_label
    tree = button("close", "X", a11y: {label: "Close dialog"})
    assert_equal "button", tree.type
    assert_equal({label: "Close dialog"}, tree.props[:a11y])
  end

  # -- Heading level --

  def test_a11y_heading_level
    tree = text("title", "Welcome to MyApp", a11y: {role: :heading, level: 1})
    assert_equal "text", tree.type
    assert_equal :heading, tree.props[:a11y][:role]
    assert_equal 1, tree.props[:a11y][:level]
  end

  # -- Icon button with label --

  def test_a11y_icon_button_label
    tree = button("close", "X", a11y: {label: "Close dialog"})
    assert_equal "Close dialog", tree.props[:a11y][:label]
  end

  # -- Landmark region --

  def test_a11y_landmark_region
    tree = container("search_results", a11y: {role: :region, label: "Search results"}) do
      text("msg", "No results")
    end
    assert_equal "container", tree.type
    assert_equal :region, tree.props[:a11y][:role]
    assert_equal "Search results", tree.props[:a11y][:label]
    assert_equal "msg", tree.children.first.id
  end

  # -- Live region polite --

  def test_a11y_live_region_polite
    tree = text("save_status", "3 items saved", a11y: {live: :polite})
    assert_equal :polite, tree.props[:a11y][:live]
  end

  # -- Live region assertive --

  def test_a11y_live_region_assertive
    tree = text("error", "Something went wrong", a11y: {live: :assertive, role: :alert})
    assert_equal :assertive, tree.props[:a11y][:live]
    assert_equal :alert, tree.props[:a11y][:role]
  end

  # -- labelled_by reference --

  def test_a11y_labelled_by
    tree = text_input("email", "",
      a11y: {labelled_by: "email-label", described_by: "email-help", error_message: "email-error"})
    a11y = tree.props[:a11y]
    assert_equal "email-label", a11y[:labelled_by]
    assert_equal "email-help", a11y[:described_by]
    assert_equal "email-error", a11y[:error_message]
  end

  # -- Hidden decorative element --

  def test_a11y_hidden_decorative_image
    tree = image("divider", "/images/decorative-line.png", a11y: {hidden: true})
    assert_equal true, tree.props[:a11y][:hidden]
  end

  def test_a11y_hidden_decorative_rule
    tree = rule("divider_rule", a11y: {hidden: true})
    assert_equal "rule", tree.type
    assert_equal true, tree.props[:a11y][:hidden]
  end

  # -- Canvas shape with a11y --

  def test_a11y_canvas_with_alt_text
    tree = canvas("chart",
      layers: {"data" => []},
      a11y: {role: :image, label: "Sales chart: Q1 revenue up 15%, Q2 flat"})
    assert_equal "canvas", tree.type
    assert_equal :image, tree.props[:a11y][:role]
    assert_equal "Sales chart: Q1 revenue up 15%, Q2 flat", tree.props[:a11y][:label]
  end

  # -- Widget-specific alt prop --

  def test_a11y_image_alt_prop
    tree = image("logo", "/images/logo.png", alt: "Company logo")
    assert_equal "Company logo", tree.props[:alt]
  end

  def test_a11y_svg_alt_prop
    tree = svg("icon", "/icons/search.svg", alt: "Search")
    assert_equal "Search", tree.props[:alt]
  end

  def test_a11y_canvas_alt_prop
    tree = canvas("chart", alt: "Revenue chart")
    assert_equal "Revenue chart", tree.props[:alt]
  end
end
