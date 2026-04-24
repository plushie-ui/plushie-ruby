# frozen_string_literal: true

require "test_helper"
require "timeout"

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
      @effect_tags = {}
      @effect_ids = {}
      @effect_kinds = {}
      @pending_timers = {}
      @running = true
      @logger = Logger.new(IO::NULL)
      @dispatch_depth = 0
      @diagnostics = []
      @diagnostics_mutex = Mutex.new
      @pending_runtime_events = []
      @runtime_thread = nil
    end

    attr_accessor :dispatch_depth

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
    cmd = C.task(-> { 42 }, :fetch)
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
    cmd = C.task(-> { sleep(60) }, :slow)
    @runner.execute_commands(cmd)

    assert @runner.async_tasks.key?(:slow)

    @runner.execute_commands(C.cancel(:slow))
    # Entry is marked as cancelled (not deleted). The async result
    # handler owns cleanup, preventing a race where Thread.kill
    # triggers the rescue block that pushes an async_result after
    # deletion.
    assert @runner.async_tasks.key?(:slow)
    assert_equal :cancelled, @runner.async_tasks[:slow][:nonce]
  end

  # -- :done dispatches immediately ----------------------------------------

  def test_done_dispatches_immediately
    mapper = ->(v) { [:got, v] }
    cmd = C.dispatch("payload", mapper)
    @runner.execute_commands(cmd)

    msg = @runner.event_queue.pop
    assert_equal :dispatched_event, msg[0]
    assert_equal 1, msg[1]
    assert_equal [:got, "payload"], msg[2]
  end

  def test_done_from_runtime_thread_does_not_block_when_mailbox_is_full
    full_queue = Plushie::BoundedQueue.new(1)
    full_queue.push(:already_waiting)
    @runner.instance_variable_set(:@event_queue, full_queue)
    @runner.instance_variable_set(:@runtime_thread, Thread.current)

    mapper = ->(v) { [:got, v] }
    cmd = C.dispatch("payload", mapper)

    Timeout.timeout(0.1) { @runner.execute_commands(cmd) }

    pending = @runner.instance_variable_get(:@pending_runtime_events)
    assert_equal :already_waiting, full_queue.pop
    assert_equal [
      {
        message: [:dispatched_event, 1, [:got, "payload"]],
        remaining: 1
      }
    ], pending
  end

  # -- :done guards against runaway dispatch chains ------------------------

  def test_done_drops_and_diagnoses_past_depth_cap
    mapper = ->(v) { [:got, v] }
    cmd = C.dispatch("payload", mapper)
    @runner.dispatch_depth = Plushie::Runtime::Commands::DISPATCH_DEPTH_LIMIT
    @runner.execute_commands(cmd)

    # The guard dropped the event; nothing queued.
    assert @runner.event_queue.empty?

    diags = @runner.instance_variable_get(:@diagnostics)
    refute_empty diags
    message = diags.first
    assert_kind_of Plushie::Event::DiagnosticMessage, message
    assert_kind_of Plushie::Event::Diagnostic::DispatchLoopExceeded,
      message.diagnostic
    assert_equal Plushie::Runtime::Commands::DISPATCH_DEPTH_LIMIT + 1,
      message.diagnostic.depth
    assert_equal Plushie::Runtime::Commands::DISPATCH_DEPTH_LIMIT,
      message.diagnostic.limit
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
    cmd = Plushie::Effect.clipboard_read(:paste)
    @runner.execute_commands(cmd)

    assert_equal 1, @bridge.messages.length
    assert_equal 1, @runner.pending_effects.length

    # Clean up the timeout thread
    @runner.pending_effects.each_value(&:kill)
  end

  def test_effect_timeout_stops_timeout_thread
    timer = Thread.new { sleep 60 }
    runtime = Plushie::Runtime.allocate
    dispatched = []
    runtime.define_singleton_method(:dispatch_event) { |event| dispatched << event }
    runtime.instance_variable_set(:@pending_effects, {"effect-1" => timer})
    runtime.instance_variable_set(:@effect_ids, {"effect-1" => :paste})
    runtime.instance_variable_set(:@effect_kinds, {"effect-1" => "clipboard_read"})
    runtime.instance_variable_set(:@effect_tags, {paste: "effect-1"})

    runtime.send(:handle_effect_timeout, "effect-1")

    timer.join(0.1)
    refute timer.alive?
    assert_equal 1, dispatched.length
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
