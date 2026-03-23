# frozen_string_literal: true

require "test_helper"

class DocsEventsTest < Minitest::Test
  E = Plushie::Event

  # -- Widget events --

  def test_events_widget_click_construct
    event = E::Widget.new(type: :click, id: "save")
    assert_equal :click, event.type
    assert_equal "save", event.id
  end

  def test_events_widget_input_match
    event = E::Widget.new(type: :input, id: "search", value: "hello")
    case event
    in E::Widget[type: :input, id: "search", value:]
      assert_equal "hello", value
    else
      flunk "expected input event to match"
    end
  end

  def test_events_widget_submit_match
    event = E::Widget.new(type: :submit, id: "search", value: "query")
    case event
    in E::Widget[type: :submit, id: "search", value:]
      assert_equal "query", value
    else
      flunk "expected submit event to match"
    end
  end

  def test_events_widget_toggle_match
    event = E::Widget.new(type: :toggle, id: "dark_mode", value: true)
    case event
    in E::Widget[type: :toggle, id: "dark_mode", value:]
      assert_equal true, value
    else
      flunk "expected toggle event to match"
    end
  end

  def test_events_widget_select_match
    event = E::Widget.new(type: :select, id: "theme_picker", value: "ocean")
    case event
    in E::Widget[type: :select, id: "theme_picker", value:]
      assert_equal "ocean", value
    else
      flunk "expected select event to match"
    end
  end

  def test_events_widget_slide_match
    event = E::Widget.new(type: :slide, id: "volume", value: 75)
    case event
    in E::Widget[type: :slide, id: "volume", value:]
      assert_equal 75, value
    else
      flunk "expected slide event to match"
    end
  end

  # -- Key events --

  def test_events_key_press_cmd_s_match
    event = E::Key.new(type: :press, key: "s", modifiers: {command: true, shift: false})
    case event
    in E::Key[type: :press, key: "s", modifiers: {command: true, **}]
      pass
    else
      flunk "expected Cmd+S key event to match"
    end
  end

  def test_events_key_press_escape_match
    event = E::Key.new(type: :press, key: :escape)
    case event
    in E::Key[type: :press, key: :escape]
      pass
    else
      flunk "expected escape key event to match"
    end
  end

  # -- Timer events --

  def test_events_timer_tick_match
    event = E::Timer.new(tag: :tick, timestamp: 12345)
    case event
    in E::Timer[tag: :tick, timestamp:]
      assert_equal 12345, timestamp
    else
      flunk "expected timer event to match"
    end
  end

  # -- Async events --

  def test_events_async_result_ok_match
    event = E::Async.new(tag: :data_loaded, result: [:ok, "payload"])
    case event
    in E::Async[tag: :data_loaded, result: [:ok, body]]
      assert_equal "payload", body
    else
      flunk "expected async ok event to match"
    end
  end

  # -- Effect events --

  def test_events_effect_response_ok_match
    event = E::Effect.new(request_id: "ef_1234", result: [:ok, "/path/to/file"])
    case event
    in E::Effect[request_id: "ef_1234", result: [:ok, data]]
      assert_equal "/path/to/file", data
    else
      flunk "expected effect ok event to match"
    end
  end

  # -- Scope matching --

  def test_events_scope_sidebar_match
    event = E::Widget.new(type: :click, id: "save", scope: ["sidebar", "app"])
    case event
    in E::Widget[type: :click, id: "save", scope: ["sidebar", *]]
      pass
    else
      flunk "expected sidebar scope to match"
    end
  end

  def test_events_scope_main_match
    event = E::Widget.new(type: :click, id: "save", scope: ["main", "app"])
    case event
    in E::Widget[type: :click, id: "save", scope: ["main", *]]
      pass
    else
      flunk "expected main scope to match"
    end
  end

  # -- Widget scroll event --

  def test_events_widget_scroll_data_match
    data = {
      "absolute_x" => 0.0, "absolute_y" => 150.0,
      "relative_x" => 0.0, "relative_y" => 0.99,
      "bounds_width" => 400.0, "bounds_height" => 300.0,
      "content_width" => 400.0, "content_height" => 1200.0
    }
    event = E::Widget.new(type: :scroll, id: "log_view", data: data)
    case event
    in E::Widget[type: :scroll, id: "log_view", data:]
      at_bottom = data["relative_y"] >= 0.99
      assert at_bottom
    else
      flunk "expected scroll event to match"
    end
  end

  # -- Widget paste event --

  def test_events_widget_paste_match
    event = E::Widget.new(type: :paste, id: "url_input", value: "https://example.com")
    case event
    in E::Widget[type: :paste, id: "url_input", value:]
      assert_equal "https://example.com", value
    else
      flunk "expected paste event to match"
    end
  end

  # -- Widget sort event --

  def test_events_widget_sort_match
    event = E::Widget.new(type: :sort, id: "users", value: "name")
    case event
    in E::Widget[type: :sort, id: "users", value:]
      assert_equal "name", value
    else
      flunk "expected sort event to match"
    end
  end

  # -- Widget open/close events --

  def test_events_widget_open_match
    event = E::Widget.new(type: :open, id: "country_picker")
    case event
    in E::Widget[type: :open, id: "country_picker"]
      pass
    else
      flunk "expected open event to match"
    end
  end

  def test_events_widget_close_match
    event = E::Widget.new(type: :close, id: "country_picker")
    case event
    in E::Widget[type: :close, id: "country_picker"]
      pass
    else
      flunk "expected close event to match"
    end
  end

  # -- Canvas shape events --

  def test_events_canvas_shape_click_match
    event = E::Widget.new(type: :canvas_shape_click, id: "chart",
      data: {"shape_id" => "bar-jan", "x" => 10.0, "y" => 20.0})
    case event
    in E::Widget[type: :canvas_shape_click, id: "chart", data:]
      assert_equal "bar-jan", data["shape_id"]
    else
      flunk "expected canvas_shape_click event to match"
    end
  end

  def test_events_canvas_shape_enter_match
    event = E::Widget.new(type: :canvas_shape_enter, id: "chart",
      data: {"shape_id" => "bar-jan"})
    case event
    in E::Widget[type: :canvas_shape_enter, id: "chart", data:]
      assert_equal "bar-jan", data["shape_id"]
    else
      flunk "expected canvas_shape_enter event to match"
    end
  end

  # -- Mouse area events --

  def test_events_mouse_area_enter_match
    event = E::MouseArea.new(type: :enter, id: "hover_zone")
    case event
    in E::MouseArea[type: :enter, id: "hover_zone"]
      pass
    else
      flunk "expected mouse area enter event to match"
    end
  end

  def test_events_mouse_area_move_match
    event = E::MouseArea.new(type: :move, id: "canvas_area", x: 100.5, y: 200.3)
    case event
    in E::MouseArea[type: :move, id: "canvas_area", x:, y:]
      assert_equal 100.5, x
      assert_equal 200.3, y
    else
      flunk "expected mouse area move event to match"
    end
  end

  # -- Canvas events --

  def test_events_canvas_press_match
    event = E::Canvas.new(type: :press, id: "draw_area", x: 50.0, y: 75.0, button: "left")
    case event
    in E::Canvas[type: :press, id: "draw_area", x:, y:, button: "left"]
      assert_equal 50.0, x
      assert_equal 75.0, y
    else
      flunk "expected canvas press event to match"
    end
  end

  def test_events_canvas_move_match
    event = E::Canvas.new(type: :move, id: "draw_area", x: 60.0, y: 80.0)
    case event
    in E::Canvas[type: :move, id: "draw_area", x:, y:]
      assert_equal 60.0, x
      assert_equal 80.0, y
    else
      flunk "expected canvas move event to match"
    end
  end

  # -- Sensor resize event --

  def test_events_sensor_resize_match
    event = E::Sensor.new(type: :resize, id: "content_area", width: 800.0, height: 600.0)
    case event
    in E::Sensor[type: :resize, id: "content_area", width:, height:]
      assert_equal 800.0, width
      assert_equal 600.0, height
    else
      flunk "expected sensor resize event to match"
    end
  end

  # -- Pane events --

  def test_events_pane_resized_match
    event = E::Pane.new(type: :resized, id: "editor", split: :horizontal, ratio: 0.5)
    case event
    in E::Pane[type: :resized, id: "editor", split:, ratio:]
      assert_equal :horizontal, split
      assert_equal 0.5, ratio
    else
      flunk "expected pane resized event to match"
    end
  end

  def test_events_pane_clicked_match
    event = E::Pane.new(type: :clicked, id: "editor", pane: "left")
    case event
    in E::Pane[type: :clicked, id: "editor", pane:]
      assert_equal "left", pane
    else
      flunk "expected pane clicked event to match"
    end
  end

  # -- Key release event --

  def test_events_key_release_match
    event = E::Key.new(type: :release, key: :escape)
    case event
    in E::Key[type: :release, key: :escape]
      pass
    else
      flunk "expected key release event to match"
    end
  end

  # -- Modifiers changed event --

  def test_events_modifiers_changed_match
    event = E::Modifiers.new(modifiers: {shift: true, ctrl: false, alt: false, logo: false, command: false})
    case event
    in E::Modifiers[modifiers: {shift: true, **}]
      pass
    else
      flunk "expected modifiers changed event to match"
    end
  end

  # -- Mouse events (global) --

  def test_events_mouse_cursor_moved_match
    event = E::Mouse.new(type: :moved, x: 320.0, y: 240.0)
    case event
    in E::Mouse[type: :moved, x:, y:]
      assert_equal 320.0, x
      assert_equal 240.0, y
    else
      flunk "expected mouse moved event to match"
    end
  end

  def test_events_mouse_button_pressed_match
    event = E::Mouse.new(type: :button_pressed, button: :left)
    case event
    in E::Mouse[type: :button_pressed, button: :left]
      pass
    else
      flunk "expected mouse button_pressed event to match"
    end
  end

  def test_events_mouse_wheel_scrolled_match
    event = E::Mouse.new(type: :wheel_scrolled, delta_x: 0.0, delta_y: -3.0, unit: :line)
    case event
    in E::Mouse[type: :wheel_scrolled, delta_x:, delta_y:, unit: :line]
      assert_equal 0.0, delta_x
      assert_equal(-3.0, delta_y)
    else
      flunk "expected mouse wheel_scrolled event to match"
    end
  end

  # -- Touch event --

  def test_events_touch_finger_pressed_match
    event = E::Touch.new(type: :pressed, finger_id: 0, x: 100.0, y: 200.0)
    case event
    in E::Touch[type: :pressed, finger_id:, x:, y:]
      assert_equal 0, finger_id
      assert_equal 100.0, x
      assert_equal 200.0, y
    else
      flunk "expected touch finger_pressed event to match"
    end
  end

  # -- IME events --

  def test_events_ime_preedit_match
    event = E::Ime.new(type: :preedit, text: "\u304B", cursor: [0, 1])
    case event
    in E::Ime[type: :preedit, text:, cursor:]
      assert_equal "\u304B", text
      assert_equal [0, 1], cursor
    else
      flunk "expected IME preedit event to match"
    end
  end

  def test_events_ime_commit_match
    event = E::Ime.new(type: :commit, text: "\u304B")
    case event
    in E::Ime[type: :commit, text:]
      assert_equal "\u304B", text
    else
      flunk "expected IME commit event to match"
    end
  end

  # -- Window events --

  def test_events_window_close_requested_match
    event = E::Window.new(type: :close_requested, window_id: "main")
    case event
    in E::Window[type: :close_requested, window_id: "main"]
      pass
    else
      flunk "expected window close_requested event to match"
    end
  end

  def test_events_window_resized_match
    event = E::Window.new(type: :resized, window_id: "main", width: 1024.0, height: 768.0)
    case event
    in E::Window[type: :resized, window_id: "main", width:, height:]
      assert_equal 1024.0, width
      assert_equal 768.0, height
    else
      flunk "expected window resized event to match"
    end
  end

  def test_events_window_file_dropped_match
    event = E::Window.new(type: :file_dropped, window_id: "main", path: "/tmp/data.csv")
    case event
    in E::Window[type: :file_dropped, window_id: "main", path:]
      assert_equal "/tmp/data.csv", path
    else
      flunk "expected window file_dropped event to match"
    end
  end

  # -- System events --

  def test_events_system_animation_frame_match
    event = E::System.new(type: :animation_frame, data: 16.67)
    case event
    in E::System[type: :animation_frame, data: timestamp]
      assert_equal 16.67, timestamp
    else
      flunk "expected system animation_frame event to match"
    end
  end

  def test_events_system_theme_changed_match
    event = E::System.new(type: :theme_changed, data: "dark")
    case event
    in E::System[type: :theme_changed, data: mode]
      assert_equal "dark", mode
    else
      flunk "expected system theme_changed event to match"
    end
  end
end
