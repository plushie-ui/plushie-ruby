# frozen_string_literal: true

require "test_helper"
require "plushie/test"

class TestTestSession < Minitest::Test
  Model = Plushie::Model.define(:count)

  class EventProcessingApp
    include Plushie::App

    def update(model, event)
      case event.id
      when "increment"
        model.with(count: model.count + 1)
      when "fail"
        raise ArgumentError, "update failed for #{event.id}"
      else
        model
      end
    end

    def view(model)
      window("main", title: "Test") do
        text("count", model.count.to_s)
      end
    end
  end

  class PoolStub
    attr_reader :messages

    def initialize
      @messages = []
    end

    def send_message(message, session_id)
      @messages << [message, session_id]
    end
  end

  def test_process_events_batch_warns_without_debug
    session = build_session
    events = [
      Plushie::Event::Widget.new(type: :click, id: "increment"),
      Plushie::Event::Widget.new(type: :click, id: "fail")
    ]

    _stdout, stderr = without_debug do
      capture_io { session.send(:process_events_batch, events) }
    end

    assert_equal 1, session.model.count
    assert_includes stderr, "plushie test: error processing event"
    assert_includes stderr, "id=\"fail\""
    assert_includes stderr, "ArgumentError: update failed for fail"
  end

  def test_process_events_individually_warns_without_debug
    session = build_session
    events = [
      Plushie::Event::Widget.new(type: :click, id: "increment"),
      Plushie::Event::Widget.new(type: :click, id: "fail")
    ]

    _stdout, stderr = without_debug do
      capture_io { session.send(:process_events_individually, events) }
    end

    assert_equal 1, session.model.count
    assert_equal 1, session.instance_variable_get(:@pool).messages.length
    assert_includes stderr, "plushie test: error processing event"
    assert_includes stderr, "id=\"fail\""
    assert_includes stderr, "ArgumentError: update failed for fail"
  end

  def test_process_commands_sync_warns_when_task_event_update_fails_without_debug
    session = build_session
    command = Plushie::Command.task(-> { "loaded" }, :loaded)

    _stdout, stderr = without_debug do
      capture_io { session.send(:process_commands_sync, command) }
    end

    assert_equal 0, session.model.count
    assert_includes stderr, "plushie test: error processing event"
    assert_includes stderr, "Event::Async"
    assert_includes stderr, "NoMethodError"
  end

  def test_process_commands_sync_warns_when_dispatch_event_update_fails_without_debug
    session = build_session
    command = Plushie::Command.dispatch("payload", ->(_value) { Plushie::Event::Widget.new(type: :click, id: "fail") })

    _stdout, stderr = without_debug do
      capture_io { session.send(:process_commands_sync, command) }
    end

    assert_equal 0, session.model.count
    assert_includes stderr, "plushie test: error processing event"
    assert_includes stderr, "id=\"fail\""
    assert_includes stderr, "ArgumentError: update failed for fail"
  end

  private

  def build_session
    Plushie::Test::Session.allocate.tap do |session|
      session.instance_variable_set(:@app, EventProcessingApp.new)
      session.instance_variable_set(:@model, Model.new(count: 0))
      session.instance_variable_set(:@tree, nil)
      session.instance_variable_set(:@diagnostics, [])
      session.instance_variable_set(:@pool, PoolStub.new)
      session.instance_variable_set(:@session_id, "session-test")
    end
  end

  def without_debug
    previous = $DEBUG
    $DEBUG = false
    yield
  ensure
    $DEBUG = previous
  end
end
