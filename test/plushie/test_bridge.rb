# frozen_string_literal: true

require "test_helper"

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

  def test_stop_waits_for_forwarder_thread_cleanup
    bridge = Plushie::Bridge.new(event_queue: Thread::Queue.new, heartbeat_interval: nil)
    forwarder = ThreadDouble.new
    bridge.instance_variable_set(:@forwarder_thread, forwarder)

    bridge.stop

    assert forwarder.killed
    assert_equal 1, forwarder.joined
  end

  def test_restart_is_not_reported_when_reconnect_fails
    event_queue = Thread::Queue.new
    bridge = Plushie::Bridge.new(
      event_queue: event_queue,
      transport: :unsupported,
      heartbeat_interval: nil
    )
    bridge.instance_variable_set(:@settings, {})
    bridge.define_singleton_method(:sleep) { |_delay| nil }

    bridge.send(:attempt_restart)

    exited = event_queue.pop(timeout: 0.1)
    assert_equal :renderer_exited, exited[0]
    refute_equal [:renderer_restarted], event_queue.pop(timeout: 0.05)
  end
end
