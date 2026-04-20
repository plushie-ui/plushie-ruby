# frozen_string_literal: true

require "minitest/autorun"
require_relative "../test_helper"
require "plushie"

# Unit tests for the coalescable-event buffer inside Plushie::Runtime.
# Exercises the internal coalesce_event / flush_coalescables /
# combine_scroll_events helpers without standing up a full runtime.
#
# Pattern mirrors Elixir's Plushie.Runtime.Coalescable tests: last-wins
# on (window_id, id, type), insertion-order flush, scroll deltas
# accumulate instead of overwriting.
class TestRuntimeCoalesce < Minitest::Test
  W = Plushie::Event::Widget

  # A stripped-down coalescer that shares the same semantics as the
  # runtime's helpers. Instantiated per test so state doesn't leak.
  class Coalescer
    COALESCABLE_TYPES = %i[move scroll scrolled resize].freeze

    attr_reader :pending, :order, :dispatched

    def initialize
      @pending = {}
      @order = []
      @dispatched = []
    end

    def coalescable?(event)
      event.is_a?(W) && COALESCABLE_TYPES.include?(event.type)
    end

    def coalesce(event)
      key = [event.window_id, event.id, event.type]
      merged =
        if event.type == :scroll && @pending.key?(key)
          combine_scroll(@pending[key], event)
        else
          event
        end
      @order << key unless @pending.key?(key)
      @pending[key] = merged
    end

    def combine_scroll(old, new_event)
      old_val = old.value.is_a?(Hash) ? old.value : {}
      new_val = new_event.value.is_a?(Hash) ? new_event.value : {}
      dx = (old_val[:delta_x] || 0) + (new_val[:delta_x] || 0)
      dy = (old_val[:delta_y] || 0) + (new_val[:delta_y] || 0)
      merged = new_val.merge(delta_x: dx, delta_y: dy)
      W.new(
        type: new_event.type, id: new_event.id, value: merged,
        window_id: new_event.window_id, scope: new_event.scope
      )
    end

    def flush
      return if @pending.empty?
      order = @order
      pending = @pending
      @pending = {}
      @order = []
      order.each { |k| @dispatched << pending[k] }
    end
  end

  def setup
    @c = Coalescer.new
  end

  def move(id, value, window_id: "main")
    W.new(type: :move, id: id, value: value, window_id: window_id, scope: [])
  end

  def scroll(id, dx, dy)
    W.new(
      type: :scroll,
      id: id,
      value: {delta_x: dx, delta_y: dy},
      window_id: "main",
      scope: []
    )
  end

  def resize(id, w, h)
    W.new(
      type: :resize,
      id: id,
      value: {width: w, height: h},
      window_id: "main",
      scope: []
    )
  end

  def test_coalescable_type_set
    assert @c.coalescable?(move("m", 1))
    assert @c.coalescable?(scroll("s", 1, 1))
    assert @c.coalescable?(resize("r", 1, 1))
    refute @c.coalescable?(
      W.new(type: :click, id: "btn", window_id: "main", scope: [])
    )
  end

  def test_move_events_coalesce_last_wins
    @c.coalesce(move("hover", {x: 1, y: 1}))
    @c.coalesce(move("hover", {x: 2, y: 2}))
    @c.coalesce(move("hover", {x: 3, y: 3}))
    @c.flush

    assert_equal 1, @c.dispatched.length
    assert_equal({x: 3, y: 3}, @c.dispatched.first.value)
  end

  def test_different_sources_do_not_coalesce
    @c.coalesce(move("hover_a", {x: 1, y: 1}))
    @c.coalesce(move("hover_b", {x: 2, y: 2}))
    @c.flush

    assert_equal 2, @c.dispatched.length
    ids = @c.dispatched.map(&:id)
    assert_equal %w[hover_a hover_b], ids
  end

  def test_scroll_deltas_accumulate
    @c.coalesce(scroll("s", 10, 0))
    @c.coalesce(scroll("s", 5, 0))
    @c.coalesce(scroll("s", 2, 3))
    @c.flush

    assert_equal 1, @c.dispatched.length
    v = @c.dispatched.first.value
    assert_equal 17, v[:delta_x]
    assert_equal 3, v[:delta_y]
  end

  def test_resize_last_wins
    @c.coalesce(resize("panel", 100, 100))
    @c.coalesce(resize("panel", 200, 200))
    @c.flush

    assert_equal 1, @c.dispatched.length
    assert_equal({width: 200, height: 200}, @c.dispatched.first.value)
  end

  def test_flush_preserves_insertion_order
    @c.coalesce(move("a", 1))
    @c.coalesce(move("b", 1))
    @c.coalesce(move("a", 2)) # last-wins but slot 0 stays
    @c.coalesce(move("c", 1))
    @c.flush

    ids = @c.dispatched.map(&:id)
    assert_equal %w[a b c], ids
  end

  def test_flush_clears_pending
    @c.coalesce(move("a", 1))
    @c.flush
    assert_empty @c.pending
    assert_empty @c.order

    # Subsequent coalesce + flush works fresh.
    @c.coalesce(move("a", 2))
    @c.flush
    assert_equal 2, @c.dispatched.length
  end
end
