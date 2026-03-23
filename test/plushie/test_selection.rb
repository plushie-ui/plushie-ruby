# frozen_string_literal: true

require "test_helper"

class TestSelection < Minitest::Test
  S = Plushie::Selection

  # -- Single mode ---------------------------------------------------------

  def test_single_select_replaces
    sel = S.new(mode: :single)
    sel = S.select(sel, "a")
    sel = S.select(sel, "b")
    assert_equal Set["b"], S.selected(sel)
  end

  def test_single_toggle_on
    sel = S.new(mode: :single)
    sel = S.toggle(sel, "a")
    assert S.selected?(sel, "a")
  end

  def test_single_toggle_off
    sel = S.new(mode: :single)
    sel = S.select(sel, "a")
    sel = S.toggle(sel, "a")
    assert_empty S.selected(sel)
  end

  # -- Multi mode ----------------------------------------------------------

  def test_multi_select_replaces_without_extend
    sel = S.new(mode: :multi)
    sel = S.select(sel, "a")
    sel = S.select(sel, "b")
    assert_equal Set["b"], S.selected(sel)
  end

  def test_multi_select_extends
    sel = S.new(mode: :multi)
    sel = S.select(sel, "a")
    sel = S.select(sel, "b", extend: true)
    assert_equal Set["a", "b"], S.selected(sel)
  end

  def test_multi_toggle
    sel = S.new(mode: :multi)
    sel = S.toggle(sel, "a")
    sel = S.toggle(sel, "b")
    assert_equal Set["a", "b"], S.selected(sel)

    sel = S.toggle(sel, "a")
    assert_equal Set["b"], S.selected(sel)
  end

  # -- Deselect / clear ----------------------------------------------------

  def test_deselect
    sel = S.new(mode: :multi)
    sel = S.select(sel, "a")
    sel = S.select(sel, "b", extend: true)
    sel = S.deselect(sel, "a")
    assert_equal Set["b"], S.selected(sel)
  end

  def test_clear
    sel = S.new(mode: :multi)
    sel = S.select(sel, "a")
    sel = S.select(sel, "b", extend: true)
    sel = S.clear(sel)
    assert_empty S.selected(sel)
  end

  # -- Range mode ----------------------------------------------------------

  def test_range_select_no_anchor
    sel = S.new(mode: :range, order: %w[a b c d])
    sel = S.range_select(sel, "c")
    assert_equal Set["c"], S.selected(sel)
  end

  def test_range_select_with_anchor
    sel = S.new(mode: :range, order: %w[a b c d e])
    sel = S.select(sel, "b")
    sel = S.range_select(sel, "d")
    assert_equal Set["b", "c", "d"], S.selected(sel)
  end

  def test_range_select_reverse
    sel = S.new(mode: :range, order: %w[a b c d e])
    sel = S.select(sel, "d")
    sel = S.range_select(sel, "b")
    assert_equal Set["b", "c", "d"], S.selected(sel)
  end

  def test_range_select_anchor_not_in_order
    sel = S.new(mode: :range, order: %w[a b c])
    # Force an anchor that is not in order
    sel = S.select(sel, "z")
    sel = S.range_select(sel, "b")
    # Falls back to single selection since anchor not found
    assert_equal Set["b"], S.selected(sel)
  end

  # -- selected? -----------------------------------------------------------

  def test_selected_predicate
    sel = S.new(mode: :single)
    sel = S.select(sel, "a")
    assert S.selected?(sel, "a")
    refute S.selected?(sel, "b")
  end
end
