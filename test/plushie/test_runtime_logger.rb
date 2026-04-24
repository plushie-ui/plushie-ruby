# frozen_string_literal: true

require "test_helper"

class TestRuntimeLogger < Minitest::Test
  class LoggerApp
    def settings = {}
    def init(_opts) = nil
    def update(model, _event) = model
    def view(_model) = nil
  end

  class BridgeDouble
    def start(settings: {})
    end
  end

  def test_log_level_configures_sdk_logger
    runtime = Plushie::Runtime.new(app: LoggerApp.new, log_level: :debug)

    assert_equal Logger::DEBUG, runtime.logger.level
  end

  def test_default_log_level_keeps_sdk_logger_at_warn
    runtime = Plushie::Runtime.new(app: LoggerApp.new)

    assert_equal Logger::WARN, runtime.logger.level
  end

  def test_default_log_level_keeps_renderer_fallback_at_error
    runtime = Plushie::Runtime.new(app: LoggerApp.new)

    assert_equal :error, runtime.instance_variable_get(:@log_level)
  end

  def test_default_renderer_log_level_passes_to_bridge
    runtime = Plushie::Runtime.new(app: LoggerApp.new)
    bridge_args = nil

    Plushie::Bridge.stub(:new, ->(**kwargs) {
      bridge_args = kwargs
      BridgeDouble.new
    }) do
      runtime.send(:start_bridge)
    end

    refute_includes bridge_args.keys, :log_level
  end

  def test_explicit_error_log_level_configures_sdk_logger
    runtime = Plushie::Runtime.new(app: LoggerApp.new, log_level: :error)

    assert_equal Logger::ERROR, runtime.logger.level
  end

  def test_explicit_log_level_passes_to_bridge
    runtime = Plushie::Runtime.new(app: LoggerApp.new, log_level: :debug)
    bridge_args = nil

    Plushie::Bridge.stub(:new, ->(**kwargs) {
      bridge_args = kwargs
      BridgeDouble.new
    }) do
      runtime.send(:start_bridge)
    end

    assert_equal :debug, bridge_args[:log_level]
  end

  def test_warning_log_level_alias_configures_sdk_logger
    runtime = Plushie::Runtime.new(app: LoggerApp.new, log_level: :warning)

    assert_equal Logger::WARN, runtime.logger.level
  end
end
