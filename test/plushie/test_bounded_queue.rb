# frozen_string_literal: true

require "test_helper"
require "plushie/test/session_pool"

class TestBoundedQueue < Minitest::Test
  class MinimalApp
    def init(_opts) = nil
    def update(model, _event) = model
    def view(_model) = nil
  end

  def test_push_blocks_until_space_is_available
    queue = Plushie::BoundedQueue.new(1)
    queue.push(:first)

    started = Thread::Queue.new
    finished = Thread::Queue.new
    worker = Thread.new do
      started.push(:ready)
      Plushie::BoundedQueue.push(queue, :second)
      finished.push(:done)
    end

    started.pop
    assert_nil finished.pop(timeout: 0.05)

    assert_equal :first, queue.pop
    assert_equal :done, finished.pop(timeout: 1)
    assert_equal :second, queue.pop
  ensure
    worker&.kill
    worker&.join
  end

  def test_runtime_event_queue_is_bounded
    runtime = Plushie::Runtime.new(app: MinimalApp.new)
    queue = runtime.instance_variable_get(:@event_queue)

    assert_kind_of SizedQueue, queue
    assert_equal Plushie::BoundedQueue::EVENT_CAPACITY, queue.max
  end

  def test_pending_runtime_dispatch_does_not_wait_behind_later_external_events
    runtime = Plushie::Runtime.new(app: MinimalApp.new)
    queue = Plushie::BoundedQueue.new(1)
    queue.push(:external_before_dispatch)
    runtime.instance_variable_set(:@event_queue, queue)
    runtime.instance_variable_set(:@runtime_thread, Thread.current)

    runtime.send(
      :execute_commands,
      Plushie::Command.dispatch(:payload, ->(value) { [:got, value] })
    )

    assert_equal :external_before_dispatch, runtime.send(:next_event_message)
    queue.push(:external_after_dispatch)

    assert_equal [:dispatched_event, 1, [:got, :payload]],
      runtime.send(:next_event_message)
    assert_equal :external_after_dispatch, runtime.send(:next_event_message)
  end

  def test_ready_runtime_dispatch_runs_before_idle_coalesce_flush
    runtime = Plushie::Runtime.allocate
    key = ["main", "pointer", :move]
    order = []

    runtime.instance_variable_set(:@running, true)
    runtime.instance_variable_set(:@event_queue, Plushie::BoundedQueue.new(1))
    runtime.instance_variable_set(:@pending_runtime_events, [
      {message: [:dispatched_event, 1, :runtime_event], remaining: 0}
    ])
    runtime.instance_variable_set(:@pending_coalesce, {key => :coalesced_event})
    runtime.instance_variable_set(:@coalesce_order, [key])
    runtime.instance_variable_set(:@dispatch_depth, 0)
    runtime.instance_variable_set(:@logger, Logger.new(IO::NULL))

    runtime.define_singleton_method(:flush_coalescables) do
      order << :flush
      @pending_coalesce.clear
    end
    runtime.define_singleton_method(:dispatch_event) do |event|
      order << [:dispatch, event]
      @running = false
    end

    runtime.send(:event_loop)

    assert_equal [[:dispatch, :runtime_event]], order
  end

  def test_shutdown_keeps_runtime_thread_marker_for_dispatch
    runtime = Plushie::Runtime.allocate
    queue = Plushie::BoundedQueue.new(1)
    queue.push(:queued)

    runtime.instance_variable_set(:@dev, false)
    runtime.instance_variable_set(:@event_queue, queue)
    runtime.instance_variable_set(:@pending_runtime_events, [])
    runtime.instance_variable_set(:@dispatch_depth, 0)
    runtime.instance_variable_set(:@diagnostics, [])
    runtime.instance_variable_set(:@diagnostics_mutex, Mutex.new)
    runtime.instance_variable_set(:@logger, Logger.new(IO::NULL))

    runtime.define_singleton_method(:start_bridge) {}
    runtime.define_singleton_method(:initialize_app) {}
    runtime.define_singleton_method(:event_loop) { raise "stop" }
    runtime.define_singleton_method(:shutdown) do
      send(
        :execute_commands,
        Plushie::Command.dispatch(:payload, ->(value) { [:got, value] })
      )
    end

    error = assert_raises(RuntimeError) do
      Timeout.timeout(0.1) { runtime.run }
    end
    assert_equal "stop", error.message

    assert_nil runtime.instance_variable_get(:@runtime_thread)
    assert_equal [
      {
        message: [:dispatched_event, 1, [:got, :payload]],
        remaining: 1
      }
    ], runtime.instance_variable_get(:@pending_runtime_events)
  end

  def test_session_pool_uses_bounded_session_queues
    pool = Plushie::Test::SessionPool.new(max_sessions: 1)
    session_id = pool.register
    sessions = pool.instance_variable_get(:@sessions)
    queue = sessions.fetch(session_id)

    assert_kind_of SizedQueue, queue
    assert_equal Plushie::BoundedQueue::SESSION_CAPACITY, queue.max
  end

  def test_session_pool_stashes_without_blocking_when_session_queue_is_full
    pool = Plushie::Test::SessionPool.new(max_sessions: 1)
    session_id = pool.register
    sessions = pool.instance_variable_get(:@sessions)
    queue = Plushie::BoundedQueue.new(1)
    sessions[session_id] = queue

    other = {type: :other, session: session_id}
    target = {type: :target, session: session_id}
    filler = {type: :filler, session: session_id}
    queue.push(other)

    target_read = Thread::Queue.new
    release_target = Thread::Queue.new
    original_read = pool.method(:read_message)
    pool.define_singleton_method(:read_message) do |id, timeout: 10|
      msg = original_read.call(id, timeout: timeout)
      if msg[:type] == :target
        target_read.push(:ok)
        release_target.pop
      end
      msg
    end

    waiter = Thread.new do
      pool.send(:wait_for_response, session_id, :target, timeout: 1)
    end

    Timeout.timeout(1) { sleep 0.001 until queue.empty? }
    queue.push(target)
    assert_equal :ok, target_read.pop(timeout: 1)
    queue.push(filler)
    release_target.push(:ok)

    assert waiter.join(0.5), "wait_for_response blocked while restoring stash"
    assert_equal target, waiter.value
    assert_equal other, pool.read_message(session_id, timeout: 0.1)
    assert_equal filler, pool.read_message(session_id, timeout: 0.1)
  ensure
    release_target&.push(:ok)
    waiter&.kill
    waiter&.join
  end

  def test_runtime_stop_kills_thread_when_shutdown_cannot_be_enqueued
    runtime = Plushie::Runtime.allocate
    queue = Plushie::BoundedQueue.new(1)
    queue.close
    thread = Thread.new { sleep }
    runtime.instance_variable_set(:@event_queue, queue)
    runtime.instance_variable_set(:@loop_thread, thread)
    runtime.instance_variable_set(:@running, true)

    runtime.stop

    refute thread.alive?
  ensure
    thread&.kill
    thread&.join
  end
end
