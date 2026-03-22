# frozen_string_literal: true

require "test_helper"

class TestEncode < Minitest::Test
  E = Plushie::Encode

  def test_primitives_pass_through
    assert_equal 42, E.encode_value(42)
    assert_equal 3.14, E.encode_value(3.14)
    assert_equal "hello", E.encode_value("hello")
    assert_equal true, E.encode_value(true)
    assert_equal false, E.encode_value(false)
    assert_nil E.encode_value(nil)
  end

  def test_symbols_become_strings
    assert_equal "fill", E.encode_value(:fill)
    assert_equal "center", E.encode_value(:center)
  end

  def test_arrays_recursive
    assert_equal ["a", "b"], E.encode_value([:a, :b])
    assert_equal [1, [2, 3]], E.encode_value([1, [2, 3]])
  end

  def test_hashes_recursive_with_string_keys
    result = E.encode_value({name: :test, count: 42})
    assert_equal({"name" => "test", "count" => 42}, result)
  end

  def test_nested_hashes
    result = E.encode_value({outer: {inner: :value}})
    assert_equal({"outer" => {"inner" => "value"}}, result)
  end

  def test_objects_with_to_wire
    obj = Plushie::Type::Shadow.new
    result = E.encode_value(obj)
    assert_kind_of Hash, result
    assert result.key?("color") || result.key?(:color)
  end

  def test_raises_on_unknown_type
    assert_raises(ArgumentError) { E.encode_value(Object.new) }
  end
end
