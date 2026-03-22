# frozen_string_literal: true

require "test_helper"
require "plushie/test"

class TestScriptParser < Minitest::Test
  S = Plushie::Test::Script

  def test_parse_header_and_body
    source = <<~SCRIPT
      app Counter
      viewport 800x600
      theme dark
      backend mock
      -----
      click "#increment"
      assert_text "#count" "Count: 1"
    SCRIPT

    result = S.parse(source)
    assert_equal "Counter", result.header["app"]
    assert_equal "800x600", result.header["viewport"]
    assert_equal "dark", result.header["theme"]
    assert_equal "mock", result.header["backend"]
    assert_equal 2, result.instructions.length
  end

  def test_parse_click_instruction
    result = S.parse("-----\nclick \"#save\"")
    inst = result.instructions[0]
    assert_equal "click", inst.command
    assert_equal ["#save"], inst.args
  end

  def test_parse_type_instruction
    result = S.parse("-----\ntype \"#input\" \"hello world\"")
    inst = result.instructions[0]
    assert_equal "type", inst.command
    assert_equal ["#input", "hello world"], inst.args
  end

  def test_parse_type_key_instruction
    result = S.parse("-----\ntype_key Enter")
    inst = result.instructions[0]
    assert_equal "type_key", inst.command
    assert_equal ["Enter"], inst.args
  end

  def test_parse_press_and_release
    result = S.parse("-----\npress Escape\nrelease Escape")
    assert_equal "press", result.instructions[0].command
    assert_equal "release", result.instructions[1].command
    assert_equal ["Escape"], result.instructions[0].args
  end

  def test_parse_expect_instruction
    result = S.parse("-----\nexpect \"Hello\"")
    inst = result.instructions[0]
    assert_equal "expect", inst.command
    assert_equal ["Hello"], inst.args
  end

  def test_parse_tree_hash_instruction
    result = S.parse("-----\ntree_hash main_view")
    inst = result.instructions[0]
    assert_equal "tree_hash", inst.command
    assert_equal ["main_view"], inst.args
  end

  def test_parse_screenshot_instruction
    result = S.parse("-----\nscreenshot home_page")
    inst = result.instructions[0]
    assert_equal "screenshot", inst.command
    assert_equal ["home_page"], inst.args
  end

  def test_parse_assert_text_instruction
    result = S.parse("-----\nassert_text \"#label\" \"Expected value\"")
    inst = result.instructions[0]
    assert_equal "assert_text", inst.command
    assert_equal ["#label", "Expected value"], inst.args
  end

  def test_parse_assert_model_instruction
    result = S.parse("-----\nassert_model \"some_value\"")
    inst = result.instructions[0]
    assert_equal "assert_model", inst.command
    assert_equal ["some_value"], inst.args
  end

  def test_parse_wait_instruction
    result = S.parse("-----\nwait 0.5")
    inst = result.instructions[0]
    assert_equal "wait", inst.command
    assert_equal ["0.5"], inst.args
  end

  def test_parse_move_instruction
    result = S.parse("-----\nmove \"100,200\"")
    inst = result.instructions[0]
    assert_equal "move", inst.command
    assert_equal ["100,200"], inst.args
  end

  def test_skips_blank_lines_and_comments
    source = <<~SCRIPT
      app Counter
      -----

      # This is a comment
      click "#btn"

      # Another comment
      click "#btn2"
    SCRIPT

    result = S.parse(source)
    assert_equal 2, result.instructions.length
    assert_equal "#btn", result.instructions[0].args[0]
    assert_equal "#btn2", result.instructions[1].args[0]
  end

  def test_header_comments_skipped
    source = <<~SCRIPT
      # Header comment
      app Counter
      -----
      click "#btn"
    SCRIPT

    result = S.parse(source)
    assert_equal "Counter", result.header["app"]
    refute result.header.key?("#")
  end

  def test_no_separator_treats_all_as_body
    source = <<~SCRIPT
      click "#btn"
      click "#btn2"
    SCRIPT

    result = S.parse(source)
    assert_equal({}, result.header)
    assert_equal 2, result.instructions.length
  end

  def test_tokenize_quoted_strings
    tokens = S.tokenize('type "#field" "hello world"')
    assert_equal ["type", "#field", "hello world"], tokens
  end

  def test_tokenize_unquoted_words
    tokens = S.tokenize("click save")
    assert_equal ["click", "save"], tokens
  end

  def test_tokenize_mixed
    tokens = S.tokenize('assert_text "#id" value')
    assert_equal ["assert_text", "#id", "value"], tokens
  end

  def test_longer_separator_accepted
    result = S.parse("app Foo\n----------\nclick \"#x\"")
    assert_equal "Foo", result.header["app"]
    assert_equal 1, result.instructions.length
  end
end
