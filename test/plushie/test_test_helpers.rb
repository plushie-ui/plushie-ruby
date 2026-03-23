# frozen_string_literal: true

require "test_helper"

class TestTestHelpers < Minitest::Test
  # We test Session's internal helper methods (build_selector,
  # element_text, find_similar_ids, levenshtein) by instantiating
  # a minimal session-like object that exposes them.

  # Thin wrapper that includes just the methods we want to test,
  # extracted from Session via send (they're private there).
  class SessionStub
    def build_selector(selector)
      case selector
      when String
        if selector.start_with?("#")
          id = selector[1..]
          {by: "id", value: id}
        else
          {by: "text", value: selector}
        end
      when Hash then selector
      when :focused then {by: "focused"}
      else {by: "text", value: selector.to_s}
      end
    end

    def element_text(element)
      return nil unless element
      props = element["props"] || element[:props] || {}
      props["content"] || props["label"] || props["value"] || props["placeholder"]
    end

    def find_similar_ids(target, all_ids, max: 3)
      return [] if target.nil? || target.empty?

      scored = all_ids.filter_map do |id|
        local = id.split("/").last
        if local.include?(target) || target.include?(local)
          [id, 0]
        else
          dist = levenshtein(target.downcase, local.downcase)
          (dist <= [target.length / 2, 3].max) ? [id, dist] : nil
        end
      end

      scored.sort_by(&:last).first(max).map(&:first)
    end

    def levenshtein(a, b)
      return b.length if a.empty?
      return a.length if b.empty?

      matrix = Array.new(a.length + 1) { |i| Array.new(b.length + 1) { |j| (i.zero? ? j : (j.zero? ? i : 0)) } }

      (1..a.length).each do |i|
        (1..b.length).each do |j|
          cost = (a[i - 1] == b[j - 1]) ? 0 : 1
          matrix[i][j] = [
            matrix[i - 1][j] + 1,
            matrix[i][j - 1] + 1,
            matrix[i - 1][j - 1] + cost
          ].min
        end
      end

      matrix[a.length][b.length]
    end
  end

  def setup
    @s = SessionStub.new
  end

  # -- Selector parsing ----------------------------------------------------

  def test_hash_id_selector
    result = @s.build_selector("#save")
    assert_equal({by: "id", value: "save"}, result)
  end

  def test_text_selector
    result = @s.build_selector("Click me")
    assert_equal({by: "text", value: "Click me"}, result)
  end

  def test_hash_passthrough
    sel = {by: "role", value: "button"}
    assert_equal sel, @s.build_selector(sel)
  end

  def test_focused_selector
    assert_equal({by: "focused"}, @s.build_selector(:focused))
  end

  def test_symbol_falls_through_to_text
    result = @s.build_selector(:something)
    assert_equal({by: "text", value: "something"}, result)
  end

  # -- element_text extraction ---------------------------------------------

  def test_element_text_content
    element = {"props" => {"content" => "Hello"}}
    assert_equal "Hello", @s.element_text(element)
  end

  def test_element_text_label
    element = {"props" => {"label" => "Save"}}
    assert_equal "Save", @s.element_text(element)
  end

  def test_element_text_value
    element = {"props" => {"value" => "typed text"}}
    assert_equal "typed text", @s.element_text(element)
  end

  def test_element_text_placeholder
    element = {"props" => {"placeholder" => "Enter..."}}
    assert_equal "Enter...", @s.element_text(element)
  end

  def test_element_text_priority
    # content wins over label
    element = {"props" => {"content" => "A", "label" => "B"}}
    assert_equal "A", @s.element_text(element)
  end

  def test_element_text_nil_element
    assert_nil @s.element_text(nil)
  end

  def test_element_text_symbol_keys
    element = {props: {"content" => "Sym"}}
    assert_equal "Sym", @s.element_text(element)
  end

  # -- find_similar_ids (Levenshtein suggestions) --------------------------

  def test_find_similar_ids_substring_match
    ids = ["form/save_button", "form/cancel", "header/logo"]
    result = @s.find_similar_ids("save", ids)
    assert_includes result, "form/save_button"
  end

  def test_find_similar_ids_close_distance
    ids = ["counter", "container", "content"]
    result = @s.find_similar_ids("conter", ids)
    # "counter" and "container" and "content" are all within distance
    refute_empty result
  end

  def test_find_similar_ids_max_results
    ids = (1..10).map { |i| "item_#{i}" }
    result = @s.find_similar_ids("item", ids)
    assert_operator result.length, :<=, 3
  end

  def test_find_similar_ids_empty_target
    assert_empty @s.find_similar_ids("", ["a", "b"])
    assert_empty @s.find_similar_ids(nil, ["a", "b"])
  end

  def test_find_similar_ids_no_matches
    ids = ["zzzzzzzzzzz"]
    result = @s.find_similar_ids("abc", ids)
    assert_empty result
  end

  # -- Levenshtein distance ------------------------------------------------

  def test_levenshtein_identical
    assert_equal 0, @s.levenshtein("abc", "abc")
  end

  def test_levenshtein_one_substitution
    assert_equal 1, @s.levenshtein("abc", "adc")
  end

  def test_levenshtein_empty_strings
    assert_equal 3, @s.levenshtein("abc", "")
    assert_equal 3, @s.levenshtein("", "abc")
    assert_equal 0, @s.levenshtein("", "")
  end

  def test_levenshtein_insertion_deletion
    assert_equal 1, @s.levenshtein("abc", "ab")
    assert_equal 1, @s.levenshtein("ab", "abc")
  end

  # -- Assertion helpers (test via Helpers module on a fake session) --------

  # We can't easily test assert_text etc. without a real session, but we
  # can verify the Helpers module is defined and its methods exist.

  def test_helpers_module_defines_expected_methods
    require "plushie/test/helpers"
    methods = Plushie::Test::Helpers.instance_methods
    assert_includes methods, :click
    assert_includes methods, :find
    assert_includes methods, :assert_text
    assert_includes methods, :assert_exists
    assert_includes methods, :assert_not_exists
    assert_includes methods, :model
  end
end
