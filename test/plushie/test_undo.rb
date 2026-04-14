# frozen_string_literal: true

require "test_helper"

class TestUndo < Minitest::Test
  U = Plushie::Undo

  def test_new
    u = U.new(0)
    assert_equal 0, U.current(u)
    refute U.can_undo?(u)
    refute U.can_redo?(u)
  end

  def test_new_custom_max_size
    u = U.new(0, max_size: 5)
    assert_equal 0, U.current(u)
    assert_equal 5, u.max_size
  end

  def test_new_invalid_max_size
    assert_raises(ArgumentError) { U.new(0, max_size: 0) }
    assert_raises(ArgumentError) { U.new(0, max_size: -1) }
    assert_raises(ArgumentError) { U.new(0, max_size: "ten") }
  end

  def test_push
    u = U.new(0)
    u = U.push(u, {apply: ->(n) { n + 1 }, undo: ->(n) { n - 1 }})
    assert_equal 1, U.current(u)
    assert U.can_undo?(u)
  end

  def test_push_validates_callables
    u = U.new(0)
    assert_raises(ArgumentError) { U.push(u, {apply: "not callable", undo: ->(n) { n }}) }
    assert_raises(ArgumentError) { U.push(u, {apply: ->(n) { n }, undo: 42}) }
  end

  def test_undo
    u = U.new(0)
    u = U.push(u, {apply: ->(n) { n + 1 }, undo: ->(n) { n - 1 }})
    u = U.undo(u)
    assert_equal 0, U.current(u)
    refute U.can_undo?(u)
    assert U.can_redo?(u)
  end

  def test_redo
    u = U.new(0)
    u = U.push(u, {apply: ->(n) { n + 1 }, undo: ->(n) { n - 1 }})
    u = U.undo(u)
    u = U.redo(u)
    assert_equal 1, U.current(u)
    assert U.can_undo?(u)
    refute U.can_redo?(u)
  end

  def test_push_clears_redo
    u = U.new(0)
    u = U.push(u, {apply: ->(n) { n + 1 }, undo: ->(n) { n - 1 }})
    u = U.undo(u)
    u = U.push(u, {apply: ->(n) { n + 10 }, undo: ->(n) { n - 10 }})
    assert_equal 10, U.current(u)
    refute U.can_redo?(u)
  end

  def test_undo_empty_is_noop
    u = U.new(42)
    u2 = U.undo(u)
    assert_equal 42, U.current(u2)
  end

  def test_redo_empty_is_noop
    u = U.new(42)
    u2 = U.redo(u)
    assert_equal 42, U.current(u2)
  end

  def test_history
    u = U.new(0)
    u = U.push(u, {apply: ->(n) { n + 1 }, undo: ->(n) { n - 1 }, label: "inc"})
    u = U.push(u, {apply: ->(n) { n * 2 }, undo: ->(n) { n / 2 }, label: "double"})
    assert_equal ["double", "inc"], U.history(u)
  end

  def test_multiple_undo_redo
    u = U.new(0)
    u = U.push(u, {apply: ->(n) { n + 1 }, undo: ->(n) { n - 1 }})
    u = U.push(u, {apply: ->(n) { n + 10 }, undo: ->(n) { n - 10 }})
    u = U.push(u, {apply: ->(n) { n + 100 }, undo: ->(n) { n - 100 }})
    assert_equal 111, U.current(u)

    u = U.undo(u)
    assert_equal 11, U.current(u)
    u = U.undo(u)
    assert_equal 1, U.current(u)
    u = U.redo(u)
    assert_equal 11, U.current(u)
  end

  # -- Max size --------------------------------------------------------------

  def test_max_size_drops_oldest
    u = U.new(0, max_size: 3)
    5.times { |i| u = U.push(u, {apply: ->(n) { n + 1 }, undo: ->(n) { n - 1 }, label: "step #{i}"}) }
    assert_equal 5, U.current(u)

    # Only 3 undo levels available
    u = U.undo(u)
    assert_equal 4, U.current(u)
    u = U.undo(u)
    assert_equal 3, U.current(u)
    u = U.undo(u)
    assert_equal 2, U.current(u)
    refute U.can_undo?(u)
  end

  def test_max_size_default
    u = U.new(0)
    assert_equal Plushie::Undo::DEFAULT_MAX_SIZE, u.max_size
  end

  # -- Coalescing ----------------------------------------------------------

  def test_coalesce_within_window
    Thread.current[:plushie_undo_timestamp] = 100

    u = U.new("")
    u = U.push(u, {
      apply: ->(s) { s + "a" },
      undo: ->(s) { s.chop },
      coalesce: :typing,
      coalesce_window_ms: 500
    })

    Thread.current[:plushie_undo_timestamp] = 200

    u = U.push(u, {
      apply: ->(s) { s + "b" },
      undo: ->(s) { s.chop },
      coalesce: :typing,
      coalesce_window_ms: 500
    })

    assert_equal "ab", U.current(u)
    # Single undo should reverse both coalesced operations
    u = U.undo(u)
    assert_equal "", U.current(u)
  ensure
    Thread.current[:plushie_undo_timestamp] = nil
  end

  def test_coalesce_outside_window
    Thread.current[:plushie_undo_timestamp] = 100

    u = U.new("")
    u = U.push(u, {
      apply: ->(s) { s + "a" },
      undo: ->(s) { s.chop },
      coalesce: :typing,
      coalesce_window_ms: 50
    })

    Thread.current[:plushie_undo_timestamp] = 200

    u = U.push(u, {
      apply: ->(s) { s + "b" },
      undo: ->(s) { s.chop },
      coalesce: :typing,
      coalesce_window_ms: 50
    })

    assert_equal "ab", U.current(u)
    # Two separate undo entries since outside window
    u = U.undo(u)
    assert_equal "a", U.current(u)
    u = U.undo(u)
    assert_equal "", U.current(u)
  ensure
    Thread.current[:plushie_undo_timestamp] = nil
  end

  def test_coalesce_different_keys_no_merge
    Thread.current[:plushie_undo_timestamp] = 100

    u = U.new(0)
    u = U.push(u, {
      apply: ->(n) { n + 1 },
      undo: ->(n) { n - 1 },
      coalesce: :a,
      coalesce_window_ms: 500
    })

    u = U.push(u, {
      apply: ->(n) { n + 10 },
      undo: ->(n) { n - 10 },
      coalesce: :b,
      coalesce_window_ms: 500
    })

    u = U.undo(u)
    assert_equal 1, U.current(u)
  ensure
    Thread.current[:plushie_undo_timestamp] = nil
  end
end
