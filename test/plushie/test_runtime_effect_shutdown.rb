# frozen_string_literal: true

require "test_helper"

class TestRuntimeEffectShutdown < Minitest::Test
  class EffectApp
    include Plushie::App

    attr_reader :events

    def initialize
      @events = []
    end

    def init(_opts) = :model

    def update(model, event)
      @events << event
      model
    end

    def view(_model)
      window("main") { text("label", "ready") }
    end
  end

  class CommandingEffectApp < EffectApp
    def update(model, event)
      @events << event
      [model, Plushie::Effect.clipboard_read(:after_shutdown)]
    end
  end

  def runtime_for(app)
    runtime = Plushie::Runtime.new(app: app, transport: :spawn, format: :json)
    runtime.instance_variable_set(:@logger, Logger.new(IO::NULL))
    runtime.instance_variable_set(:@model, :model)
    runtime
  end

  def seed_pending_effect(runtime, wire_id: "effect-1", tag: :save)
    timer = Thread.new { sleep 60 }
    pending_effects = runtime.instance_variable_get(:@pending_effects)
    effect_ids = runtime.instance_variable_get(:@effect_ids)
    effect_kinds = runtime.instance_variable_get(:@effect_kinds)
    effect_tags = runtime.instance_variable_get(:@effect_tags)
    pending_effects[wire_id] = timer
    effect_ids[wire_id] = tag
    effect_kinds[wire_id] = "clipboard_read"
    effect_tags[tag] = wire_id
    timer
  end

  def test_shutdown_reports_pending_effect_as_cancelled
    app = EffectApp.new
    runtime = runtime_for(app)
    timer = seed_pending_effect(runtime)

    runtime.send(:shutdown)

    timer.join(0.1)
    refute timer.alive?
    assert_instance_of Plushie::Event::Effect, app.events.first
    assert_instance_of Plushie::Event::Effect::Result::Cancelled, app.events.first.result
  end

  def test_shutdown_reports_each_pending_effect_as_cancelled
    app = EffectApp.new
    runtime = runtime_for(app)
    timers = [
      seed_pending_effect(runtime, wire_id: "effect-1", tag: :save),
      seed_pending_effect(runtime, wire_id: "effect-2", tag: :load)
    ]

    runtime.send(:shutdown)

    timers.each do |timer|
      timer.join(0.1)
      refute timer.alive?
    end
    assert_equal [:save, :load], app.events.map(&:tag)
    assert app.events.all? { |event| event.result.is_a?(Plushie::Event::Effect::Result::Cancelled) }
  end

  def test_shutdown_does_not_execute_commands_returned_by_cancelled_effects
    app = CommandingEffectApp.new
    runtime = runtime_for(app)
    seed_pending_effect(runtime)

    runtime.send(:shutdown)

    assert_equal 1, app.events.length
    assert_empty runtime.instance_variable_get(:@pending_effects)
    assert_empty runtime.instance_variable_get(:@effect_tags)
  end

  def test_renderer_exit_flush_reports_pending_effect_as_renderer_restarted
    app = EffectApp.new
    runtime = runtime_for(app)
    timer = seed_pending_effect(runtime)

    runtime.send(
      :flush_pending_effects_on_exit,
      Plushie::Event::Effect::Result::RendererRestarted.new
    )

    timer.join(0.1)
    refute timer.alive?
    assert_instance_of Plushie::Event::Effect, app.events.first
    assert_instance_of(
      Plushie::Event::Effect::Result::RendererRestarted,
      app.events.first.result
    )
  ensure
    runtime&.instance_variable_get(:@timer_scheduler)&.stop
  end
end
