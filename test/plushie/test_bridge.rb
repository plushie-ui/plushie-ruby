# frozen_string_literal: true

require "test_helper"
require "digest"

class TestBridge < Minitest::Test
  class ThreadDouble
    attr_reader :killed, :joined

    def kill
      @killed = true
    end

    def join(timeout = nil)
      @joined = timeout
    end
  end

  class ConnectionDouble
    attr_reader :hello

    def initialize
      @hello = {type: :hello, version: Plushie::PLUSHIE_RUST_VERSION}
    end

    def close
    end
  end

  def test_stop_waits_for_forwarder_thread_cleanup
    bridge = Plushie::Bridge.new(event_queue: Thread::Queue.new, heartbeat_interval: nil)
    forwarder = ThreadDouble.new
    bridge.instance_variable_set(:@forwarder_thread, forwarder)

    bridge.stop

    assert forwarder.killed
    assert_equal 1, forwarder.joined
  end

  def test_log_level_configures_sdk_logger
    bridge = Plushie::Bridge.new(event_queue: Thread::Queue.new, log_level: :debug, heartbeat_interval: nil)

    logger = bridge.instance_variable_get(:@logger)

    assert_equal Logger::DEBUG, logger.level
  end

  def test_warning_log_level_alias_configures_sdk_logger
    bridge = Plushie::Bridge.new(event_queue: Thread::Queue.new, log_level: :warning, heartbeat_interval: nil)

    logger = bridge.instance_variable_get(:@logger)

    assert_equal Logger::WARN, logger.level
  end

  def test_default_log_level_keeps_sdk_logger_at_warn
    bridge = Plushie::Bridge.new(event_queue: Thread::Queue.new, heartbeat_interval: nil)

    logger = bridge.instance_variable_get(:@logger)

    assert_equal Logger::WARN, logger.level
  end

  def test_default_log_level_keeps_renderer_fallback_at_error
    bridge = Plushie::Bridge.new(event_queue: Thread::Queue.new, heartbeat_interval: nil)

    assert_equal :error, bridge.instance_variable_get(:@log_level)
  end

  def test_default_renderer_log_level_passes_to_connection
    bridge = Plushie::Bridge.new(event_queue: Thread::Queue.new, heartbeat_interval: nil)
    connection_args = nil

    Plushie::Connection.stub(:spawn, ->(**kwargs) {
      connection_args = kwargs
      ConnectionDouble.new
    }) do
      bridge.start(settings: {})
    end

    assert_equal :error, connection_args[:log_level]
  ensure
    bridge&.stop
  end

  def test_token_is_sent_as_digest
    bridge = Plushie::Bridge.new(
      event_queue: Thread::Queue.new,
      token: "secret-123",
      heartbeat_interval: nil
    )
    connection_args = nil

    Plushie::Connection.stub(:spawn, ->(**kwargs) {
      connection_args = kwargs
      ConnectionDouble.new
    }) do
      bridge.start(settings: {title: "Test", token: "do-not-send"})
    end

    assert_equal Digest::SHA256.hexdigest("secret-123"), connection_args[:settings][:token_sha256]
    refute connection_args[:settings].key?(:token)
  ensure
    bridge&.stop
  end

  def test_explicit_error_log_level_configures_sdk_logger
    bridge = Plushie::Bridge.new(event_queue: Thread::Queue.new, log_level: :error, heartbeat_interval: nil)

    logger = bridge.instance_variable_get(:@logger)

    assert_equal Logger::ERROR, logger.level
  end

  def test_restart_is_not_reported_when_reconnect_fails
    event_queue = Thread::Queue.new
    bridge = Plushie::Bridge.new(
      event_queue: event_queue,
      transport: :unsupported,
      heartbeat_interval: nil
    )
    bridge.instance_variable_set(:@settings, {})
    bridge.instance_variable_set(:@logger, Logger.new(IO::NULL))
    bridge.define_singleton_method(:sleep) { |_delay| nil }

    bridge.send(:attempt_restart)

    exited = event_queue.pop(timeout: 0.1)
    assert_equal :renderer_exited, exited[0]
    refute_equal [:renderer_restarted], event_queue.pop(timeout: 0.05)
  end
end
