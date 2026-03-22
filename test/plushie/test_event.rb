# frozen_string_literal: true

require "test_helper"

class TestEvent < Minitest::Test
  def test_widget_click_pattern_matching
    event = Plushie::Event::Widget.new(type: :click, id: "save")

    result = case event
    in Plushie::Event::Widget[type: :click, id: "save"]
      :matched
    else
      :no_match
    end

    assert_equal :matched, result
  end

  def test_widget_input_with_value
    event = Plushie::Event::Widget.new(type: :input, id: "search", value: "hello")

    result = case event
    in Plushie::Event::Widget[type: :input, id: "search", value:]
      value
    end

    assert_equal "hello", result
  end

  def test_widget_with_scope
    event = Plushie::Event::Widget.new(type: :click, id: "save", scope: ["form", "sidebar"])
    assert_equal "sidebar/form/save", Plushie::Event.target(event)
  end

  def test_widget_without_scope
    event = Plushie::Event::Widget.new(type: :click, id: "save")
    assert_equal "save", Plushie::Event.target(event)
  end

  def test_key_event_pattern_matching
    event = Plushie::Event::Key.new(
      type: :press,
      key: "s",
      modifiers: {command: true, shift: false, ctrl: false, alt: false, logo: false}
    )

    result = case event
    in Plushie::Event::Key[type: :press, key: "s", modifiers: {command: true}]
      :save
    else
      :other
    end

    assert_equal :save, result
  end

  def test_timer_event
    event = Plushie::Event::Timer.new(tag: :tick, timestamp: 1234)
    assert_equal :tick, event.tag
    assert_equal 1234, event.timestamp
  end

  def test_async_event
    event = Plushie::Event::Async.new(tag: :fetch, result: [:ok, "data"])
    assert_equal :fetch, event.tag
    assert_equal [:ok, "data"], event.result
  end
end
