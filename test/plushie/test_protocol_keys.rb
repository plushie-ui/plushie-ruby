# frozen_string_literal: true

require "test_helper"

class TestProtocolKeys < Minitest::Test
  K = Plushie::Protocol::Keys

  # -- Named keys ----------------------------------------------------------

  def test_parse_named_navigation_keys
    assert_equal :escape, K.parse_key("Escape")
    assert_equal :enter, K.parse_key("Enter")
    assert_equal :tab, K.parse_key("Tab")
    assert_equal :backspace, K.parse_key("Backspace")
    assert_equal :arrow_up, K.parse_key("ArrowUp")
    assert_equal :arrow_down, K.parse_key("ArrowDown")
    assert_equal :home, K.parse_key("Home")
    assert_equal :end, K.parse_key("End")
    assert_equal :page_up, K.parse_key("PageUp")
    assert_equal :space, K.parse_key("Space")
  end

  def test_parse_function_keys
    assert_equal :f1, K.parse_key("F1")
    assert_equal :f12, K.parse_key("F12")
    assert_equal :f35, K.parse_key("F35")
  end

  def test_parse_modifier_keys
    assert_equal :alt, K.parse_key("Alt")
    assert_equal :control, K.parse_key("Control")
    assert_equal :shift, K.parse_key("Shift")
    assert_equal :meta, K.parse_key("Meta")
    assert_equal :caps_lock, K.parse_key("CapsLock")
  end

  def test_parse_single_character_keys_pass_through
    assert_equal "a", K.parse_key("a")
    assert_equal "1", K.parse_key("1")
    assert_equal "/", K.parse_key("/")
    assert_equal " ", K.parse_key(" ")
  end

  def test_parse_unknown_multi_char_passes_through
    assert_equal "SomeUnknownKey", K.parse_key("SomeUnknownKey")
  end

  def test_parse_nil
    assert_nil K.parse_key(nil)
  end

  def test_media_keys
    assert_equal :media_play_pause, K.parse_key("MediaPlayPause")
    assert_equal :audio_volume_up, K.parse_key("AudioVolumeUp")
  end

  def test_tv_keys
    assert_equal :tv, K.parse_key("TV")
    assert_equal :tv_input_hdmi1, K.parse_key("TVInputHDMI1")
  end

  def test_ime_keys
    assert_equal :hangul_mode, K.parse_key("HangulMode")
    assert_equal :katakana, K.parse_key("Katakana")
  end

  # -- Physical keys -------------------------------------------------------

  def test_parse_physical_letters
    assert_equal :key_a, K.parse_physical_key("KeyA")
    assert_equal :key_z, K.parse_physical_key("KeyZ")
  end

  def test_parse_physical_digits
    assert_equal :digit_0, K.parse_physical_key("Digit0")
    assert_equal :digit_9, K.parse_physical_key("Digit9")
  end

  def test_parse_physical_modifiers
    assert_equal :shift_left, K.parse_physical_key("ShiftLeft")
    assert_equal :control_right, K.parse_physical_key("ControlRight")
    assert_equal :alt_left, K.parse_physical_key("AltLeft")
    assert_equal :meta_right, K.parse_physical_key("MetaRight")
  end

  def test_parse_physical_punctuation
    assert_equal :minus, K.parse_physical_key("Minus")
    assert_equal :bracket_left, K.parse_physical_key("BracketLeft")
    assert_equal :semicolon, K.parse_physical_key("Semicolon")
  end

  def test_parse_physical_numpad
    assert_equal :numpad_0, K.parse_physical_key("Numpad0")
    assert_equal :numpad_add, K.parse_physical_key("NumpadAdd")
    assert_equal :numpad_enter, K.parse_physical_key("NumpadEnter")
  end

  def test_parse_physical_nil
    assert_nil K.parse_physical_key(nil)
  end

  def test_parse_physical_unknown_passes_through
    assert_equal "UnknownCode", K.parse_physical_key("UnknownCode")
  end

  # -- Location ------------------------------------------------------------

  def test_parse_location
    assert_equal :left, K.parse_location("left")
    assert_equal :right, K.parse_location("right")
    assert_equal :numpad, K.parse_location("numpad")
    assert_equal :standard, K.parse_location("standard")
    assert_equal :standard, K.parse_location(nil)
    assert_equal :standard, K.parse_location("unknown")
  end
end
