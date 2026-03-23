# frozen_string_literal: true

require "test_helper"

class TestCommand < Minitest::Test
  C = Plushie::Command

  # -- Basic ---------------------------------------------------------------

  def test_none
    cmd = C.none
    assert_equal :none, cmd.type
  end

  def test_async
    cmd = C.async(-> { "result" }, :fetch)
    assert_equal :async, cmd.type
    assert_equal :fetch, cmd.payload[:tag]
  end

  def test_stream
    cmd = C.stream(->(emit) { emit.call("chunk") }, :import)
    assert_equal :stream, cmd.type
  end

  def test_cancel
    cmd = C.cancel(:fetch)
    assert_equal :cancel, cmd.type
    assert_equal :fetch, cmd.payload[:tag]
  end

  def test_done
    cmd = C.done(42, ->(v) { [:result, v] })
    assert_equal :done, cmd.type
    assert_equal 42, cmd.payload[:value]
  end

  def test_send_after
    cmd = C.send_after(3000, :clear)
    assert_equal :send_after, cmd.type
    assert_equal 3000, cmd.payload[:delay]
  end

  def test_exit
    cmd = C.exit
    assert_equal :exit, cmd.type
  end

  def test_batch
    cmds = C.batch([C.focus("a"), C.focus("b")])
    assert_equal :batch, cmds.type
    assert_equal 2, cmds.payload[:commands].length
  end

  # -- Focus ---------------------------------------------------------------

  def test_focus
    cmd = C.focus("input_field")
    assert_equal :focus, cmd.type
    assert_equal "input_field", cmd.payload[:target]
  end

  def test_focus_next
    assert_equal :focus_next, C.focus_next.type
  end

  def test_focus_previous
    assert_equal :focus_previous, C.focus_previous.type
  end

  # -- Text editing --------------------------------------------------------

  def test_select_all
    cmd = C.select_all("editor")
    assert_equal :select_all, cmd.type
    assert_equal "editor", cmd.payload[:target]
  end

  def test_move_cursor_to_front
    assert_equal :move_cursor_to_front, C.move_cursor_to_front("ed").type
  end

  def test_move_cursor_to_end
    assert_equal :move_cursor_to_end, C.move_cursor_to_end("ed").type
  end

  def test_move_cursor_to
    cmd = C.move_cursor_to("ed", 5)
    assert_equal :move_cursor_to, cmd.type
    assert_equal 5, cmd.payload[:position]
  end

  def test_select_range
    cmd = C.select_range("ed", 2, 8)
    assert_equal :select_range, cmd.type
    assert_equal 2, cmd.payload[:start]
    assert_equal 8, cmd.payload[:end]
  end

  # -- Scroll --------------------------------------------------------------

  def test_scroll_to
    cmd = C.scroll_to("list", 100)
    assert_equal :scroll_to, cmd.type
  end

  def test_snap_to
    cmd = C.snap_to("list", 0.0, 1.0)
    assert_equal :snap_to, cmd.type
  end

  def test_snap_to_end
    assert_equal :snap_to_end, C.snap_to_end("list").type
  end

  def test_scroll_by
    cmd = C.scroll_by("list", 0, 50)
    assert_equal :scroll_by, cmd.type
  end

  # -- Window ops ----------------------------------------------------------

  def test_close_window
    cmd = C.close_window("settings")
    assert_equal :close_window, cmd.type
    assert_equal "settings", cmd.payload[:window_id]
  end

  def test_resize_window
    cmd = C.resize_window("main", 800, 600)
    assert_equal :window_op, cmd.type
    assert_equal :resize, cmd.payload[:op]
  end

  def test_maximize_window
    cmd = C.maximize_window("main")
    assert_equal true, cmd.payload[:maximized]
  end

  def test_minimize_window
    cmd = C.minimize_window("main", false)
    assert_equal false, cmd.payload[:minimized]
  end

  def test_set_window_mode
    cmd = C.set_window_mode("main", :fullscreen)
    assert_equal :set_mode, cmd.payload[:op]
    assert_equal "fullscreen", cmd.payload[:mode]
  end

  def test_toggle_maximize
    assert_equal :toggle_maximize, C.toggle_maximize("main").payload[:op]
  end

  def test_toggle_decorations
    assert_equal :toggle_decorations, C.toggle_decorations("main").payload[:op]
  end

  def test_gain_focus
    assert_equal :gain_focus, C.gain_focus("main").payload[:op]
  end

  def test_set_window_level
    cmd = C.set_window_level("main", :always_on_top)
    assert_equal "always_on_top", cmd.payload[:level]
  end

  def test_drag_window
    assert_equal :drag, C.drag_window("main").payload[:op]
  end

  def test_set_resizable
    cmd = C.set_resizable("main", false)
    assert_equal false, cmd.payload[:resizable]
  end

  def test_set_min_max_size
    cmd = C.set_min_size("main", 400, 300)
    assert_equal :set_min_size, cmd.payload[:op]
    assert_equal 400, cmd.payload[:width]

    cmd = C.set_max_size("main", 1920, 1080)
    assert_equal :set_max_size, cmd.payload[:op]
  end

  def test_mouse_passthrough
    assert_equal true, C.enable_mouse_passthrough("main").payload[:enabled]
    assert_equal false, C.disable_mouse_passthrough("main").payload[:enabled]
  end

  def test_set_icon
    cmd = C.set_icon("main", "\x00" * 16, 2, 2)
    assert_equal :set_icon, cmd.payload[:op]
    assert_equal 2, cmd.payload[:width]
  end

  def test_allow_automatic_tabbing
    cmd = C.allow_automatic_tabbing(false)
    assert_equal false, cmd.payload[:enabled]
    assert_equal "_global", cmd.payload[:window_id]
  end

  # -- Window queries ------------------------------------------------------

  def test_get_window_size
    cmd = C.get_window_size("main", :size_check)
    assert_equal :window_query, cmd.type
    assert_equal :get_size, cmd.payload[:op]
  end

  def test_get_system_theme
    cmd = C.get_system_theme(:theme)
    assert_equal :window_query, cmd.type
    assert_equal :get_system_theme, cmd.payload[:op]
    assert_equal "_system", cmd.payload[:window_id]
  end

  # -- PaneGrid ------------------------------------------------------------

  def test_pane_split
    cmd = C.pane_split("grid", "p1", :horizontal, "p2")
    assert_equal :widget_op, cmd.type
    assert_equal :pane_split, cmd.payload[:op]
  end

  def test_pane_close
    cmd = C.pane_close("grid", "p1")
    assert_equal :pane_close, cmd.payload[:op]
  end

  # -- Image ops -----------------------------------------------------------

  def test_create_image_with_data
    cmd = C.create_image("img1", "png_bytes")
    assert_equal :image_op, cmd.type
    assert_equal :create_image, cmd.payload[:op]
    assert_equal "png_bytes", cmd.payload[:data]
  end

  def test_create_image_with_pixels
    cmd = C.create_image("img1", pixels: "\x00" * 16, width: 2, height: 2)
    assert_equal "\x00" * 16, cmd.payload[:pixels]
    assert_equal 2, cmd.payload[:width]
  end

  def test_delete_image
    cmd = C.delete_image("img1")
    assert_equal :delete_image, cmd.payload[:op]
  end

  def test_clear_images
    cmd = C.clear_images
    assert_equal :clear_images, cmd.payload[:op]
  end

  # -- Widget queries ------------------------------------------------------

  def test_tree_hash
    cmd = C.tree_hash(:hash_check)
    assert_equal :tree_hash, cmd.payload[:op]
    assert_equal "hash_check", cmd.payload[:tag]
  end

  def test_find_focused
    cmd = C.find_focused(:focus_check)
    assert_equal :find_focused, cmd.payload[:op]
    assert_equal "focus_check", cmd.payload[:tag]
  end

  def test_list_images_stringifies_tag
    cmd = C.list_images(:img_list)
    assert_equal :list_images, cmd.payload[:op]
    assert_equal "img_list", cmd.payload[:tag]
  end

  def test_get_system_info
    cmd = C.get_system_info(:info)
    assert_equal :window_query, cmd.type
    assert_equal :get_system_info, cmd.payload[:op]
    assert_equal "_system", cmd.payload[:window_id]
  end

  # -- Font ----------------------------------------------------------------

  def test_load_font
    cmd = C.load_font("ttf_bytes")
    assert_equal :load_font, cmd.payload[:op]
  end

  # -- Accessibility -------------------------------------------------------

  def test_announce
    cmd = C.announce("Item saved")
    assert_equal :announce, cmd.payload[:op]
    assert_equal "Item saved", cmd.payload[:text]
  end

  # -- Extension -----------------------------------------------------------

  def test_extension_command
    cmd = C.extension_command("chart-1", "append", {values: [1, 2]})
    assert_equal :extension_command, cmd.type
    assert_equal "chart-1", cmd.payload[:node_id]
  end

  def test_extension_commands
    cmd = C.extension_commands([{node_id: "a", op: "push", payload: {}}])
    assert_equal :extension_commands, cmd.type
  end

  # -- Test / headless -----------------------------------------------------

  def test_advance_frame
    cmd = C.advance_frame(16000)
    assert_equal :advance_frame, cmd.type
    assert_equal 16000, cmd.payload[:timestamp]
  end
end
