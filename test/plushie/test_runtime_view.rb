# frozen_string_literal: true

require "test_helper"
require "json"
require "stringio"

class TestRuntimeView < Minitest::Test
  include Plushie::UI

  class ViewApp
    attr_accessor :view_tree, :window_config_result
    attr_reader :renderer_exits

    def initialize(view_tree)
      @view_tree = view_tree
      @renderer_exits = []
      @window_config_result = {}
    end

    def init(_opts) = nil
    def update(model, _event) = model
    def view(_model) = @view_tree
    def subscribe(_model) = []
    def settings = {}
    def window_config(_model) = @window_config_result

    def handle_renderer_exit(model, exit)
      @renderer_exits << exit
      model
    end
  end

  class MemoApp
    include Plushie::UI

    attr_reader :call_count

    def initialize
      @call_count = 0
    end

    def init(_opts) = nil
    def update(model, _event) = model
    def subscribe(_model) = []
    def settings = {}
    def window_config(_model) = {}

    def view(_model)
      window("main") do
        memo(:stable) do
          @call_count += 1
          text("memo_text", "memo #{@call_count}")
        end
      end
    end
  end

  class MockBridge
    attr_reader :attempts, :messages

    def initialize(fail_on_type: nil, fail_on_window_op: nil, fail_on_window_id: nil)
      @fail_on_type = fail_on_type
      @fail_on_window_op = fail_on_window_op
      @fail_on_window_id = fail_on_window_id
      @attempts = []
      @messages = []
    end

    def send_encoded(data)
      message = JSON.parse(data)
      type = message["type"]
      @attempts << message
      raise IOError, "send failed for #{type}" if type == @fail_on_type
      if type == "window_op" && message["op"] == @fail_on_window_op
        raise IOError, "send failed for #{type}: #{message["op"]}"
      end
      if type == "window_op" && message["window_id"] == @fail_on_window_id
        raise IOError, "send failed for #{type}: #{message["window_id"]}"
      end

      @messages << data
    end
  end

  class FakeTimer
    attr_reader :killed

    def kill
      @killed = true
    end
  end

  class LeakyReason
    def inspect = "/secret/config.yml token=abc"
  end

  class LeakyClassReason
    def class
      Struct.new(:name).new("/secret/config.yml token=abc")
    end
  end

  def runtime_for(view_tree)
    runtime = Plushie::Runtime.new(app: ViewApp.new(view_tree), transport: :spawn, format: :json)
    runtime.instance_variable_set(:@logger, Logger.new(IO::NULL))
    runtime
  end

  def test_normalize_view_tree_requires_window_nodes
    runtime = runtime_for(column("content") { text("msg", "hi") })

    error = assert_raises(ArgumentError) do
      runtime.send(:normalize_view_tree, runtime.instance_variable_get(:@app).view(nil))
    end

    assert_equal "view must return a window node or an array of window nodes", error.message
  end

  def test_normalize_view_tree_wraps_single_window_in_root
    runtime = runtime_for(window("main", title: "Main") { text("msg", "hi") })

    tree = runtime.send(:normalize_view_tree, runtime.instance_variable_get(:@app).view(nil))

    assert_equal "root", tree.id
    assert_equal "root", tree.type
    assert_equal ["main"], tree.children.map(&:id)
  end

  def test_normalize_view_tree_keeps_multiple_windows
    runtime = runtime_for([
      window("main", title: "Main") { text("msg", "hi") },
      window("inspector", title: "Inspector") { text("meta", "details") }
    ])

    tree = runtime.send(:normalize_view_tree, runtime.instance_variable_get(:@app).view(nil))

    assert_equal "root", tree.id
    assert_equal %w[main inspector], tree.children.map(&:id)
    assert tree.children.all? { |node| node.type == "window" }
  end

  def test_renderer_exit_preserves_previous_tree
    runtime = runtime_for(window("main") { text("msg", "hi") })
    app = runtime.instance_variable_get(:@app)
    tree = runtime.send(:normalize_view_tree, app.view(nil))
    runtime.instance_variable_set(:@previous_tree, tree)
    runtime.instance_variable_set(:@model, :model)
    runtime.instance_variable_set(:@running, true)

    runtime.send(:handle_renderer_exit, {type: :connection_closed})

    assert_equal tree, runtime.instance_variable_get(:@previous_tree)
    assert_equal :connection_lost, app.renderer_exits.first.type
    refute runtime.instance_variable_get(:@running)
  end

  def test_renderer_exit_callback_receives_sanitized_crash
    runtime = runtime_for(window("main") { text("msg", "hi") })
    app = runtime.instance_variable_get(:@app)
    runtime.instance_variable_set(:@model, :model)
    runtime.instance_variable_set(:@running, true)
    error = RuntimeError.new("/secret/config.yml token=abc")

    runtime.send(:handle_renderer_exit, error)

    exit = app.renderer_exits.first
    assert_equal :crash, exit.type
    assert_equal "renderer exited unexpectedly", exit.message
    assert_equal({exception_class: "RuntimeError"}, exit.details)
    refute_includes exit.message, "/secret"
    refute_includes exit.details.inspect, "/secret"
  end

  def test_renderer_exit_sanitizes_connection_error
    runtime = runtime_for(window("main") { text("msg", "hi") })
    error = IOError.new("/secret/renderer.sock token=abc")

    exit = runtime.send(:build_renderer_exit, {type: :connection_error, error: error})

    assert_equal :crash, exit.type
    assert_equal "renderer connection error", exit.message
    assert_equal({error_class: "IOError"}, exit.details)
    refute_same error, exit.details
    refute_includes exit.message, "/secret"
    refute_includes exit.details.inspect, "/secret"
  end

  def test_renderer_exit_sanitizes_exception_reason
    runtime = runtime_for(window("main") { text("msg", "hi") })
    error = RuntimeError.new("/secret/config.yml token=abc")

    exit = runtime.send(:build_renderer_exit, error)

    assert_equal :crash, exit.type
    assert_equal "renderer exited unexpectedly", exit.message
    assert_equal({exception_class: "RuntimeError"}, exit.details)
    refute_same error, exit.details
    refute_includes exit.message, "/secret"
    refute_includes exit.details.inspect, "/secret"
  end

  def test_renderer_exit_sanitizes_arbitrary_reason
    runtime = runtime_for(window("main") { text("msg", "hi") })
    reason = LeakyReason.new

    exit = runtime.send(:build_renderer_exit, reason)

    assert_equal :crash, exit.type
    assert_equal "renderer exited unexpectedly", exit.message
    assert_equal({reason_type: "TestRuntimeView::LeakyReason"}, exit.details)
    refute_same reason, exit.details
    refute_includes exit.message, "/secret"
    refute_includes exit.details.inspect, "/secret"
  end

  def test_renderer_exit_sanitizes_overridden_class
    runtime = runtime_for(window("main") { text("msg", "hi") })
    reason = LeakyClassReason.new

    exit = runtime.send(:build_renderer_exit, reason)

    assert_equal({reason_type: "TestRuntimeView::LeakyClassReason"}, exit.details)
    refute_includes exit.details.inspect, "/secret"
  end

  def test_renderer_restart_clears_memo_cache_before_snapshot
    app = MemoApp.new
    runtime = Plushie::Runtime.new(app: app, transport: :spawn, format: :json)
    runtime.instance_variable_set(:@logger, Logger.new(IO::NULL))
    runtime.instance_variable_set(:@bridge, MockBridge.new)

    runtime.send(:render_and_snapshot)
    assert_equal 1, app.call_count
    refute_empty runtime.instance_variable_get(:@memo_cache)

    runtime.send(:handle_renderer_restarted)

    assert_equal 2, app.call_count
  end

  def test_render_and_snapshot_tracks_opened_windows_when_snapshot_send_fails
    app = ViewApp.new(window("main") { text("msg", "hi") })
    app.window_config_result = {title: "Base"}
    runtime = Plushie::Runtime.new(app: app, transport: :spawn, format: :json)
    runtime.instance_variable_set(:@logger, Logger.new(IO::NULL))
    bridge = MockBridge.new(fail_on_type: "snapshot")
    runtime.instance_variable_set(:@bridge, bridge)

    runtime.send(:render_and_snapshot)

    assert_equal %w[window_op snapshot], bridge.attempts.map { |message| message["type"] }
    assert_equal ["open"], bridge.attempts.select { |message| message["type"] == "window_op" }.map { |message| message["op"] }
    assert_equal "Base", bridge.attempts[0]["payload"]["title"]
    assert_nil runtime.instance_variable_get(:@previous_tree)
    assert_equal Set["main"], runtime.instance_variable_get(:@tracked_windows)
    assert runtime.view_error?
  end

  def test_render_and_snapshot_resends_old_snapshot_if_window_op_fails
    app = ViewApp.new(window("child") { text("child_msg", "child") })
    runtime = Plushie::Runtime.new(app: app, transport: :spawn, format: :json)
    runtime.instance_variable_set(:@logger, Logger.new(IO::NULL))
    old_tree = runtime.send(:normalize_view_tree, window("main") { text("msg", "old") })
    runtime.instance_variable_set(:@previous_tree, old_tree)
    runtime.instance_variable_set(:@tracked_windows, Set["main"])
    bridge = MockBridge.new(fail_on_window_op: "open")
    runtime.instance_variable_set(:@bridge, bridge)

    runtime.send(:render_and_snapshot)

    assert_equal %w[window_op snapshot], bridge.attempts.map { |message| message["type"] }
    assert_equal Set["main"], runtime.instance_variable_get(:@tracked_windows)
    assert_equal old_tree, runtime.instance_variable_get(:@previous_tree)
    assert runtime.view_error?
  end

  def test_render_and_snapshot_does_not_resend_old_snapshot_after_window_ops
    app = ViewApp.new([
      window("main") { text("msg", "new") },
      window("child") { text("child_msg", "child") }
    ])
    runtime = Plushie::Runtime.new(app: app, transport: :spawn, format: :json)
    runtime.instance_variable_set(:@logger, Logger.new(IO::NULL))
    old_tree = runtime.send(:normalize_view_tree, window("main") { text("msg", "old") })
    runtime.instance_variable_set(:@previous_tree, old_tree)
    runtime.instance_variable_set(:@tracked_windows, Set["main"])
    bridge = MockBridge.new(fail_on_type: "snapshot")
    runtime.instance_variable_set(:@bridge, bridge)

    runtime.send(:render_and_snapshot)

    assert_equal %w[window_op snapshot], bridge.attempts.map { |message| message["type"] }
    assert_equal Set["main", "child"], runtime.instance_variable_get(:@tracked_windows)
    assert_equal old_tree, runtime.instance_variable_get(:@previous_tree)
    assert runtime.view_error?
  end

  def test_render_and_snapshot_can_defer_window_ops_for_interact_step
    app = ViewApp.new([
      window("main") { text("msg", "new") },
      window("child") { text("child_msg", "child") }
    ])
    runtime = Plushie::Runtime.new(app: app, transport: :spawn, format: :json)
    runtime.instance_variable_set(:@logger, Logger.new(IO::NULL))
    runtime.instance_variable_set(:@tracked_windows, Set["main"])
    bridge = MockBridge.new
    runtime.instance_variable_set(:@bridge, bridge)

    runtime.send(:render_and_snapshot, window_ops_order: :defer_window_ops)

    assert_equal ["snapshot"], bridge.attempts.map { |message| message["type"] }
    assert_equal Set["main"], runtime.instance_variable_get(:@tracked_windows)
    refute runtime.view_error?

    runtime.send(:handle_interact_response, {events: []})

    assert_equal %w[snapshot window_op], bridge.attempts.map { |message| message["type"] }
    assert_equal ["child"], bridge.attempts.select { |message| message["type"] == "window_op" }.map { |message| message["window_id"] }
    assert_equal Set["main", "child"], runtime.instance_variable_get(:@tracked_windows)
  end

  def test_deferred_interact_window_op_failure_keeps_snapshot_commit
    app = ViewApp.new(window("child") { text("child_msg", "child") })
    runtime = Plushie::Runtime.new(app: app, transport: :spawn, format: :json)
    runtime.instance_variable_set(:@logger, Logger.new(IO::NULL))
    old_tree = runtime.send(:normalize_view_tree, window("main") { text("msg", "old") })
    runtime.instance_variable_set(:@previous_tree, old_tree)
    runtime.instance_variable_set(:@tracked_windows, Set["main"])
    bridge = MockBridge.new(fail_on_window_op: "open")
    runtime.instance_variable_set(:@bridge, bridge)

    runtime.send(:render_and_snapshot, window_ops_order: :defer_window_ops)

    assert_equal ["snapshot"], bridge.attempts.map { |message| message["type"] }
    refute_equal old_tree, runtime.instance_variable_get(:@previous_tree)
    refute runtime.view_error?

    runtime.send(:handle_interact_response, {events: []})

    assert_equal %w[snapshot window_op], bridge.attempts.map { |message| message["type"] }
    assert_equal Set["main"], runtime.instance_variable_get(:@tracked_windows)
    refute_equal old_tree, runtime.instance_variable_get(:@previous_tree)
    assert runtime.view_error?
  end

  def test_handle_interact_timeout_pushes_action_and_selector_error
    runtime = runtime_for(window("main") { text("msg", "hi") })
    result_queue = Thread::Queue.new
    timer = FakeTimer.new
    runtime.instance_variable_set(:@pending_interact, {
      id: "interact-1",
      action: "click",
      selector: {by: "id", value: "submit"},
      result_queue: result_queue,
      timeout_timer: timer
    })

    runtime.send(:handle_interact_timeout, "interact-1")

    assert_equal({error: 'interact timed out: action=click selector={by: "id", value: "submit"}'}, result_queue.pop)
    assert_nil runtime.instance_variable_get(:@pending_interact)
    assert timer.killed
  end

  def test_handle_interact_timeout_omits_nil_selector_in_error
    runtime = runtime_for(window("main") { text("msg", "hi") })
    result_queue = Thread::Queue.new
    runtime.instance_variable_set(:@pending_interact, {
      id: "interact-1",
      action: "press_key",
      selector: nil,
      result_queue: result_queue,
      timeout_timer: FakeTimer.new
    })

    runtime.send(:handle_interact_timeout, "interact-1")

    assert_equal({error: "interact timed out: action=press_key"}, result_queue.pop)
  end

  def test_handle_interact_timeout_warning_names_action_and_selector
    runtime = runtime_for(window("main") { text("msg", "hi") })
    log_io = StringIO.new
    logger = Logger.new(log_io)
    logger.formatter = ->(_severity, _time, _progname, message) { "#{message}\n" }
    runtime.instance_variable_set(:@logger, logger)
    runtime.instance_variable_set(:@pending_interact, {
      id: "interact-2",
      action: "type_text",
      selector: {by: "id", value: "name"},
      result_queue: Thread::Queue.new,
      timeout_timer: FakeTimer.new
    })

    runtime.send(:handle_interact_timeout, "interact-2")

    assert_equal(
      "plushie: interact timed out: action=type_text selector={by: \"id\", value: \"name\"} (id interact-2)\n",
      log_io.string
    )
  end

  def test_interact_enqueue_timeout_uses_labeled_message
    runtime = runtime_for(window("main") { text("msg", "hi") })
    queue = Plushie::BoundedQueue.new(1)
    queue.close
    runtime.instance_variable_set(:@event_queue, queue)

    error = assert_raises(Plushie::Error) do
      runtime.interact("click", {by: "id", value: "submit"}, timeout: 0)
    end

    assert_equal 'interact timed out: action=click selector={by: "id", value: "submit"}', error.message
  end

  def test_interact_wait_timeout_uses_labeled_message
    runtime = runtime_for(window("main") { text("msg", "hi") })

    error = assert_raises(Plushie::Error) do
      runtime.interact("press_key", nil, timeout: 0)
    end

    assert_equal "interact timed out: action=press_key", error.message
  end

  def test_await_async_enqueue_timeout_uses_labeled_message
    runtime = runtime_for(window("main") { text("msg", "hi") })
    queue = Plushie::BoundedQueue.new(1)
    queue.close
    runtime.instance_variable_set(:@event_queue, queue)

    error = assert_raises(Plushie::Error) do
      runtime.await_async(:data_loaded, timeout: 0)
    end

    assert_equal "await_async timed out: tag=data_loaded", error.message
  end

  def test_await_async_wait_timeout_uses_labeled_message
    runtime = runtime_for(window("main") { text("msg", "hi") })

    error = assert_raises(Plushie::Error) do
      runtime.await_async(:data_loaded, timeout: 0)
    end

    assert_equal "await_async timed out: tag=data_loaded", error.message
  end

  def test_render_and_patch_tracks_opened_windows_when_patch_send_fails
    app = ViewApp.new(window("main") { text("msg", "old") })
    runtime = Plushie::Runtime.new(app: app, transport: :spawn, format: :json)
    runtime.instance_variable_set(:@logger, Logger.new(IO::NULL))
    old_tree = runtime.send(:normalize_view_tree, app.view(nil))
    runtime.instance_variable_set(:@previous_tree, old_tree)
    runtime.instance_variable_set(:@tracked_windows, Set["main"])
    bridge = MockBridge.new(fail_on_type: "patch")
    runtime.instance_variable_set(:@bridge, bridge)

    app.view_tree = [
      window("main") { text("msg", "new") },
      window("child") { text("child_msg", "child") }
    ]

    runtime.send(:render_and_patch)

    assert_equal %w[window_op patch], bridge.attempts.map { |message| message["type"] }
    assert_equal ["child"], bridge.attempts.select { |message| message["type"] == "window_op" }.map { |message| message["window_id"] }
    assert_equal old_tree, runtime.instance_variable_get(:@previous_tree)
    assert_equal Set["main", "child"], runtime.instance_variable_get(:@tracked_windows)
    assert runtime.view_error?
  end

  def test_render_and_patch_keeps_tree_commit_when_window_op_send_fails
    app = ViewApp.new(window("main") { text("msg", "old") })
    runtime = Plushie::Runtime.new(app: app, transport: :spawn, format: :json)
    runtime.instance_variable_set(:@logger, Logger.new(IO::NULL))
    old_tree = runtime.send(:normalize_view_tree, app.view(nil))
    runtime.instance_variable_set(:@previous_tree, old_tree)
    runtime.instance_variable_set(:@tracked_windows, Set["main"])
    bridge = MockBridge.new(fail_on_window_op: "open")
    runtime.instance_variable_set(:@bridge, bridge)

    app.view_tree = [
      window("main") { text("msg", "new") },
      window("child") { text("child_msg", "child") }
    ]
    new_tree = runtime.send(:normalize_view_tree, app.view(nil))

    runtime.send(:render_and_patch)

    assert_equal ["window_op"], bridge.attempts.map { |message| message["type"] }
    assert_equal ["open"], bridge.attempts.select { |message| message["type"] == "window_op" }.map { |message| message["op"] }
    refute_equal new_tree, runtime.instance_variable_get(:@previous_tree)
    assert_equal old_tree, runtime.instance_variable_get(:@previous_tree)
    assert_equal Set["main"], runtime.instance_variable_get(:@tracked_windows)
    assert runtime.view_error?
  end

  def test_render_and_patch_tracks_successful_window_ops_before_later_failure
    app = ViewApp.new(window("main") { text("msg", "old") })
    runtime = Plushie::Runtime.new(app: app, transport: :spawn, format: :json)
    runtime.instance_variable_set(:@logger, Logger.new(IO::NULL))
    old_tree = runtime.send(:normalize_view_tree, app.view(nil))
    runtime.instance_variable_set(:@previous_tree, old_tree)
    runtime.instance_variable_set(:@tracked_windows, Set["main"])
    bridge = MockBridge.new(fail_on_window_id: "second")
    runtime.instance_variable_set(:@bridge, bridge)

    app.view_tree = [
      window("main") { text("msg", "new") },
      window("first") { text("first_msg", "first") },
      window("second") { text("second_msg", "second") }
    ]
    runtime.send(:render_and_patch)

    window_attempts = bridge.attempts.select { |message| message["type"] == "window_op" }
    assert_equal %w[first second], window_attempts.map { |message| message["window_id"] }
    assert_equal old_tree, runtime.instance_variable_get(:@previous_tree)
    assert_equal Set["main", "first"], runtime.instance_variable_get(:@tracked_windows)
    assert runtime.view_error?
  end
end
