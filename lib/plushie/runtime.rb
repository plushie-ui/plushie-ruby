# frozen_string_literal: true

require "logger"
require "securerandom"
require_relative "runtime/commands"
require_relative "runtime/subscriptions"

module Plushie
  # Core event loop for Plushie applications.
  #
  # Owns the Elm-style update cycle: event -> model -> view -> diff -> patch.
  # Processes events sequentially from a thread-safe queue. All state is
  # owned by the runtime thread -- no shared mutable state.
  #
  # @see ~/projects/toddy-elixir/lib/plushie/runtime.ex
  class Runtime
    include Commands
    include Subscriptions

    # @param app [Object] app instance (includes Plushie::App)
    # @param transport [:spawn, :stdio, Array(:iostream, adapter)] transport mode
    # @param format [:msgpack, :json] wire format
    # @param daemon [Boolean] keep running after last window closes
    # @param binary [String, nil] renderer binary path
    # @param log_level [Symbol] renderer log level
    # @param token [String, nil] authentication token for the renderer
    # @param dev [Boolean] enable live code reloading via DevServer
    # @param dev_dirs [Array<String>, nil] directories to watch (default: ["lib/"])
    def initialize(app:, transport: :spawn, format: :msgpack, daemon: false,
      binary: nil, log_level: :error, token: nil, dev: false, dev_dirs: nil)
      @app = app
      @transport = transport
      @format = format
      @daemon = daemon
      @binary = binary
      @log_level = log_level
      @token = token
      @dev = dev
      @dev_dirs = dev_dirs

      @event_queue = Thread::Queue.new
      @model = nil
      @previous_tree = nil
      @bridge = nil
      @dev_server = nil
      @running = false

      @async_tasks = {}        # tag -> {thread:, nonce:}
      @pending_effects = {}    # effect_id -> timer_thread
      @pending_timers = {}     # event_key -> timer_thread
      @subscriptions = {}      # sub_key -> {sub_type:, ...}
      @subscription_keys = []  # sorted keys for short-circuit
      @canvas_widgets = {}     # "#{window_id}\0#{scoped_id}" -> CanvasWidget::RegistryEntry
      @consecutive_errors = 0
      @consecutive_view_errors = 0
      @diagnostics = []        # accumulated prop validation diagnostics
      @diagnostics_mutex = Mutex.new
      @pending_stub_acks = {}  # kind -> Queue (for sync ack round-trip)
      @pending_await_async = {} # tag -> Queue (for sync await)
      @pending_interact = nil   # {id:, result_queue:} for current interact

      @logger = Logger.new($stderr, level: :warn, progname: "plushie")
    end

    # Run the event loop in the calling thread (blocking).
    def run
      start_bridge
      start_dev_server if @dev
      initialize_app
      event_loop
    ensure
      shutdown
    end

    # Start the event loop in a background thread.
    # @return [Runtime] self
    def start
      thread = Thread.new { run }
      thread.name = "plushie-runtime"
      @loop_thread = thread
      self
    end

    # Stop a background runtime.
    def stop
      @running = false
      @event_queue.push(:shutdown)
      @loop_thread&.join(5)
    end

    # Register an effect stub with the renderer.
    # Blocks until the renderer confirms the stub is stored.
    #
    # @param kind [String] effect kind (e.g. "clipboard_read")
    # @param response [Object] the canned response to return
    # @param timeout [Numeric] max wait in seconds
    def register_effect_stub(kind, response, timeout: 5)
      ack_queue = Thread::Queue.new
      @event_queue.push([:register_effect_stub, kind, response, ack_queue])
      result = ack_queue.pop(timeout: Float(timeout))
      raise Plushie::Error, "effect stub registration timed out for #{kind}" if result.nil?
      :ok
    end

    # Remove a previously registered effect stub.
    # Blocks until the renderer confirms the stub is removed.
    #
    # @param kind [String] effect kind
    # @param timeout [Numeric] max wait in seconds
    def unregister_effect_stub(kind, timeout: 5)
      ack_queue = Thread::Queue.new
      @event_queue.push([:unregister_effect_stub, kind, ack_queue])
      result = ack_queue.pop(timeout: Float(timeout))
      raise Plushie::Error, "effect stub unregistration timed out for #{kind}" if result.nil?
      :ok
    end

    # Returns and clears accumulated prop validation diagnostics.
    #
    # The renderer emits diagnostic events when validate_props is enabled.
    # These are intercepted by the runtime (never delivered to update)
    # and accumulated. This method atomically retrieves and clears the list.
    #
    # @return [Array<Event::System>]
    def get_diagnostics
      @diagnostics_mutex.synchronize do
        result = @diagnostics.dup
        @diagnostics.clear
        result
      end
    end

    # Simulate a user interaction with a widget.
    #
    # Sends an interact message through the bridge and blocks until the
    # renderer responds. Used by scripting and automation -- the test
    # session has its own interact that runs synchronously within the
    # test process.
    #
    # @param action [String] interaction type ("click", "type_text", etc.)
    # @param selector [Hash, nil] target widget selector ({by: "id", value: "btn"})
    # @param payload [Hash] action-specific parameters
    # @param timeout [Numeric] max wait in seconds
    # @return [Array<Object>] events produced by the interaction
    def interact(action, selector = nil, payload = {}, timeout: 5)
      result_queue = Thread::Queue.new
      @event_queue.push([:interact, action, selector, payload, result_queue])
      result = result_queue.pop(timeout: Float(timeout))
      raise Plushie::Error, "interact timed out for #{action}" if result.nil?
      raise Plushie::Error, result[:error] if result.is_a?(Hash) && result[:error]
      result.is_a?(Hash) ? result.fetch(:events, []) : []
    end

    # Waits for an async task with the given tag to complete.
    #
    # If the task has already completed, returns immediately. Otherwise
    # blocks until the task finishes and its result has been processed
    # through update.
    #
    # @param tag [Symbol] the async command tag
    # @param timeout [Numeric] max wait in seconds
    # @return [:ok]
    def await_async(tag, timeout: 5)
      ack_queue = Thread::Queue.new
      @event_queue.push([:await_async, tag, ack_queue])
      result = ack_queue.pop(timeout: Float(timeout))
      raise Plushie::Error, "await_async timed out for #{tag}" if result.nil?
      :ok
    end

    private

    # -- Lifecycle -----------------------------------------------------------

    def start_bridge
      @bridge = Bridge.new(
        event_queue: @event_queue,
        format: @format,
        binary: @binary,
        transport: @transport,
        log_level: @log_level,
        token: @token
      )
      bridge = @bridge or raise Plushie::Error, "bridge not started"
      bridge.start(settings: build_settings)
    end

    def build_settings
      settings = @app.settings
      wc = Plushie.configuration.widget_config
      settings = settings.merge(extension_config: wc) if wc && !wc.empty?
      settings
    end

    def start_dev_server
      server = DevServer.new(event_queue: @event_queue, dirs: @dev_dirs)
      server.start
      @dev_server = server
    end

    def initialize_app
      # @type var init_opts: Hash[Symbol, untyped]
      init_opts = {}
      result = @app.init(init_opts)
      @model, commands = unwrap_result(result)

      render_and_snapshot
      execute_commands(commands)
      sync_subscriptions

      @running = true
    end

    # -- Event loop ----------------------------------------------------------

    def event_loop
      while @running
        msg = @event_queue.pop
        break if msg == :shutdown

        case msg
        in [:renderer_event, event]
          dispatch_event(event)
        in [:renderer_exited, reason]
          handle_renderer_exit(reason)
        in [:renderer_restarted]
          handle_renderer_restarted
        in [:async_result, tag, nonce, result]
          handle_async_result(tag, nonce, result)
        in [:stream_value, tag, nonce, value]
          handle_stream_value(tag, nonce, value)
        in [:timer_tick, tag]
          handle_timer_tick(tag)
        in [:send_after_event, event]
          dispatch_event(event)
        in [:effect_timeout, id]
          handle_effect_timeout(id)
        in [:register_effect_stub, kind, response, ack_queue]
          if @pending_stub_acks.key?(kind)
            ack_queue.push({error: "stub ack already pending for #{kind}"})
          else
            @bridge.send_register_effect_stub(kind, response)
            @pending_stub_acks[kind] = ack_queue
          end
        in [:unregister_effect_stub, kind, ack_queue]
          if @pending_stub_acks.key?(kind)
            ack_queue.push({error: "stub ack already pending for #{kind}"})
          else
            @bridge.send_unregister_effect_stub(kind)
            @pending_stub_acks[kind] = ack_queue
          end
        in [:interact, action, selector, payload, result_queue]
          handle_interact_request(action, selector, payload, result_queue)
        in [:await_async, tag, ack_queue]
          if @pending_await_async.key?(tag)
            ack_queue.push({error: "await already in progress for #{tag}"})
          elsif @async_tasks.key?(tag)
            @pending_await_async[tag] = ack_queue
          else
            ack_queue.push(:ok)
          end
        in :force_rerender
          render_and_patch
        else
          @logger.debug("plushie: unknown message: #{msg.inspect}")
        end
      end
    end

    # -- Event dispatch ------------------------------------------------------

    def dispatch_event(event)
      # Intercept effect stub ack responses
      if event.is_a?(Hash) && event[:type] == :effect_stub_ack
        ack_queue = @pending_stub_acks.delete(event[:kind])
        ack_queue&.push(:ok)
        return
      end

      # Intercept interact_step / interact_response for pending interact.
      # Check the response ID matches the pending interact to reject stale
      # responses from timed-out interactions. Events from stale responses
      # are still dispatched through update -- only the caller completion
      # is skipped.
      if event.is_a?(Hash)
        event_type = (event[:type] || event["type"])&.to_sym
        response_id = event[:id] || event["id"]
        pending = @pending_interact
        if event_type == :interact_step || event_type == :interact_response
          if pending && response_id == pending[:id]
            if event_type == :interact_step
              handle_interact_step(event)
            else
              handle_interact_response(event)
            end
          else
            # Stale or orphaned response. Dispatch events through update
            # but don't complete any pending interact.
            extract_interact_events(event).each { |ev| dispatch_event(ev) }
          end
          return
        end
      end

      # Intercept prop validation diagnostics (never delivered to update)
      if event.is_a?(Event::System) && event.type == :diagnostic
        @logger.warn("plushie: prop validation diagnostic: #{event.data.inspect}")
        @diagnostics_mutex.synchronize { @diagnostics << event }
        return
      end

      # Cancel effect timeout if this is an effect response
      if event.is_a?(Event::Effect)
        timer = @pending_effects.delete(event.request_id)
        timer&.kill
      end

      # Route through canvas widget handlers before app.update.
      # Handlers can consume, transform, or ignore the event.
      unless @canvas_widgets.empty?
        routed_event, @canvas_widgets = CanvasWidget.dispatch_through_widgets(@canvas_widgets, event)
        return if routed_event.nil?  # consumed by a canvas widget
        event = routed_event
      end

      saved_model = @model

      result = @app.update(@model, event)
      @model, commands = unwrap_result(result)
      @consecutive_errors = 0

      render_and_patch
      execute_commands(commands)
      sync_subscriptions
    rescue NoMatchingPatternError => e
      @model = saved_model
      handle_callback_error("update", e,
        hint: "Add an `else` clause to your update method to handle unmatched events")
    rescue => e
      @model = saved_model
      handle_callback_error("update", e)
    end

    # -- Rendering -----------------------------------------------------------

    def render_and_snapshot
      @previous_tree = normalize_view_tree(@app.view(@model))
      @canvas_widgets = CanvasWidget.derive_registry(@previous_tree) if @previous_tree

      tree = @previous_tree or raise Plushie::Error, "missing normalized view tree"
      wire = Tree.node_to_wire(tree)
      encoded = Protocol::Encode.encode_snapshot(wire, @format)
      bridge = @bridge or raise Plushie::Error, "bridge not started"
      bridge.send_encoded(encoded)
      @consecutive_view_errors = 0
    rescue => e
      handle_view_error(e)
      # Send the last known snapshot as a fallback. Without this,
      # interact_step callers hang waiting for a snapshot response.
      resend_last_snapshot
    end

    def render_and_patch
      new_tree = normalize_view_tree(@app.view(@model))
      @canvas_widgets = CanvasWidget.derive_registry(new_tree) if new_tree

      if @previous_tree.nil?
        # First render or post-restart: send full snapshot
        @previous_tree = new_tree
        wire = Tree.node_to_wire(new_tree)
        encoded = Protocol::Encode.encode_snapshot(wire, @format)
        bridge = @bridge or raise Plushie::Error, "bridge not started"
        bridge.send_encoded(encoded)
      else
        ops = Tree.diff(@previous_tree, new_tree)
        @previous_tree = new_tree

        unless ops.empty?
          bridge = @bridge or raise Plushie::Error, "bridge not started"
          bridge.send_encoded(Protocol::Encode.encode_patch(ops, @format))
        end
      end
      @consecutive_view_errors = 0
    rescue => e
      handle_view_error(e)
    end

    def normalize_view_tree(view_tree)
      Tree.normalize_view(view_tree, registry: @canvas_widgets)
    end

    # Re-send the last known snapshot. Used as a fallback when view
    # fails during interact_step -- the renderer expects a snapshot
    # response and will hang without one.
    def resend_last_snapshot
      tree = @previous_tree
      bridge = @bridge
      return unless tree && bridge
      wire = Tree.node_to_wire(tree)
      bridge.send_encoded(Protocol::Encode.encode_snapshot(wire, @format))
    rescue => e
      @logger.error("plushie: failed to resend fallback snapshot: #{e.class}: #{e.message}")
    end

    # -- Result validation ---------------------------------------------------

    def unwrap_result(result)
      case result
      in [model, Command::Cmd => cmd]
        [model, cmd]
      in [model, Array => cmds] if cmds.all? { |c| c.is_a?(Command::Cmd) }
        [model, Command.batch(cmds)]
      else
        if result.is_a?(Array) && result.length == 2
          raise ArgumentError, <<~MSG.chomp
            Invalid return from update/init: second element must be a Command or Array of Commands.
            Got: [#{result[0].class}, #{result[1].class}]

            Valid return shapes:
              model                        # bare model, no commands
              [model, Command.async(...)]  # model + single command
              [model, [cmd1, cmd2]]        # model + command list
          MSG
        end
        [result, Command.none]
      end
    end

    # -- Async handling ------------------------------------------------------

    def handle_async_result(tag, nonce, result)
      entry = @async_tasks[tag]
      return unless entry && entry[:nonce] == nonce
      @async_tasks.delete(tag)
      dispatch_event(Event::Async.new(tag: tag, result: result))
      notify_await_async(tag)
    end

    def handle_stream_value(tag, nonce, value)
      entry = @async_tasks[tag]
      return unless entry && entry[:nonce] == nonce
      dispatch_event(Event::Stream.new(tag: tag, value: value))
    end

    # -- Timer handling -------------------------------------------------------

    def handle_timer_tick(tag)
      # Check if this is a canvas widget timer
      unless @canvas_widgets.empty?
        result = CanvasWidget.handle_widget_timer(@canvas_widgets, tag)
        if result
          event_or_nil, @canvas_widgets = result
          if event_or_nil
            dispatch_event(event_or_nil)
          else
            # Widget handled the timer internally; re-render for state changes
            render_and_patch
            sync_subscriptions
          end
          return
        end
      end

      dispatch_event(Event::Timer.new(
        tag: tag,
        timestamp: Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
      ))
    end

    # -- Effect handling -----------------------------------------------------

    def handle_effect_timeout(id)
      timer = @pending_effects.delete(id)
      return unless timer
      dispatch_event(Event::Effect.new(request_id: id, result: [:error, :timeout]))
    end

    # -- Renderer exit -------------------------------------------------------

    def handle_renderer_exit(reason)
      @logger.warn("plushie: renderer exited: #{reason}")
      fail_pending_interact("renderer_exited")
      flush_pending_effects_on_exit
      flush_pending_stub_acks
      @canvas_widgets = {}
      @model = @app.handle_renderer_exit(@model, reason)
      @previous_tree = nil
      @running = false unless @daemon
    end

    def handle_renderer_restarted
      @logger.info("plushie: renderer restarted -- re-sending settings and snapshot")

      # Clear stale interaction state from the old renderer.
      fail_pending_interact("renderer_restarted")
      flush_pending_effects_on_exit
      flush_pending_stub_acks
      @canvas_widgets = {}
      @previous_tree = nil

      # The new renderer expects Settings as the first message.
      send_settings

      # Re-render to get a fresh tree and send a full snapshot.
      render_and_snapshot

      # Reset renderer subscriptions so sync sees them as new and
      # re-sends subscribe messages to the fresh renderer.
      reset_renderer_subscriptions
      sync_subscriptions
    end

    # -- Error handling ------------------------------------------------------

    def handle_callback_error(callback_name, error, hint: nil)
      @consecutive_errors += 1
      if @consecutive_errors <= 100
        @logger.error("plushie: exception in #{callback_name}: #{error.class}: #{error.message}")
        @logger.error("  Hint: #{hint}") if hint
        error.backtrace&.first(5)&.each { |line| @logger.error("  #{line}") }
      elsif (@consecutive_errors % 1000).zero?
        @logger.error("plushie: #{@consecutive_errors} consecutive errors in #{callback_name} (suppressing)")
      end
    end

    def handle_view_error(error)
      @consecutive_view_errors += 1
      handle_callback_error("view", error)
      if @consecutive_view_errors == 5
        @logger.warn("plushie: view has failed 5 consecutive times -- UI is stale")
      end
    end

    # -- Await async notification --------------------------------------------

    def notify_await_async(tag)
      ack_queue = @pending_await_async.delete(tag)
      ack_queue&.push(:ok)
    end

    # -- Interact ------------------------------------------------------------

    def handle_interact_request(action, selector, payload, result_queue)
      id = SecureRandom.hex(4)
      @pending_interact = {id: id, result_queue: result_queue}
      bridge = @bridge or raise Plushie::Error, "bridge not started"
      bridge.send_encoded(
        Protocol::Encode.encode_interact(id, action, selector, payload, @format)
      )
    end

    def handle_interact_step(response)
      events = extract_interact_events(response)
      # Process events WITHOUT rendering after each one.
      # Matches Elixir's apply_event which defers view/render.
      events.each { |ev| apply_event(ev) }
      # Render once and send a single snapshot (headless protocol).
      render_and_snapshot
      sync_subscriptions
    end

    def handle_interact_response(response)
      events = extract_interact_events(response)
      events.each { |ev| dispatch_event(ev) }
      pending = @pending_interact
      @pending_interact = nil
      return unless pending

      pending[:result_queue]&.push({events: events})
    end

    # Process an event through update + commands WITHOUT rendering.
    # Used by interact_step to batch events before a single render.
    # Matches Elixir's apply_event (runtime.ex lines 972-987).
    def apply_event(event)
      # Route through canvas widget handlers
      unless @canvas_widgets.empty?
        routed_event, @canvas_widgets = CanvasWidget.dispatch_through_widgets(@canvas_widgets, event)
        return if routed_event.nil?
        event = routed_event
      end

      saved_model = @model
      result = @app.update(@model, event)
      @model, commands = unwrap_result(result)
      @consecutive_errors = 0
      execute_commands(commands)
    rescue NoMatchingPatternError => e
      @model = saved_model
      handle_callback_error("update", e,
        hint: "Add an `else` clause to your update method to handle unmatched events")
    rescue => e
      @model = saved_model
      handle_callback_error("update", e)
    end

    def extract_interact_events(response)
      raw = response[:events] || response["events"] || []
      raw.filter_map do |e|
        if e.is_a?(Hash)
          Protocol::Decode.decode_event(e.transform_keys(&:to_s))
        else
          e
        end
      end
    end

    def fail_pending_interact(reason)
      pending = @pending_interact
      @pending_interact = nil
      return unless pending

      pending[:result_queue]&.push({error: reason})
    end

    # -- Resync helpers -------------------------------------------------------

    # Send app settings to the renderer. Used after a restart so the
    # new renderer has the app's configuration.
    def send_settings
      bridge = @bridge or return
      bridge.send_encoded(Protocol::Encode.encode_settings(build_settings, @format))
    end

    # Flush pending effect requests -- the renderer that would have
    # responded is gone. Deliver timeout errors so callers don't hang.
    def flush_pending_effects_on_exit
      @pending_effects.each_value(&:kill)
      @pending_effects.clear
    end

    # Flush pending stub ack queues so callers don't hang.
    def flush_pending_stub_acks
      @pending_stub_acks.each_value { |q| q.push(:ok) }
      @pending_stub_acks.clear
    end

    # Clear renderer-side subscriptions so sync_subscriptions sees them
    # as new and re-sends subscribe messages to the fresh renderer.
    # Timer subscriptions are kept alive -- they run locally.
    def reset_renderer_subscriptions
      renderer_keys = @subscriptions.each_with_object([]) do |(key, entry), keys|
        keys << key if entry[:sub_type] == :renderer
      end
      renderer_keys.each { |key| @subscriptions.delete(key) }
      @subscription_keys = @subscriptions.keys.sort_by(&:to_s)
    end

    # -- Shutdown ------------------------------------------------------------

    def shutdown
      @dev_server&.stop
      @bridge&.stop
      @async_tasks.each_value { |entry| entry[:thread]&.kill }
      @async_tasks.clear
      @pending_effects.each_value(&:kill)
      @pending_effects.clear
      @pending_timers.each_value(&:kill)
      @pending_timers.clear
      @subscriptions.each_value { |entry| entry[:thread]&.kill if entry[:sub_type] == :timer }
      @subscriptions.clear
      # Flush pending stub acks so callers don't hang
      @pending_stub_acks.each_value { |q| q.push(:ok) }
      @pending_stub_acks.clear
      # Flush pending await_async so callers don't hang
      @pending_await_async.each_value { |q| q.push(:ok) }
      @pending_await_async.clear
      # Flush pending interact so callers don't hang
      fail_pending_interact("runtime_shutdown")
    end
  end
end
