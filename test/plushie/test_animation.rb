# frozen_string_literal: true

require "test_helper"

class TestAnimation < Minitest::Test
  A = Plushie::Animation

  # -- Easing functions ----------------------------------------------------

  def test_linear
    assert_equal 0.0, A.linear(0.0)
    assert_equal 0.5, A.linear(0.5)
    assert_equal 1.0, A.linear(1.0)
  end

  def test_ease_in_starts_slow
    assert_operator A.ease_in(0.5), :<, 0.5
  end

  def test_ease_out_starts_fast
    assert_operator A.ease_out(0.5), :>, 0.5
  end

  def test_ease_in_out_boundaries
    assert_in_delta 0.0, A.ease_in_out(0.0), 1e-10
    assert_in_delta 1.0, A.ease_in_out(1.0), 1e-10
    assert_in_delta 0.5, A.ease_in_out(0.5), 1e-10
  end

  def test_ease_in_quad
    assert_in_delta 0.25, A.ease_in_quad(0.5), 1e-10
  end

  def test_ease_out_quad
    assert_in_delta 0.75, A.ease_out_quad(0.5), 1e-10
  end

  def test_ease_in_out_quad_boundaries
    assert_in_delta 0.0, A.ease_in_out_quad(0.0), 1e-10
    assert_in_delta 1.0, A.ease_in_out_quad(1.0), 1e-10
  end

  def test_spring_boundaries
    assert_in_delta 0.0, A.spring(0.0), 1e-10
    assert_in_delta 1.0, A.spring(1.0), 1e-10
  end

  def test_spring_overshoots
    # Spring should overshoot 1.0 at some point
    max_val = (1..99).map { |i| A.spring(i / 100.0) }.max
    assert_operator max_val, :>, 1.0
  end

  # -- Interpolation -------------------------------------------------------

  def test_interpolate_linear
    assert_in_delta 5.0, A.interpolate(0, 10, 0.5), 1e-10
    assert_in_delta 0.0, A.interpolate(0, 10, 0.0), 1e-10
    assert_in_delta 10.0, A.interpolate(0, 10, 1.0), 1e-10
  end

  def test_interpolate_with_easing
    val = A.interpolate(0, 100, 0.5, :ease_in)
    assert_operator val, :<, 50.0
  end

  def test_interpolate_clamps_t
    assert_in_delta 0.0, A.interpolate(0, 10, -1.0), 1e-10
    assert_in_delta 10.0, A.interpolate(0, 10, 2.0), 1e-10
  end

  def test_interpolate_with_proc_easing
    double_easing = ->(t) { (t * 2.0 > 1.0) ? 1.0 : t * 2.0 }
    val = A.interpolate(0, 100, 0.25, double_easing)
    assert_in_delta 50.0, val, 1e-10
  end

  # -- Animation lifecycle -------------------------------------------------

  def test_new_creates_animation
    anim = A.new(0.0, 1.0, 300)
    assert_equal 0.0, A.value(anim)
    assert_equal 0.0, anim.from
    assert_equal 1.0, anim.to
    assert_equal 300, anim.duration
    assert_nil anim.started_at
  end

  def test_new_rejects_non_positive_duration
    assert_raises(ArgumentError) { A.new(0, 1, 0) }
    assert_raises(ArgumentError) { A.new(0, 1, -1) }
  end

  def test_new_with_easing
    anim = A.new(0.0, 1.0, 300, easing: :ease_out)
    assert_equal :ease_out, anim.easing
  end

  def test_start_sets_timestamp_and_resets_value
    anim = A.new(0.0, 1.0, 300)
    started = A.start(anim, 1000)
    assert_equal 1000, started.started_at
    assert_equal 0.0, A.value(started)
  end

  def test_advance_before_start_returns_unchanged
    anim = A.new(0.0, 1.0, 300)
    value, result = A.advance(anim, 1000)
    assert_equal 0.0, value
    assert_equal anim, result
  end

  def test_advance_mid_animation
    anim = A.new(0.0, 100.0, 1000)
    anim = A.start(anim, 0)
    value, result = A.advance(anim, 500)
    assert_in_delta 50.0, value, 1e-10
    refute_equal :finished, result
  end

  def test_advance_completes
    anim = A.new(0.0, 100.0, 1000)
    anim = A.start(anim, 0)
    value, result = A.advance(anim, 1000)
    assert_equal 100.0, value
    assert_equal :finished, result
  end

  def test_advance_past_duration_finishes
    anim = A.new(0.0, 100.0, 1000)
    anim = A.start(anim, 0)
    value, result = A.advance(anim, 2000)
    assert_equal 100.0, value
    assert_equal :finished, result
  end

  def test_finished_predicate
    anim = A.new(0.0, 1.0, 100)
    refute A.finished?(anim)

    anim = A.start(anim, 0)
    refute A.finished?(anim)

    _, anim_or_finished = A.advance(anim, 50)
    refute A.finished?(anim_or_finished) unless anim_or_finished == :finished
  end

  def test_advance_with_easing
    anim = A.new(0.0, 100.0, 1000, easing: :ease_in)
    anim = A.start(anim, 0)
    value, _ = A.advance(anim, 500)
    # ease_in at t=0.5 gives 0.125, so value should be 12.5
    assert_in_delta 12.5, value, 1e-10
  end

  def test_restart_resets
    anim = A.new(0.0, 100.0, 1000)
    anim = A.start(anim, 0)
    _, anim = A.advance(anim, 500)
    return if anim == :finished

    restarted = A.start(anim, 1000)
    assert_equal 0.0, A.value(restarted)
    assert_equal 1000, restarted.started_at
  end
end
