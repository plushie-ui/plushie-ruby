# frozen_string_literal: true

require "test_helper"

class TestTypes < Minitest::Test
  # -- Enum types -----------------------------------------------------------

  def test_alignment_encode
    assert_equal "left", Plushie::Type::Alignment.encode(:left)
    assert_equal "center", Plushie::Type::Alignment.encode(:center)
    assert_equal "start", Plushie::Type::Alignment.encode(:start)
    assert_raises(ArgumentError) { Plushie::Type::Alignment.encode(:invalid) }
  end

  def test_direction_encode
    assert_equal "horizontal", Plushie::Type::Direction.encode(:horizontal)
    assert_equal "vertical", Plushie::Type::Direction.encode(:vertical)
    assert_equal "both", Plushie::Type::Direction.encode(:both)
  end

  def test_anchor_encode
    assert_equal "start", Plushie::Type::Anchor.encode(:start)
    assert_equal "end", Plushie::Type::Anchor.encode(:end)
  end

  def test_content_fit_encode
    assert_equal "cover", Plushie::Type::ContentFit.encode(:cover)
    assert_equal "scale_down", Plushie::Type::ContentFit.encode(:scale_down)
  end

  def test_filter_method_encode
    assert_equal "nearest", Plushie::Type::FilterMethod.encode(:nearest)
    assert_equal "linear", Plushie::Type::FilterMethod.encode(:linear)
  end

  def test_position_encode
    assert_equal "bottom", Plushie::Type::Position.encode(:bottom)
    assert_equal "follow_cursor", Plushie::Type::Position.encode(:follow_cursor)
  end

  def test_shaping_encode
    assert_equal "advanced", Plushie::Type::Shaping.encode(:advanced)
  end

  def test_wrapping_encode
    assert_equal "word", Plushie::Type::Wrapping.encode(:word)
    assert_equal "word_or_glyph", Plushie::Type::Wrapping.encode(:word_or_glyph)
  end

  # -- Length ---------------------------------------------------------------

  def test_length_encode_fill
    assert_equal "fill", Plushie::Type::Length.encode(:fill)
  end

  def test_length_encode_shrink
    assert_equal "shrink", Plushie::Type::Length.encode(:shrink)
  end

  def test_length_encode_fill_portion
    assert_equal({fill_portion: 3}, Plushie::Type::Length.encode([:fill_portion, 3]))
  end

  def test_length_encode_number
    assert_equal 200, Plushie::Type::Length.encode(200)
    assert_equal 0, Plushie::Type::Length.encode(0)
  end

  def test_length_rejects_negative
    assert_raises(ArgumentError) { Plushie::Type::Length.encode(-1) }
  end

  # -- Padding --------------------------------------------------------------

  def test_padding_cast_uniform
    result = Plushie::Type::Padding.cast(16)
    assert_equal({top: 16, right: 16, bottom: 16, left: 16}, result)
  end

  def test_padding_cast_vertical_horizontal
    result = Plushie::Type::Padding.cast([8, 16])
    assert_equal({top: 8, right: 16, bottom: 8, left: 16}, result)
  end

  def test_padding_cast_four_values
    result = Plushie::Type::Padding.cast([1, 2, 3, 4])
    assert_equal({top: 1, right: 2, bottom: 3, left: 4}, result)
  end

  def test_padding_from_opts
    pad = Plushie::Type::Padding.from_opts(top: 4, bottom: 8)
    assert_equal 4, pad.top
    assert_equal 8, pad.bottom
    assert_nil pad.left
  end

  # -- Border ---------------------------------------------------------------

  def test_border_new_defaults
    b = Plushie::Type::Border.new
    assert_nil b.color
    assert_equal 0, b.width
    assert_equal 0, b.radius
  end

  def test_border_from_opts
    b = Plushie::Type::Border.from_opts(color: :red, width: 2, rounded: 8)
    assert_equal "#ff0000", b.color
    assert_equal 2, b.width
    assert_equal 8, b.radius
  end

  def test_border_to_wire
    b = Plushie::Type::Border.from_opts(color: "#333", width: 1, rounded: 4)
    wire = b.to_wire
    assert_equal "#333333", wire[:color]
    assert_equal 1, wire[:width]
    assert_equal 4, wire[:radius]
  end

  # -- Shadow ---------------------------------------------------------------

  def test_shadow_new_defaults
    s = Plushie::Type::Shadow.new
    assert_equal "#000000", s.color
    assert_equal 0, s.offset_x
    assert_equal 0, s.blur_radius
  end

  def test_shadow_to_wire
    s = Plushie::Type::Shadow.from_opts(color: "#00000040", offset_y: 2, blur_radius: 4)
    wire = s.to_wire
    assert_equal "#00000040", wire[:color]
    assert_equal [0, 2], wire[:offset]
    assert_equal 4, wire[:blur_radius]
  end

  # -- Font -----------------------------------------------------------------

  def test_font_encode_default
    assert_equal "default", Plushie::Type::Font.encode(:default)
  end

  def test_font_encode_monospace
    assert_equal "monospace", Plushie::Type::Font.encode(:monospace)
  end

  def test_font_encode_family_string
    assert_equal({family: "Fira Code"}, Plushie::Type::Font.encode("Fira Code"))
  end

  def test_font_encode_struct
    spec = Plushie::Type::Font.from_opts(family: "Inter", weight: :bold, style: :italic)
    result = Plushie::Type::Font.encode(spec)
    assert_equal "Inter", result[:family]
    assert_equal "Bold", result[:weight]
    assert_equal "Italic", result[:style]
  end

  def test_font_pascal_case
    assert_equal "ExtraBold", Plushie::Type::Font.pascal_case(:extra_bold)
    assert_equal "SemiCondensed", Plushie::Type::Font.pascal_case(:semi_condensed)
  end

  # -- Theme ----------------------------------------------------------------

  def test_theme_encode_builtin
    assert_equal "dark", Plushie::Type::Theme.encode(:dark)
    assert_equal "catppuccin_mocha", Plushie::Type::Theme.encode(:catppuccin_mocha)
    assert_equal "tokyo_night", Plushie::Type::Theme.encode(:tokyo_night)
  end

  def test_theme_encode_system
    assert_equal "system", Plushie::Type::Theme.encode(:system)
  end

  def test_theme_rejects_unknown
    assert_raises(ArgumentError) { Plushie::Type::Theme.encode(:nonexistent) }
  end

  # -- Gradient -------------------------------------------------------------

  def test_gradient_linear
    g = Plushie::Type::Gradient.linear(90, [[0.0, :red], [1.0, :blue]])
    assert_equal "linear", g[:type]
    assert_equal 90, g[:angle]
    assert_equal "#ff0000", g[:stops][0][:color]
    assert_equal "#0000ff", g[:stops][1][:color]
  end

  # -- A11y -----------------------------------------------------------------

  def test_a11y_from_opts
    spec = Plushie::Type::A11y.from_opts(role: :button, label: "Save", hidden: false)
    assert_equal :button, spec.role
    assert_equal "Save", spec.label
    assert_equal false, spec.hidden
  end

  def test_a11y_to_wire_strips_nil
    spec = Plushie::Type::A11y.from_opts(role: :button, label: "Save")
    wire = spec.to_wire
    assert wire.key?(:role)
    assert wire.key?(:label)
    refute wire.key?(:description)
    refute wire.key?(:hidden)
  end

  # -- StyleMap -------------------------------------------------------------

  def test_style_map_encode_symbol
    assert_equal "primary", Plushie::Type::StyleMap.encode(:primary)
  end

  def test_style_map_from_opts
    spec = Plushie::Type::StyleMap.from_opts(base: :secondary, background: "#ff0000")
    wire = spec.to_wire
    assert_equal "secondary", wire[:base]
    assert_equal "#ff0000", wire[:background]
  end
end
