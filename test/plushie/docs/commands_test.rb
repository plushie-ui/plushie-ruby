# frozen_string_literal: true

require "test_helper"

class DocsCommandsTest < Minitest::Test
  C = Plushie::Command

  def test_commands_async_construct
    cmd = C.async(-> { "result" }, :data_fetched)
    assert_equal :async, cmd.type
    assert_equal :data_fetched, cmd.payload[:tag]
    assert_respond_to cmd.payload[:callable], :call
  end

  def test_commands_stream_construct
    cmd = C.stream(->(emit) { emit.call("chunk") }, :file_import)
    assert_equal :stream, cmd.type
    assert_equal :file_import, cmd.payload[:tag]
  end

  def test_commands_cancel_construct
    cmd = C.cancel(:file_import)
    assert_equal :cancel, cmd.type
    assert_equal :file_import, cmd.payload[:tag]
  end

  def test_commands_done_construct
    cmd = C.done(:defaults, ->(v) { [:config_loaded, v] })
    assert_equal :done, cmd.type
    assert_equal :defaults, cmd.payload[:value]
    assert_respond_to cmd.payload[:mapper], :call
  end

  def test_commands_exit_construct
    cmd = C.exit
    assert_equal :exit, cmd.type
  end

  def test_commands_focus_construct
    cmd = C.focus("todo_input")
    assert_equal :focus, cmd.type
    assert_equal "todo_input", cmd.payload[:target]
  end

  def test_commands_batch_construct
    cmd = C.batch([C.focus("name_input"), C.send_after(5000, :auto_save)])
    assert_equal :batch, cmd.type
    assert_equal 2, cmd.payload[:commands].length
    assert_equal :focus, cmd.payload[:commands][0].type
    assert_equal :send_after, cmd.payload[:commands][1].type
  end

  def test_commands_send_after_construct
    cmd = C.send_after(3000, :clear_message)
    assert_equal :send_after, cmd.type
    assert_equal 3000, cmd.payload[:delay]
    assert_equal :clear_message, cmd.payload[:event]
  end

  def test_commands_close_window_construct
    cmd = C.close_window("main")
    assert_equal :close_window, cmd.type
    assert_equal "main", cmd.payload[:window_id]
  end
end
