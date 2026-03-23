# frozen_string_literal: true

require "test_helper"

class TestProtocolDecode < Minitest::Test
  D = Plushie::Protocol::Decode

  # -- Widget events -------------------------------------------------------

  def test_decode_click
    event = D.decode_event({"family" => "click", "id" => "save"})
    assert_instance_of Plushie::Event::Widget, event
    assert_equal :click, event.type
    assert_equal "save", event.id
  end

  def test_decode_input_with_value
    event = D.decode_event({"family" => "input", "id" => "search", "value" => "hello"})
    assert_equal :input, event.type
    assert_equal "hello", event.value
  end

  def test_decode_scoped_id
    event = D.decode_event({"family" => "click", "id" => "form/sidebar/save"})
    assert_equal "save", event.id
    assert_equal ["sidebar", "form"], event.scope
  end

  def test_decode_submit
    event = D.decode_event({"family" => "submit", "id" => "field", "value" => "text"})
    assert_equal :submit, event.type
    assert_equal "text", event.value
  end

  def test_decode_toggle
    event = D.decode_event({"family" => "toggle", "id" => "cb", "value" => true})
    assert_equal :toggle, event.type
    assert_equal true, event.value
  end

  def test_decode_select
    event = D.decode_event({"family" => "select", "id" => "pick", "value" => "opt1"})
    assert_equal :select, event.type
  end

  def test_decode_slide
    event = D.decode_event({"family" => "slide", "id" => "vol", "value" => 0.5})
    assert_equal :slide, event.type
    assert_equal 0.5, event.value
  end

  def test_decode_slide_release
    event = D.decode_event({"family" => "slide_release", "id" => "vol", "value" => 0.7})
    assert_equal :slide_release, event.type
  end

  def test_decode_scroll
    event = D.decode_event({"family" => "scroll", "id" => "list", "data" => {"absolute_x" => 0, "relative_y" => 0.5}})
    assert_equal :scroll, event.type
    assert_equal 0.5, event.data["relative_y"]
  end

  def test_decode_canvas_element_click
    event = D.decode_event({"family" => "canvas_element_click", "id" => "chart", "data" => {"element_id" => "bar1"}})
    assert_equal :canvas_element_click, event.type
    assert_equal "bar1", event.data["element_id"]
  end

  def test_decode_paste
    event = D.decode_event({"family" => "paste", "id" => "input", "value" => "pasted"})
    assert_equal :paste, event.type
    assert_equal "pasted", event.value
  end

  def test_decode_sort
    event = D.decode_event({"family" => "sort", "id" => "table", "data" => {"column" => "name"}})
    assert_equal :sort, event.type
  end

  def test_decode_open_close
    open = D.decode_event({"family" => "open", "id" => "picker"})
    close = D.decode_event({"family" => "close", "id" => "picker"})
    assert_equal :open, open.type
    assert_equal :close, close.type
  end

  # -- Mouse area events ---------------------------------------------------

  def test_decode_mouse_right_press
    event = D.decode_event({"family" => "mouse_right_press", "id" => "area"})
    assert_instance_of Plushie::Event::MouseArea, event
    assert_equal :right_press, event.type
    assert_equal "area", event.id
  end

  def test_decode_mouse_move
    event = D.decode_event({"family" => "mouse_move", "id" => "zone", "data" => {"x" => 10, "y" => 20}})
    assert_instance_of Plushie::Event::MouseArea, event
    assert_equal :move, event.type
    assert_equal 10, event.x
    assert_equal 20, event.y
  end

  def test_decode_mouse_scroll
    event = D.decode_event({"family" => "mouse_scroll", "id" => "zone", "data" => {"delta_x" => 0, "delta_y" => -3}})
    assert_equal :scroll, event.type
    assert_equal(-3, event.delta_y)
  end

  def test_decode_mouse_enter_exit
    enter = D.decode_event({"family" => "mouse_enter", "id" => "hover"})
    exit_ev = D.decode_event({"family" => "mouse_exit", "id" => "hover"})
    assert_equal :enter, enter.type
    assert_equal :exit, exit_ev.type
  end

  # -- Canvas events -------------------------------------------------------

  def test_decode_canvas_press
    event = D.decode_event({"family" => "canvas_press", "id" => "draw", "data" => {"x" => 5, "y" => 10, "button" => "left"}})
    assert_instance_of Plushie::Event::Canvas, event
    assert_equal :press, event.type
    assert_equal "left", event.button
  end

  def test_decode_canvas_move
    event = D.decode_event({"family" => "canvas_move", "id" => "draw", "data" => {"x" => 15, "y" => 25}})
    assert_equal :move, event.type
    assert_equal 15, event.x
  end

  def test_decode_canvas_scroll
    event = D.decode_event({"family" => "canvas_scroll", "id" => "draw", "data" => {"x" => 0, "y" => 0, "delta_x" => 1, "delta_y" => -2}})
    assert_equal :scroll, event.type
    assert_equal(-2, event.delta_y)
  end

  # -- Pane events ---------------------------------------------------------

  def test_decode_pane_resized
    event = D.decode_event({"family" => "pane_resized", "id" => "grid", "data" => {"split" => "s1", "ratio" => 0.4}})
    assert_instance_of Plushie::Event::Pane, event
    assert_equal :resized, event.type
    assert_equal 0.4, event.ratio
  end

  def test_decode_pane_clicked
    event = D.decode_event({"family" => "pane_clicked", "id" => "grid", "data" => {"pane" => "p1"}})
    assert_equal :clicked, event.type
    assert_equal "p1", event.pane
  end

  # -- Sensor events -------------------------------------------------------

  def test_decode_sensor_resize
    event = D.decode_event({"family" => "sensor_resize", "id" => "sens", "data" => {"width" => 100, "height" => 200}})
    assert_instance_of Plushie::Event::Sensor, event
    assert_equal :resize, event.type
    assert_equal 100, event.width
  end

  # -- Keyboard events -----------------------------------------------------

  def test_decode_key_press
    event = D.decode_event({
      "family" => "key_press", "key" => "Escape",
      "modifiers" => {"shift" => false, "ctrl" => true, "alt" => false, "logo" => false, "command" => true}
    })
    assert_instance_of Plushie::Event::Key, event
    assert_equal :press, event.type
    assert_equal :escape, event.key
    assert_equal true, event.modifiers[:ctrl]
  end

  def test_decode_key_press_with_data_subobject
    event = D.decode_event({
      "family" => "key_press", "tag" => "keys",
      "data" => {"key" => "a", "text" => "a", "repeat" => false},
      "modifiers" => {}
    })
    assert_equal :press, event.type
    assert_equal "a", event.key
  end

  def test_decode_key_release
    event = D.decode_event({"family" => "key_release", "key" => "Enter", "modifiers" => {}})
    assert_equal :release, event.type
    assert_equal :enter, event.key
  end

  def test_decode_key_press_modified_key_parsed
    event = D.decode_event({
      "family" => "key_press", "key" => "a", "modified_key" => "A",
      "modifiers" => {"shift" => true, "ctrl" => false, "alt" => false, "logo" => false, "command" => false}
    })
    assert_equal "a", event.key
    assert_equal "A", event.modified_key
  end

  def test_decode_key_press_modified_key_falls_back_to_key
    event = D.decode_event({
      "family" => "key_press", "key" => "Escape",
      "modifiers" => {}
    })
    assert_equal :escape, event.key
    assert_equal :escape, event.modified_key
  end

  def test_decode_key_press_modified_key_named
    event = D.decode_event({
      "family" => "key_press", "key" => "a", "modified_key" => "Tab",
      "modifiers" => {}
    })
    assert_equal "a", event.key
    assert_equal :tab, event.modified_key
  end

  # -- Modifier events -----------------------------------------------------

  def test_decode_modifiers_changed
    event = D.decode_event({
      "family" => "modifiers_changed",
      "modifiers" => {"shift" => true, "ctrl" => false, "alt" => false, "logo" => false, "command" => false}
    })
    assert_instance_of Plushie::Event::Modifiers, event
    assert_equal true, event.modifiers[:shift]
  end

  # -- Mouse subscription events -------------------------------------------

  def test_decode_cursor_moved
    event = D.decode_event({"family" => "cursor_moved", "data" => {"x" => 100, "y" => 200}})
    assert_instance_of Plushie::Event::Mouse, event
    assert_equal :moved, event.type
    assert_equal 100, event.x
  end

  def test_decode_cursor_entered_left
    entered = D.decode_event({"family" => "cursor_entered"})
    left = D.decode_event({"family" => "cursor_left"})
    assert_equal :entered, entered.type
    assert_equal :left, left.type
  end

  def test_decode_button_pressed
    event = D.decode_event({"family" => "button_pressed", "value" => "right"})
    assert_equal :button_pressed, event.type
    assert_equal :right, event.button
  end

  def test_decode_wheel_scrolled
    event = D.decode_event({
      "family" => "wheel_scrolled",
      "data" => {"delta_x" => 0, "delta_y" => -3.0, "unit" => "line"}
    })
    assert_equal :wheel_scrolled, event.type
    assert_equal :line, event.unit
  end

  # -- Touch events --------------------------------------------------------

  def test_decode_finger_pressed
    event = D.decode_event({"family" => "finger_pressed", "data" => {"id" => 1, "x" => 50, "y" => 60}})
    assert_instance_of Plushie::Event::Touch, event
    assert_equal :pressed, event.type
    assert_equal 1, event.finger_id
  end

  def test_decode_finger_moved
    event = D.decode_event({"family" => "finger_moved", "data" => {"id" => 1, "x" => 55, "y" => 65}})
    assert_equal :moved, event.type
  end

  # -- IME events ----------------------------------------------------------

  def test_decode_ime_preedit
    event = D.decode_event({"family" => "ime_preedit", "data" => {"text" => "he", "cursor" => [0, 2]}})
    assert_instance_of Plushie::Event::Ime, event
    assert_equal :preedit, event.type
    assert_equal "he", event.text
  end

  def test_decode_ime_commit
    event = D.decode_event({"family" => "ime_commit", "data" => {"text" => "hello"}})
    assert_equal :commit, event.type
    assert_equal "hello", event.text
  end

  def test_decode_ime_opened_closed
    opened = D.decode_event({"family" => "ime_opened"})
    closed = D.decode_event({"family" => "ime_closed"})
    assert_equal :opened, opened.type
    assert_equal :closed, closed.type
  end

  # -- Window subscription events ------------------------------------------

  def test_decode_window_opened
    event = D.decode_event({
      "family" => "window_opened",
      "data" => {"window_id" => "main", "position" => {"x" => 100, "y" => 200}, "width" => 800, "height" => 600}
    })
    assert_instance_of Plushie::Event::Window, event
    assert_equal :opened, event.type
    assert_equal "main", event.window_id
    assert_equal 800, event.width
  end

  def test_decode_window_close_requested
    event = D.decode_event({"family" => "window_close_requested", "data" => {"window_id" => "main"}})
    assert_equal :close_requested, event.type
    assert_equal "main", event.window_id
  end

  def test_decode_window_resized
    event = D.decode_event({"family" => "window_resized", "data" => {"window_id" => "main", "width" => 1024, "height" => 768}})
    assert_equal :resized, event.type
    assert_equal 1024, event.width
  end

  def test_decode_file_dropped
    event = D.decode_event({"family" => "file_dropped", "data" => {"window_id" => "main", "path" => "/tmp/test.txt"}})
    assert_equal :file_dropped, event.type
    assert_equal "/tmp/test.txt", event.path
  end

  # -- System events -------------------------------------------------------

  def test_decode_animation_frame
    event = D.decode_event({"family" => "animation_frame", "data" => {"timestamp" => 16000}})
    assert_instance_of Plushie::Event::System, event
    assert_equal :animation_frame, event.type
    assert_equal 16000, event.data
  end

  def test_decode_theme_changed
    event = D.decode_event({"family" => "theme_changed", "value" => "dark"})
    assert_equal :theme_changed, event.type
    assert_equal "dark", event.data
  end

  def test_decode_all_windows_closed
    event = D.decode_event({"family" => "all_windows_closed"})
    assert_equal :all_windows_closed, event.type
  end

  def test_decode_error_event
    event = D.decode_event({"family" => "error", "id" => "dup", "data" => {"error" => "duplicate IDs"}})
    assert_equal :error, event.type
    assert_equal "duplicate IDs", event.data["error"]
  end

  def test_decode_announce
    event = D.decode_event({"family" => "announce", "data" => {"text" => "Item saved"}})
    assert_equal :announce, event.type
    assert_equal "Item saved", event.data
  end

  # -- Pane events (additional) --------------------------------------------

  def test_decode_pane_dragged_with_action_region_edge
    event = D.decode_event({
      "family" => "pane_dragged", "id" => "grid",
      "data" => {"pane" => "p1", "target" => "p2", "action" => "dropped", "region" => "center", "edge" => "left"}
    })
    assert_instance_of Plushie::Event::Pane, event
    assert_equal :dragged, event.type
    assert_equal "p1", event.pane
    assert_equal "p2", event.target
    assert_equal :dropped, event.action
    assert_equal :center, event.region
    assert_equal :left, event.edge
  end

  def test_decode_pane_focus_cycle
    event = D.decode_event({"family" => "pane_focus_cycle", "id" => "grid", "data" => {"pane" => "p3"}})
    assert_instance_of Plushie::Event::Pane, event
    assert_equal :focus_cycle, event.type
    assert_equal "p3", event.pane
  end

  # -- Session events ------------------------------------------------------

  def test_decode_session_error_with_session_id
    event = D.decode_event({"family" => "session_error", "session" => "test_1", "data" => {"error" => "invalid state"}})
    assert_instance_of Plushie::Event::System, event
    assert_equal :session_error, event.type
    assert_equal "test_1", event.tag
    assert_equal "invalid state", event.data
  end

  def test_decode_session_closed_with_session_id
    event = D.decode_event({"family" => "session_closed", "session" => "test_2", "data" => {"reason" => "timeout"}})
    assert_instance_of Plushie::Event::System, event
    assert_equal :session_closed, event.type
    assert_equal "test_2", event.tag
    assert_equal "timeout", event.data
  end

  # -- Window events (additional) ------------------------------------------

  def test_decode_window_moved
    event = D.decode_event({"family" => "window_moved", "data" => {"window_id" => "main", "x" => 50, "y" => 100}})
    assert_instance_of Plushie::Event::Window, event
    assert_equal :moved, event.type
    assert_equal "main", event.window_id
    assert_equal 50, event.x
    assert_equal 100, event.y
  end

  def test_decode_window_focused
    event = D.decode_event({"family" => "window_focused", "data" => {"window_id" => "main"}})
    assert_instance_of Plushie::Event::Window, event
    assert_equal :focused, event.type
    assert_equal "main", event.window_id
  end

  def test_decode_window_unfocused
    event = D.decode_event({"family" => "window_unfocused", "data" => {"window_id" => "main"}})
    assert_instance_of Plushie::Event::Window, event
    assert_equal :unfocused, event.type
    assert_equal "main", event.window_id
  end

  def test_decode_window_rescaled
    event = D.decode_event({"family" => "window_rescaled", "data" => {"window_id" => "main", "scale_factor" => 2.0}})
    assert_instance_of Plushie::Event::Window, event
    assert_equal :rescaled, event.type
    assert_equal "main", event.window_id
    assert_equal 2.0, event.scale_factor
  end

  def test_decode_files_hovered_left
    event = D.decode_event({"family" => "files_hovered_left", "data" => {"window_id" => "main"}})
    assert_instance_of Plushie::Event::Window, event
    assert_equal :files_hovered_left, event.type
    assert_equal "main", event.window_id
  end

  # -- Canvas events (additional) ------------------------------------------

  def test_decode_canvas_release
    event = D.decode_event({"family" => "canvas_release", "id" => "draw", "data" => {"x" => 30, "y" => 40, "button" => "right"}})
    assert_instance_of Plushie::Event::Canvas, event
    assert_equal :release, event.type
    assert_equal 30, event.x
    assert_equal 40, event.y
    assert_equal "right", event.button
  end

  # -- Key events (additional) --------------------------------------------

  def test_decode_key_release_hardcoded_text_nil_repeat_false
    event = D.decode_event({"family" => "key_release", "key" => "a", "modifiers" => {}})
    assert_instance_of Plushie::Event::Key, event
    assert_equal :release, event.type
    assert_equal "a", event.key
    assert_nil event.text
    assert_equal false, event.repeat
  end

  # -- Announce event (additional) -----------------------------------------

  def test_decode_announce_event_full
    event = D.decode_event({"family" => "announce", "data" => {"text" => "Record deleted"}})
    assert_instance_of Plushie::Event::System, event
    assert_equal :announce, event.type
    assert_equal "Record deleted", event.data
  end

  # -- IME events with id and scope ----------------------------------------

  def test_decode_ime_preedit_with_id_and_scope
    event = D.decode_event({
      "family" => "ime_preedit", "id" => "form/editor",
      "data" => {"text" => "ka", "cursor" => [0, 2]}
    })
    assert_instance_of Plushie::Event::Ime, event
    assert_equal :preedit, event.type
    assert_equal "editor", event.id
    assert_equal ["form"], event.scope
    assert_equal "ka", event.text
    assert_equal [0, 2], event.cursor
  end

  def test_decode_ime_commit_with_id_and_scope
    event = D.decode_event({
      "family" => "ime_commit", "id" => "panel/input",
      "data" => {"text" => "hello"}
    })
    assert_instance_of Plushie::Event::Ime, event
    assert_equal :commit, event.type
    assert_equal "input", event.id
    assert_equal ["panel"], event.scope
    assert_equal "hello", event.text
  end

  def test_decode_ime_opened_with_id_and_scope
    event = D.decode_event({"family" => "ime_opened", "id" => "sidebar/field"})
    assert_instance_of Plushie::Event::Ime, event
    assert_equal :opened, event.type
    assert_equal "field", event.id
    assert_equal ["sidebar"], event.scope
  end

  def test_decode_ime_closed_with_id_and_scope
    event = D.decode_event({"family" => "ime_closed", "id" => "sidebar/field"})
    assert_instance_of Plushie::Event::Ime, event
    assert_equal :closed, event.type
    assert_equal "field", event.id
    assert_equal ["sidebar"], event.scope
  end

  # -- Fallback (extension events) -----------------------------------------

  def test_decode_unknown_family_with_id
    event = D.decode_event({"family" => "extension_custom", "id" => "ext1", "value" => 42})
    assert_instance_of Plushie::Event::Widget, event
    assert_equal :extension_custom, event.type
    assert_equal 42, event.value
  end

  def test_decode_unknown_family_without_id
    event = D.decode_event({"family" => "totally_unknown"})
    assert_nil event
  end

  # -- Response decoders ---------------------------------------------------

  def test_decode_hello
    msg = {"type" => "hello", "protocol" => 1, "version" => "0.4.0", "name" => "plushie", "mode" => "mock", "backend" => "none", "extensions" => [], "transport" => "stdio"}
    result = D.decode_hello(msg)
    assert_equal :hello, result[:type]
    assert_equal 1, result[:protocol]
    assert_equal :mock, result[:mode]
  end

  def test_decode_effect_response_ok
    msg = {"type" => "effect_response", "id" => "ef_1", "status" => "ok", "result" => {"path" => "/tmp/f.txt"}}
    result = D.decode_effect_response(msg)
    assert_instance_of Plushie::Event::Effect, result
    assert_equal "ef_1", result.request_id
    assert_equal [:ok, {"path" => "/tmp/f.txt"}], result.result
  end

  def test_decode_effect_response_cancelled
    msg = {"type" => "effect_response", "id" => "ef_2", "status" => "cancelled"}
    result = D.decode_effect_response(msg)
    assert_equal :cancelled, result.result
  end

  def test_decode_effect_response_error
    msg = {"type" => "effect_response", "id" => "ef_3", "status" => "error", "error" => "no permission"}
    result = D.decode_effect_response(msg)
    assert_equal [:error, "no permission"], result.result
  end

  def test_decode_query_response
    msg = {"type" => "query_response", "id" => "q1", "target" => "find", "data" => {"id" => "btn1", "type" => "button"}}
    result = D.decode_query_response(msg)
    assert_equal :query_response, result[:type]
    assert_equal "btn1", result[:data]["id"]
  end

  def test_decode_op_query_response
    msg = {"type" => "op_query_response", "kind" => "system_theme", "tag" => "t1", "data" => "dark"}
    result = D.decode_op_query_response(msg)
    assert_equal :op_query_response, result[:type]
    assert_equal :system_theme, result[:kind]
    assert_equal "dark", result[:data]
  end

  def test_decode_interact_response_with_events
    msg = {
      "type" => "interact_response", "id" => "i1", "session" => "s1",
      "events" => [{"family" => "click", "id" => "btn"}]
    }
    result = D.decode_interact_response(msg)
    assert_equal :interact_response, result[:type]
    assert_equal 1, result[:events].length
    assert_equal :click, result[:events][0].type
  end

  def test_decode_interact_step
    msg = {
      "type" => "interact_step", "id" => "i1", "session" => "s1",
      "events" => [{"family" => "input", "id" => "f", "value" => "a"}]
    }
    result = D.decode_interact_step(msg)
    assert_equal :interact_step, result[:type]
    assert_equal "a", result[:events][0].value
  end

  def test_decode_tree_hash_response
    msg = {"type" => "tree_hash_response", "id" => "th1", "name" => "test", "hash" => "abc123"}
    result = D.decode_tree_hash_response(msg)
    assert_equal :tree_hash_response, result[:type]
    assert_equal "abc123", result[:hash]
  end

  def test_decode_screenshot_response
    msg = {"type" => "screenshot_response", "id" => "sc1", "name" => "page", "hash" => "def456", "width" => 1024, "height" => 768}
    result = D.decode_screenshot_response(msg)
    assert_equal :screenshot_response, result[:type]
    assert_equal 1024, result[:width]
  end

  def test_decode_reset_response
    msg = {"type" => "reset_response", "id" => "r1", "status" => "ok"}
    result = D.decode_reset_response(msg)
    assert_equal :reset_response, result[:type]
    assert_equal "ok", result[:status]
  end

  # -- Full round-trip via decode_message ----------------------------------

  def test_decode_message_dispatches_event
    json = '{"type":"event","family":"click","id":"btn1"}'
    result = D.decode_message(json, :json)
    assert_instance_of Plushie::Event::Widget, result
    assert_equal :click, result.type
  end

  def test_decode_message_dispatches_hello
    json = '{"type":"hello","protocol":1,"version":"0.4.0","name":"plushie","mode":"mock","backend":"none","extensions":[],"transport":"stdio"}'
    result = D.decode_message(json, :json)
    assert_equal :hello, result[:type]
  end

  def test_decode_message_dispatches_interact_response
    json = '{"type":"interact_response","id":"i1","session":"","events":[]}'
    result = D.decode_message(json, :json)
    assert_equal :interact_response, result[:type]
  end
end
