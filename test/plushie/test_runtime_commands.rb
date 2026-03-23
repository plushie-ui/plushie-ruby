# frozen_string_literal: true

require "test_helper"

class TestRuntimeCommands < Minitest::Test
  C = Plushie::Command

  # Minimal mock bridge that records messages sent via send_encoded.
  class MockBridge
    attr_reader :messages

    def initialize
      @messages = []
    end

    def send_encoded(data)
      @messages << data
    end
  end

  # Harness that includes the Commands module with enough state for it
  # to operate. Exposes execute_commands as public so tests can call it.
  class CommandRunner
    include Plushie::Runtime::Commands

    attr_reader :bridge, :event_queue, :async_tasks, :pending_effects,
      :pending_timers
    attr_accessor :running

    def initialize(bridge:)
      @bridge = bridge
      @format = :json
      @event_queue = Thread::Queue.new
      @async_tasks = {}
      @pending_effects = {}
      @pending_timers = {}
      @running = true
      @logger = Logger.new(IO::NULL)
    end

    # Make the private methods public for testing.
    public :execute_commands, :execute_async, :cancel_task,
      :execute_done, :execute_send_after, :execute_effect,
      :send_widget_op, :send_window_op
  end

  def setup
    @bridge = MockBridge.new
    @runner = CommandRunner.new(bridge: @bridge)
  end

  # -- :none does nothing --------------------------------------------------

  def test_none_does_nothing
    @runner.execute_commands(C.none)
    assert_empty @bridge.messages
    assert @runner.event_queue.empty?
  end

  # -- :batch processes sub-commands ---------------------------------------

  def test_batch_processes_sub_commands
    cmd = C.batch([C.focus("a"), C.focus("b")])
    @runner.execute_commands(cmd)
    assert_equal 2, @bridge.messages.length
  end

  # -- :async spawns a thread and delivers result via queue ----------------

  def test_async_delivers_result_to_queue
    cmd = C.async(-> { 42 }, :fetch)
    @runner.execute_commands(cmd)

    # The async thread pushes [:async_result, tag, nonce, result]
    msg = @runner.event_queue.pop
    assert_equal :async_result, msg[0]
    assert_equal :fetch, msg[1]
    assert_equal 42, msg[3]
  end

  # -- :cancel kills a running task ----------------------------------------

  def test_cancel_kills_task
    # Start a long-running async task
    cmd = C.async(-> { sleep(60) }, :slow)
    @runner.execute_commands(cmd)

    assert @runner.async_tasks.key?(:slow)

    @runner.execute_commands(C.cancel(:slow))
    refute @runner.async_tasks.key?(:slow)
  end

  # -- :done dispatches immediately ----------------------------------------

  def test_done_dispatches_immediately
    mapper = ->(v) { [:got, v] }
    cmd = C.done("payload", mapper)
    @runner.execute_commands(cmd)

    msg = @runner.event_queue.pop
    assert_equal :send_after_event, msg[0]
    assert_equal [:got, "payload"], msg[1]
  end

  # -- :send_after fires after delay --------------------------------------

  def test_send_after_fires_after_delay
    cmd = C.send_after(50, :clear)
    @runner.execute_commands(cmd)

    msg = @runner.event_queue.pop
    assert_equal :send_after_event, msg[0]
    assert_equal :clear, msg[1]
  end

  # -- :exit sets running to false -----------------------------------------

  def test_exit_sets_running_to_false
    assert @runner.running
    @runner.execute_commands(C.exit)
    refute @runner.running
  end

  # -- :focus sends widget_op via bridge -----------------------------------

  def test_focus_sends_widget_op
    @runner.execute_commands(C.focus("input_field"))
    assert_equal 1, @bridge.messages.length
  end

  # -- :effect sends effect and starts timeout timer -----------------------

  def test_effect_sends_effect_and_starts_timeout
    cmd = Plushie::Effects.clipboard_read
    @runner.execute_commands(cmd)

    assert_equal 1, @bridge.messages.length
    assert_equal 1, @runner.pending_effects.length

    # Clean up the timeout thread
    @runner.pending_effects.each_value(&:kill)
  end

  # -- :window_op sends window_op via bridge -------------------------------

  def test_window_op_sends_to_bridge
    cmd = C.resize_window("main", 800, 600)
    @runner.execute_commands(cmd)
    assert_equal 1, @bridge.messages.length
  end

  # -- nil command is a no-op ----------------------------------------------

  def test_nil_command_is_noop
    @runner.execute_commands(nil)
    assert_empty @bridge.messages
  end
end
