# frozen_string_literal: true

require "test_helper"

class TestCommand < Minitest::Test
  def test_none
    cmd = Plushie::Command.none
    assert_equal :none, cmd.type
  end

  def test_async
    callable = -> { "result" }
    cmd = Plushie::Command.async(callable, :fetch)
    assert_equal :async, cmd.type
    assert_equal :fetch, cmd.payload[:tag]
  end

  def test_focus
    cmd = Plushie::Command.focus("input_field")
    assert_equal :focus, cmd.type
    assert_equal "input_field", cmd.payload[:target]
  end

  def test_send_after
    cmd = Plushie::Command.send_after(3000, :clear)
    assert_equal :send_after, cmd.type
    assert_equal 3000, cmd.payload[:delay]
    assert_equal :clear, cmd.payload[:event]
  end

  def test_batch
    cmds = Plushie::Command.batch([
      Plushie::Command.focus("input"),
      Plushie::Command.send_after(1000, :tick)
    ])
    assert_equal :batch, cmds.type
    assert_equal 2, cmds.payload[:commands].length
  end

  def test_exit
    cmd = Plushie::Command.exit
    assert_equal :exit, cmd.type
  end

  def test_close_window
    cmd = Plushie::Command.close_window("settings")
    assert_equal :close_window, cmd.type
    assert_equal "settings", cmd.payload[:window_id]
  end
end
