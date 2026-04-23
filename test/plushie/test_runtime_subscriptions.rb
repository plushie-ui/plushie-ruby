# frozen_string_literal: true

require "test_helper"
require "json"

class TestRuntimeSubscriptions < Minitest::Test
  Sub = Plushie::Subscription

  # Minimal mock bridge that records messages.
  class MockBridge
    attr_reader :messages

    def initialize
      @messages = []
    end

    def send_encoded(data)
      @messages << data
    end
  end

  # Fake app whose subscribe method returns whatever we tell it to.
  class FakeApp
    attr_accessor :subs

    def initialize
      @subs = []
    end

    def subscribe(_model)
      @subs
    end
  end

  # Harness that includes the Subscriptions module with just enough state.
  class SubRunner
    include Plushie::Runtime::Subscriptions

    attr_reader :bridge, :event_queue, :subscriptions, :subscription_keys

    def initialize(bridge:, app:)
      @bridge = bridge
      @app = app
      @model = {}
      @format = :json
      @event_queue = Thread::Queue.new
      @subscriptions = {}
      @subscription_keys = []
      @logger = Logger.new(IO::NULL)
      @timer_scheduler = Plushie::TimerScheduler.new
    end

    # Expose private methods for testing.
    public :sync_subscriptions, :start_subscription, :stop_subscription

    def stop_timer(tag)
      @timer_scheduler.cancel(tag)
    end
  end

  def setup
    @bridge = MockBridge.new
    @app = FakeApp.new
    @runner = SubRunner.new(bridge: @bridge, app: @app)
  end

  def teardown
    @runner.subscriptions.each_value do |entry|
      @runner.stop_timer(entry[:tag]) if entry[:sub_type] == :timer
    end
  end

  # -- Adding a renderer subscription sends subscribe ---------------------

  def test_adding_renderer_subscription_sends_subscribe
    @app.subs = [Sub.on_key_press]
    @runner.sync_subscriptions

    assert_equal 1, @bridge.messages.length
    assert_equal 1, @runner.subscriptions.length
  end

  # -- Removing a subscription sends unsubscribe --------------------------

  def test_removing_subscription_sends_unsubscribe
    @app.subs = [Sub.on_key_press]
    @runner.sync_subscriptions

    @bridge.messages.clear
    @app.subs = []
    @runner.sync_subscriptions

    # Should have sent an unsubscribe message
    assert_equal 1, @bridge.messages.length
    decoded = JSON.parse(@bridge.messages.first)
    assert_equal "unsubscribe", decoded["type"]
    assert_equal "on_key_press", decoded["kind"]
    assert_equal "on_key_press", decoded["tag"]
    assert_empty @runner.subscriptions
  end

  # -- Timer subscription spawns a thread ----------------------------------

  def test_timer_subscription_spawns_thread
    @app.subs = [Sub.every(100, :tick)]
    @runner.sync_subscriptions

    entry = @runner.subscriptions.values.first
    assert_equal :timer, entry[:sub_type]
    assert_equal :tick, entry[:tag]

    @runner.stop_timer(entry[:tag])
  end

  # -- Short-circuit when key list unchanged --------------------------------

  def test_short_circuit_when_keys_unchanged
    @app.subs = [Sub.on_key_press]
    @runner.sync_subscriptions
    @bridge.messages.clear

    # Sync again with same subs: should not send anything
    @runner.sync_subscriptions
    assert_empty @bridge.messages
  end

  # -- Max rate update re-sends subscribe ----------------------------------

  def test_max_rate_update_resends_subscribe
    @app.subs = [Sub.on_key_press(max_rate: 10)]
    @runner.sync_subscriptions
    @bridge.messages.clear

    # Change max_rate on same sub key
    @app.subs = [Sub.on_key_press(max_rate: 30)]
    @runner.sync_subscriptions

    # Should have re-sent a subscribe with the new rate
    assert_equal 1, @bridge.messages.length
  end
end
