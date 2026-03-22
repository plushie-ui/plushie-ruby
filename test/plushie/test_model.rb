# frozen_string_literal: true

require "test_helper"

class TestModel < Minitest::Test
  Model = Plushie::Model.define(:count, :name)

  def test_creates_immutable_instance
    m = Model.new(count: 0, name: "test")
    assert_equal 0, m.count
    assert_equal "test", m.name
    assert m.frozen?
  end

  def test_with_returns_new_instance
    m = Model.new(count: 0, name: "test")
    m2 = m.with(count: 1)

    assert_equal 1, m2.count
    assert_equal "test", m2.name
    assert_equal 0, m.count
    refute_same m, m2
  end

  def test_value_equality
    a = Model.new(count: 0, name: "test")
    b = Model.new(count: 0, name: "test")
    assert_equal a, b
  end

  def test_pattern_matching
    m = Model.new(count: 42, name: "test")

    result = case m
    in {count: 42}
      :matched
    else
      :no_match
    end

    assert_equal :matched, result
  end
end
