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
end
