# frozen_string_literal: true

require "logger"
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
      @consecutive_errors = 0
      @diagnostics = []        # accumulated prop validation diagnostics
      @diagnostics_mutex = Mutex.new
      @pending_stub_acks = {}  # kind -> Queue (for sync ack round-trip)
      @pending_await_async = {} # tag -> Queue (for sync await)

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
      @loop_thread = Thread.new { run }
      @loop_thread.name = "plushie-runtime"
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
      result = ack_queue.pop(timeout: timeout)
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
      result = ack_queue.pop(timeout: timeout)
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
      result = ack_queue.pop(timeout: timeout)
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
      settings = @app.settings
      ext_config = Plushie.configuration.extension_config
      settings = settings.merge(extension_config: ext_config) if ext_config && !ext_config.empty?
      @bridge.start(settings: settings)
    end

    def start_dev_server
      opts = {event_queue: @event_queue}
      opts[:dirs] = @dev_dirs if @dev_dirs
      @dev_server = DevServer.new(**opts)
      @dev_server.start
    end

    def initialize_app
      result = @app.init({})
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
        in [:async_result, tag, nonce, result]
          handle_async_result(tag, nonce, result)
        in [:stream_value, tag, nonce, value]
          handle_stream_value(tag, nonce, value)
        in [:timer_tick, tag]
          dispatch_event(Event::Timer.new(
            tag: tag,
            timestamp: Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
          ))
        in [:send_after_event, event]
          dispatch_event(event)
        in [:effect_timeout, id]
          handle_effect_timeout(id)
        in [:register_effect_stub, kind, response, ack_queue]
          @bridge.send_register_effect_stub(kind, response)
          @pending_stub_acks[kind] = ack_queue
        in [:unregister_effect_stub, kind, ack_queue]
          @bridge.send_unregister_effect_stub(kind)
          @pending_stub_acks[kind] = ack_queue
        in [:await_async, tag, ack_queue]
          if @async_tasks.key?(tag)
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
      tree_list = Tree.normalize(@app.view(@model))
      @previous_tree = tree_list.is_a?(Array) ? tree_list.first : tree_list

      wire = Tree.node_to_wire(@previous_tree)
      encoded = Protocol::Encode.encode_snapshot(wire, @format)
      @bridge.send_encoded(encoded)
      @bridge.remember_snapshot(encoded)
    rescue => e
      handle_callback_error("view", e)
    end

    def render_and_patch
      tree_list = Tree.normalize(@app.view(@model))
      new_tree = tree_list.is_a?(Array) ? tree_list.first : tree_list

      if @previous_tree.nil?
        # First render or post-restart: send full snapshot
        @previous_tree = new_tree
        wire = Tree.node_to_wire(new_tree)
        encoded = Protocol::Encode.encode_snapshot(wire, @format)
        @bridge.send_encoded(encoded)
        @bridge.remember_snapshot(encoded)
      else
        ops = Tree.diff(@previous_tree, new_tree)
        @previous_tree = new_tree

        unless ops.empty?
          @bridge.send_encoded(Protocol::Encode.encode_patch(ops, @format))
          # Also remember the current tree as a snapshot for restart
          wire = Tree.node_to_wire(new_tree)
          @bridge.remember_snapshot(Protocol::Encode.encode_snapshot(wire, @format))
        end
      end
    rescue => e
      handle_callback_error("view", e)
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

    # -- Effect handling -----------------------------------------------------

    def handle_effect_timeout(id)
      timer = @pending_effects.delete(id)
      return unless timer
      dispatch_event(Event::Effect.new(request_id: id, result: [:error, :timeout]))
    end

    # -- Renderer exit -------------------------------------------------------

    def handle_renderer_exit(reason)
      @logger.warn("plushie: renderer exited: #{reason}")
      @model = @app.handle_renderer_exit(@model, reason)
      @previous_tree = nil # Force full snapshot on reconnect
      @running = false unless @daemon
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

    # -- Await async notification --------------------------------------------

    def notify_await_async(tag)
      ack_queue = @pending_await_async.delete(tag)
      ack_queue&.push(:ok)
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
    end
  end
end
