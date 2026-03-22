# frozen_string_literal: true

require "test_helper"

class TestKeyModifiers < Minitest::Test
  KM = Plushie::KeyModifiers

  def test_defaults_to_false
    mods = KM.new
    refute mods.ctrl?
    refute mods.shift?
    refute mods.alt?
    refute mods.logo?
    refute mods.command?
  end

  def test_individual_flags
    mods = KM.new(ctrl: true)
    assert mods.ctrl?
    refute mods.shift?
  end

  def test_multiple_flags
    mods = KM.new(ctrl: true, shift: true, command: true)
    assert mods.ctrl?
    assert mods.shift?
    assert mods.command?
    refute mods.alt?
    refute mods.logo?
  end

  def test_from_hash
    mods = KM.from_hash({ctrl: true, alt: true})
    assert mods.ctrl?
    assert mods.alt?
    refute mods.shift?
  end

  def test_from_hash_missing_keys_default_false
    mods = KM.from_hash({})
    refute mods.ctrl?
    refute mods.shift?
  end

  def test_to_h
    mods = KM.new(ctrl: true, shift: false, alt: true, logo: false, command: true)
    expected = {ctrl: true, shift: false, alt: true, logo: false, command: true}
    assert_equal expected, mods.to_h
  end

  def test_equality
    a = KM.new(ctrl: true)
    b = KM.new(ctrl: true)
    assert_equal a, b
  end

  def test_inequality
    a = KM.new(ctrl: true)
    b = KM.new(ctrl: false)
    refute_equal a, b
  end

  def test_inspect
    mods = KM.new(ctrl: true, shift: true)
    assert_includes mods.inspect, "ctrl"
    assert_includes mods.inspect, "shift"
  end

  def test_inspect_none
    mods = KM.new
    assert_includes mods.inspect, "(none)"
  end
end
