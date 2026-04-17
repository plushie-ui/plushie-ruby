# frozen_string_literal: true

require "test_helper"
require "plushie/test/helpers"

class TestResolvedA11y < Minitest::Test
  H = Plushie::Test::Helpers

  def test_text_input_placeholder_seeds_description
    element = {type: "text_input", props: {placeholder: "Search..."}}
    assert_equal({description: "Search..."}, H.resolve_a11y_for_element(element))
  end

  def test_image_alt_seeds_label
    element = {type: "image", props: {alt: "Tree"}}
    assert_equal({label: "Tree"}, H.resolve_a11y_for_element(element))
  end

  def test_explicit_a11y_composes_with_inferred
    element = {
      type: "text_input",
      props: {
        placeholder: "Search...",
        a11y: {label: "Search box", required: true}
      }
    }
    resolved = H.resolve_a11y_for_element(element)
    assert_equal "Search...", resolved[:description]
    assert_equal "Search box", resolved[:label]
    assert_equal true, resolved[:required]
  end

  def test_explicit_description_overrides_inferred
    element = {
      type: "text_input",
      props: {
        placeholder: "Search...",
        a11y: {description: "Enter a query"}
      }
    }
    assert_equal "Enter a query", H.resolve_a11y_for_element(element)[:description]
  end

  def test_blank_placeholder_treated_as_absent
    element = {type: "text_input", props: {placeholder: ""}}
    assert_equal({}, H.resolve_a11y_for_element(element))
  end

  def test_widgets_without_inference_return_empty
    element = {type: "text", props: {content: "hi"}}
    assert_equal({}, H.resolve_a11y_for_element(element))
  end

  def test_accepts_string_keyed_props
    element = {"type" => "text_input", "props" => {"placeholder" => "Search..."}}
    assert_equal({description: "Search..."}, H.resolve_a11y_for_element(element))
  end
end
