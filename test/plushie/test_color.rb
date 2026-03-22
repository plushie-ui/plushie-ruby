# frozen_string_literal: true

require "test_helper"

class TestColor < Minitest::Test
  C = Plushie::Type::Color

  def test_from_rgb
    assert_equal "#ff8000", C.from_rgb(255, 128, 0)
    assert_equal "#000000", C.from_rgb(0, 0, 0)
    assert_equal "#ffffff", C.from_rgb(255, 255, 255)
  end

  def test_from_rgba
    assert_equal "#ff800080", C.from_rgba(255, 128, 0, 128)
    assert_equal "#00000000", C.from_rgba(0, 0, 0, 0)
  end

  def test_from_hex_with_hash
    assert_equal "#ff8800", C.from_hex("#ff8800")
    assert_equal "#ff880080", C.from_hex("#ff880080")
  end

  def test_from_hex_without_hash
    assert_equal "#ff8800", C.from_hex("ff8800")
  end

  def test_from_hex_normalizes_case
    assert_equal "#ff8800", C.from_hex("#FF8800")
  end

  def test_from_hex_expands_short_forms
    assert_equal "#ffffff", C.from_hex("#fff")
    assert_equal "#ff0000", C.from_hex("#f00")
    assert_equal "#ff000088", C.from_hex("#f008")
  end

  def test_from_hex_rejects_invalid
    assert_raises(ArgumentError) { C.from_hex("#gggggg") }
    assert_raises(ArgumentError) { C.from_hex("#12") }
    assert_raises(ArgumentError) { C.from_hex("#12345") }
  end

  def test_cast_named_symbol
    assert_equal "#ff0000", C.cast(:red)
    assert_equal "#0000ff", C.cast(:blue)
    assert_equal "#6495ed", C.cast(:cornflowerblue)
    assert_equal "#00000000", C.cast(:transparent)
  end

  def test_cast_named_string
    assert_equal "#ff0000", C.cast("red")
    assert_equal "#0000ff", C.cast("blue")
  end

  def test_cast_hex_string
    assert_equal "#ff8800", C.cast("#ff8800")
    assert_equal "#ff880080", C.cast("#ff880080")
  end

  def test_cast_rejects_unknown_name
    assert_raises(ArgumentError) { C.cast(:nonexistent_color) }
  end

  def test_named_colors_count
    # 148 CSS colors + transparent = 149
    assert_equal 149, C::NAMED_COLORS.size
  end

  def test_all_named_colors_are_valid_hex
    C::NAMED_COLORS.each do |name, hex|
      assert_match(/\A#[0-9a-f]{6,8}\z/, hex, "#{name} has invalid hex: #{hex}")
    end
  end

  def test_encode_is_alias_for_cast
    assert_equal C.cast(:red), C.encode(:red)
    assert_equal C.cast("#ff8800"), C.encode("#ff8800")
  end
end
