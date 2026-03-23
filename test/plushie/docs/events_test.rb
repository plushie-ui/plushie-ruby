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
end
