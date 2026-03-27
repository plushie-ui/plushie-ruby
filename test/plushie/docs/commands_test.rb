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

  # -- Scroll operations --

  def test_commands_scroll_to_construct
    cmd = C.scroll_to("chat_log", 500)
    assert_equal :scroll_to, cmd.type
    assert_equal "chat_log", cmd.payload[:target]
    assert_equal 500, cmd.payload[:offset_y]
  end

  def test_commands_snap_to_construct
    cmd = C.snap_to("scroll_area", 0.0, 0.5)
    assert_equal :snap_to, cmd.type
    assert_equal "scroll_area", cmd.payload[:target]
    assert_equal 0.0, cmd.payload[:x]
    assert_equal 0.5, cmd.payload[:y]
  end

  def test_commands_snap_to_end_construct
    cmd = C.snap_to_end("chat_log")
    assert_equal :snap_to_end, cmd.type
    assert_equal "chat_log", cmd.payload[:target]
  end

  def test_commands_scroll_by_construct
    cmd = C.scroll_by("log_view", 0, 100)
    assert_equal :scroll_by, cmd.type
    assert_equal "log_view", cmd.payload[:target]
    assert_equal 0, cmd.payload[:x]
    assert_equal 100, cmd.payload[:y]
  end

  # -- Text operations --

  def test_commands_select_all_construct
    cmd = C.select_all("editor")
    assert_equal :select_all, cmd.type
    assert_equal "editor", cmd.payload[:target]
  end

  def test_commands_move_cursor_to_construct
    cmd = C.move_cursor_to("editor", 42)
    assert_equal :move_cursor_to, cmd.type
    assert_equal "editor", cmd.payload[:target]
    assert_equal 42, cmd.payload[:position]
  end

  def test_commands_select_range_construct
    cmd = C.select_range("editor", 5, 10)
    assert_equal :select_range, cmd.type
    assert_equal "editor", cmd.payload[:target]
    assert_equal 5, cmd.payload[:start]
    assert_equal 10, cmd.payload[:end]
  end

  # -- Window management --

  def test_commands_maximize_window_construct
    cmd = C.maximize_window("main")
    assert_equal :window_op, cmd.type
    assert_equal :maximize, cmd.payload[:op]
    assert_equal "main", cmd.payload[:window_id]
    assert_equal true, cmd.payload[:maximized]
  end

  def test_commands_maximize_window_restore
    cmd = C.maximize_window("main", false)
    assert_equal :window_op, cmd.type
    assert_equal :maximize, cmd.payload[:op]
    assert_equal false, cmd.payload[:maximized]
  end

  def test_commands_set_window_mode_construct
    cmd = C.set_window_mode("main", :fullscreen)
    assert_equal :window_op, cmd.type
    assert_equal :set_mode, cmd.payload[:op]
    assert_equal "main", cmd.payload[:window_id]
    assert_equal "fullscreen", cmd.payload[:mode]
  end

  def test_commands_set_window_level_construct
    cmd = C.set_window_level("main", :always_on_top)
    assert_equal :window_op, cmd.type
    assert_equal :set_level, cmd.payload[:op]
    assert_equal "main", cmd.payload[:window_id]
    assert_equal "always_on_top", cmd.payload[:level]
  end

  # -- Window queries --

  def test_commands_get_window_size_construct
    cmd = C.get_window_size("main", :got_size)
    assert_equal :window_query, cmd.type
    assert_equal :get_size, cmd.payload[:op]
    assert_equal "main", cmd.payload[:window_id]
    assert_equal "got_size", cmd.payload[:tag]
  end

  def test_commands_get_system_theme_construct
    cmd = C.get_system_theme(:theme_detected)
    assert_equal :system_query, cmd.type
    assert_equal :get_system_theme, cmd.payload[:op]
    assert_equal "theme_detected", cmd.payload[:tag]
  end

  # -- PaneGrid operations --

  def test_commands_pane_split_construct
    cmd = C.pane_split("pane_grid", "editor", :horizontal, "new_editor")
    assert_equal :widget_op, cmd.type
    assert_equal :pane_split, cmd.payload[:op]
    assert_equal "pane_grid", cmd.payload[:target]
    assert_equal "editor", cmd.payload[:pane]
    assert_equal "horizontal", cmd.payload[:axis]
    assert_equal "new_editor", cmd.payload[:new_pane_id]
  end

  def test_commands_pane_close_construct
    cmd = C.pane_close("pane_grid", "editor")
    assert_equal :widget_op, cmd.type
    assert_equal :pane_close, cmd.payload[:op]
    assert_equal "pane_grid", cmd.payload[:target]
    assert_equal "editor", cmd.payload[:pane]
  end

  # -- Image operations --

  def test_commands_create_image_construct
    cmd = C.create_image("preview", "png-data-here")
    assert_equal :image_op, cmd.type
    assert_equal :create_image, cmd.payload[:op]
    assert_equal "preview", cmd.payload[:handle]
    assert_equal "png-data-here", cmd.payload[:data]
  end

  def test_commands_delete_image_construct
    cmd = C.delete_image("preview")
    assert_equal :image_op, cmd.type
    assert_equal :delete_image, cmd.payload[:op]
    assert_equal "preview", cmd.payload[:handle]
  end

  # -- Extension commands --

  def test_commands_extension_command_construct
    cmd = C.extension_command("term-1", "write", {data: "hello"})
    assert_equal :extension_command, cmd.type
    assert_equal "term-1", cmd.payload[:node_id]
    assert_equal "write", cmd.payload[:op]
    assert_equal({data: "hello"}, cmd.payload[:data])
  end

  # -- Animation --

  def test_commands_advance_frame_construct
    cmd = C.advance_frame(16)
    assert_equal :advance_frame, cmd.type
    assert_equal 16, cmd.payload[:timestamp]
  end

  # -- Subscription constructs --

  def test_subscription_every_construct
    sub = Plushie::Subscription.every(1000, :tick)
    assert_equal :every, sub.type
    assert_equal :tick, sub.tag
    assert_equal 1000, sub.interval
  end

  def test_subscription_on_key_press_construct
    sub = Plushie::Subscription.on_key_press(:key_event)
    assert_equal :on_key_press, sub.type
    assert_equal :key_event, sub.tag
  end

  def test_subscription_on_mouse_move_with_max_rate
    sub = Plushie::Subscription.on_mouse_move(:mouse, max_rate: 30)
    assert_equal :on_mouse_move, sub.type
    assert_equal :mouse, sub.tag
    assert_equal 30, sub.max_rate
  end
end
