# frozen_string_literal: true

require "logger"
require "securerandom"
require_relative "runtime/commands"
require_relative "runtime/subscriptions"
require_relative "runtime/windows"
require_relative "timer_scheduler"

module Plushie
  # Core event loop for Plushie applications.
  #
  # Owns the Elm-style update cycle: event -> model -> view -> diff -> patch.
  # Processes events sequentially from a thread-safe queue. All state is
  # owned by the runtime thread: no shared mutable state.
  #
  class Runtime
    include Commands
    include Subscriptions

    # Accessors for Runtime submodules (Windows, etc.).
    attr_reader :app, :model, :logger

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
      validate_app!(app)
      validate_transport!(transport)

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
      @timer_scheduler = TimerScheduler.new

      @async_tasks = {}        # tag -> {thread:, nonce:}
      @pending_effects = {}    # wire_id -> timer_thread
      @effect_tags = {}        # tag -> wire_id
      @effect_ids = {}         # wire_id -> tag
      @effect_kinds = {}       # wire_id -> kind string

      # Coalescable event buffer. High-frequency events (move, scroll,
      # scrolled, resize) are stored here, keyed by (window_id, id, type),
      # and flushed at the next event_queue iteration. Last-wins so
      # bursts collapse to the latest value, except scroll events which
      # accumulate their delta_x / delta_y. Keeps update() from drowning
      # in pointer-move events when the host's update() is slow.
      @pending_coalesce = {}   # [window_id, id, type] -> event
      @coalesce_order = []     # insertion order for deterministic flush
      @pending_timers = {}     # event_key -> {thread:, nonce:}
      @subscriptions = {}      # sub_key -> {sub_type:, ...}
      @subscription_keys = []  # sorted keys for short-circuit
      @canvas_widgets = {}     # "#{window_id}\0#{scoped_id}" -> CanvasWidget::RegistryEntry
      @consecutive_errors = 0
      @consecutive_view_errors = 0
      @widget_statuses = {}    # id -> status string
      @focused_widget_id = nil # currently focused widget ID
      @memo_cache = {} # : Hash[untyped, untyped]
      @diagnostics = []        # accumulated prop validation diagnostics
      @diagnostics_mutex = Mutex.new
      @dispatch_depth = 0      # Command.dispatch chain position
      @pending_stub_acks = {}  # kind -> Queue (for sync ack round-trip)
      @pending_await_async = {} # tag -> Queue (for sync await)
      @pending_interact = nil   # {id:, result_queue:} for current interact
      @tracked_windows = Set.new # active window IDs
      @restarting = false

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

    # Returns the ID of the currently focused widget, or nil.
    # Focus is tracked automatically from renderer status events.
    #
    # @return [String, nil]
    def get_focused
      @focused_widget_id
    end

    # Returns true if the most recent view/render call failed, meaning
    # the tree is stale and does not reflect the current model state.
    #
    # @return [Boolean]
    def view_error?
      @consecutive_view_errors > 0
    end

    # @api private
    # Send a window operation to the renderer via the bridge.
    def bridge_send_window_op(op, window_id, settings = {})
      bridge = @bridge or return
      bridge.send_encoded(Protocol::Encode.encode_window_op(op, window_id, Encode.encode_props(settings), @format))
    end

    # Simulate a user interaction with a widget.
    #
    # Sends an interact message through the bridge and blocks until the
    # renderer responds. Used by scripting and automation: the test
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
      # @type var settings: Hash[Symbol, untyped]
      settings = begin
        @app.settings
      rescue => e
        @logger.warn("plushie: settings callback error: #{e.class}: #{e.message}")
        {}
      end
      wc = Plushie.configuration.widget_config
      settings = settings.merge(widget_config: wc) if wc && !wc.empty?
      settings = settings.merge(validate_props: true) if Plushie.configuration.validate_props
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
        # Flush any pending coalescables before blocking on the queue.
        # This mirrors Elixir's zero-delay send_after: coalescables
        # survive only until the next scheduler tick, and here the
        # "tick" is the boundary between inbound message batches.
        flush_coalescables if !@pending_coalesce.empty? && @event_queue.empty?

        msg = @event_queue.pop
        break if msg == :shutdown

        # A fresh entry into the event loop resets the
        # `Command.dispatch` chain counter. The `:dispatched_event`
        # branch below overrides it with the chain position so the
        # guard in `execute_done` caps a pathological update loop.
        @dispatch_depth = 0

        case msg
        in [:renderer_event, event]
          # Coalescable widget events collapse on (window_id, id, type);
          # scroll deltas accumulate.
          if coalescable_event?(event)
            coalesce_event(event)
          else
            flush_coalescables
            dispatch_event(event)
          end
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
        in [:dispatched_event, depth, event]
          # A `Command.dispatch` follow-up: set the depth so the guard
          # in `execute_done` caps the chain, then dispatch the event
          # through the normal update cycle.
          @dispatch_depth = depth
          dispatch_event(event)
        in [:send_after_event, event, nonce]
          entry = @pending_timers[event]
          if entry && entry[:nonce] == nonce
            @pending_timers.delete(event)
            dispatch_event(event)
          end
        in [:effect_timeout, id]
          handle_effect_timeout(id)
        in [:interact_timeout, id]
          handle_interact_timeout(id)
        in [:register_effect_stub, kind, response, ack_queue]
          if @restarting
            ack_queue.push({error: "renderer is restarting"})
          elsif @pending_stub_acks.key?(kind)
            ack_queue.push({error: "stub ack already pending for #{kind}"})
          else
            @bridge.send_register_effect_stub(kind, response)
            @pending_stub_acks[kind] = ack_queue
          end
        in [:unregister_effect_stub, kind, ack_queue]
          if @restarting
            ack_queue.push({error: "renderer is restarting"})
          elsif @pending_stub_acks.key?(kind)
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
          @consecutive_errors = 0
          @consecutive_view_errors = 0
          render_and_patch
        else
          @logger.debug("plushie: unknown message: #{msg.inspect}")
        end
      end
    end

    # -- Coalescable events --------------------------------------------------

    # Widget event types that collapse under high-frequency emission.
    # Mirrors the Elixir / Python / TypeScript coalesce sets: pointer
    # move, scroll, scrolled, and container resize events accumulate
    # quickly when the host's update() is slow, so we keep only the
    # latest value per (window_id, id, type) source before dispatch.
    COALESCABLE_TYPES = %i[move scroll scrolled resize].freeze
    private_constant :COALESCABLE_TYPES

    def coalescable_event?(event)
      event.is_a?(Event::Widget) && COALESCABLE_TYPES.include?(event.type)
    end

    def coalesce_event(event)
      key = [event.window_id, event.id, event.type]
      # Scroll events accumulate delta_x / delta_y so a burst of small
      # wheel ticks delivers one Scroll with the summed deltas, not a
      # lost-to-overwrite chain. Other types are last-wins.
      merged =
        if event.type == :scroll && @pending_coalesce.key?(key)
          existing = @pending_coalesce[key]
          combine_scroll_events(existing, event)
        else
          event
        end

      @coalesce_order << key unless @pending_coalesce.key?(key)
      @pending_coalesce[key] = merged
    end

    def combine_scroll_events(old, new_event)
      # Both events share the same (window_id, id, type) key. Sum the
      # deltas and keep the newest metadata (modifiers, pointer kind).
      empty = {} # : Hash[untyped, untyped]
      old_val = old.value.is_a?(Hash) ? old.value : empty
      new_val = new_event.value.is_a?(Hash) ? new_event.value : empty
      dx = (old_val[:delta_x] || old_val["delta_x"] || 0) +
        (new_val[:delta_x] || new_val["delta_x"] || 0)
      dy = (old_val[:delta_y] || old_val["delta_y"] || 0) +
        (new_val[:delta_y] || new_val["delta_y"] || 0)
      merged_value = new_val.merge(delta_x: dx, delta_y: dy)
      Event::Widget.new(
        type: new_event.type,
        id: new_event.id,
        value: merged_value,
        window_id: new_event.window_id,
        scope: new_event.scope
      )
    end

    def flush_coalescables
      return if @pending_coalesce.empty?
      order = @coalesce_order
      pending = @pending_coalesce
      @coalesce_order = []
      @pending_coalesce = {}
      order.each do |key|
        event = pending[key]
        dispatch_event(event) if event
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
      # are still dispatched through update: only the caller completion
      # is skipped.
      if event.is_a?(Hash)
        event_type = (event[:type] || event["type"])&.to_sym
        response_id = event[:id] || event["id"]
        pending = @pending_interact
        if %i[interact_step interact_response].include?(event_type)
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

      # Intercept status events for focus tracking. The raw :status event
      # is absorbed; derived :focused/:blurred events are dispatched.
      if event.is_a?(Event::Widget) && event.type == :status
        handle_status_event(event)
        return
      end

      # Intercept structured diagnostics from the renderer's diagnostic
      # channel (never delivered to update). Log at the renderer's
      # severity level; pattern-match on event.diagnostic for typed
      # access to the variant payload.
      if event.is_a?(Event::DiagnosticMessage)
        msg = describe_diagnostic(event.diagnostic)
        case event.level
        when :error then @logger.error("plushie: diagnostic: #{msg}")
        when :info then @logger.info("plushie: diagnostic: #{msg}")
        else @logger.warn("plushie: diagnostic: #{msg}")
        end
        @diagnostics_mutex.synchronize { @diagnostics << event }
        return
      end

      # Resolve effect responses: map wire_id -> tag and decode the
      # payload into a typed Event::Effect::Result.*.
      if event.is_a?(Hash) && event[:type] == :effect_response
        wire_id = event[:wire_id]
        timer = @pending_effects.delete(wire_id)
        timer&.kill
        tag = @effect_ids.delete(wire_id)
        kind = @effect_kinds.delete(wire_id)
        @effect_tags.delete(tag) if tag
        return unless tag

        # @effect_ids and @effect_kinds are always written together in
        # execute_effect, so if tag was present kind is too. Fall back
        # to "" if the invariant ever breaks; decode will surface it as
        # an Error result rather than crashing the loop.
        typed = Event::Effect::Result.decode(kind || "", event[:status], event[:payload])
        event = Event::Effect.new(tag: tag, result: typed)

      end

      # Route through canvas widget handlers before app.update.
      # Handlers can consume, transform, or ignore the event.
      # Wrapped in rescue so widget handler errors don't crash the runtime.
      unless @canvas_widgets.empty?
        begin
          widgets_before = @canvas_widgets
          routed_event, @canvas_widgets = CanvasWidget.dispatch_through_widgets(@canvas_widgets, event)
          if routed_event.nil?
            # Event consumed by a widget handler. If the registry changed
            # (widget state updated), re-render to pick up view changes.
            rerender_after_widget_state_change(widgets_before) if @canvas_widgets != widgets_before
            return
          end
          event = routed_event
        rescue => e
          @logger.warn("plushie: widget event routing error: #{e.class}: #{e.message}")
          return
        end
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
      Thread.current[:_plushie_canvas_counter] = 0
      @previous_tree = normalize_view_tree(@app.view(@model))
      @canvas_widgets = CanvasWidget.derive_registry(@previous_tree) if @previous_tree

      tree = @previous_tree or raise Plushie::Error, "missing normalized view tree"
      @tracked_windows = Windows.sync_windows(self, tree, nil, @tracked_windows)

      wire = Tree.node_to_wire(tree)
      encoded = Protocol::Encode.encode_snapshot(wire, @format)
      bridge = @bridge or raise Plushie::Error, "bridge not started"
      bridge.send_encoded(encoded)
      @consecutive_view_errors = 0
    rescue => e
      handle_view_error(e)
      resend_last_snapshot
    end

    def render_and_patch
      Thread.current[:_plushie_canvas_counter] = 0
      new_tree = normalize_view_tree(@app.view(@model))
      @canvas_widgets = CanvasWidget.derive_registry(new_tree) if new_tree

      if @previous_tree.nil?
        @previous_tree = new_tree
        @tracked_windows = Windows.sync_windows(self, new_tree, nil, @tracked_windows)

        wire = Tree.node_to_wire(new_tree)
        encoded = Protocol::Encode.encode_snapshot(wire, @format)
        bridge = @bridge or raise Plushie::Error, "bridge not started"
        bridge.send_encoded(encoded)
      else
        @tracked_windows = Windows.sync_windows(self, new_tree, @previous_tree, @tracked_windows)

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
      UI::MemoCache.seed(@memo_cache)
      result = Tree.normalize_view(view_tree, registry: @canvas_widgets)
      @memo_cache = UI::MemoCache.capture
      result
    end

    # Re-send the last known snapshot. Used as a fallback when view
    # fails during interact_step: the renderer expects a snapshot
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
              [model, Command.task(...)]  # model + single command
              [model, [cmd1, cmd2]]        # model + command list
          MSG
        end

        [result, Command.none]
      end
    end

    # -- Async handling ------------------------------------------------------

    def handle_async_result(tag, nonce, result)
      entry = @async_tasks[tag]
      return unless entry

      case entry[:nonce]
      when :cancelled
        # Task was intentionally cancelled. Silent cleanup.
        @async_tasks.delete(tag)
      when nonce
        # Normal completion or crash. Dispatch through update.
        @async_tasks.delete(tag)
        dispatch_event(Event::Async.new(tag: tag, result: result))
        notify_await_async(tag)
      else
        @logger.debug("plushie: stale async result for tag=#{tag} (nonce mismatch)")
        nil
      end
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

      tag = @effect_ids.delete(id)
      @effect_kinds.delete(id)
      @effect_tags.delete(tag) if tag
      return unless tag

      dispatch_event(Event::Effect.new(tag: tag, result: Event::Effect::Result::Timeout.new))
    end

    # -- Renderer exit -------------------------------------------------------

    def handle_renderer_exit(reason)
      renderer_exit = build_renderer_exit(reason)
      @logger.warn("plushie: renderer exited: #{renderer_exit.message}")
      fail_pending_interact("renderer_exited")
      flush_pending_effects_on_exit
      flush_pending_stub_acks
      @canvas_widgets = {}
      @widget_statuses = {}
      @focused_widget_id = nil
      @restarting = true
      # @type var recovery_error: Exception?
      recovery_error = nil
      begin
        @model = @app.handle_renderer_exit(@model, renderer_exit)
      rescue => e
        @logger.error("plushie: handle_renderer_exit error: #{e.class}: #{e.message}")
        recovery_error = e
      end

      # If the recovery callback failed, dispatch a recovery_failed event
      # so the app can react (show an error banner, reset to safe state).
      if recovery_error
        dispatch_event(Event::System.new(
          type: :recovery_failed,
          value: {error: recovery_error.message, renderer_exit: renderer_exit.message} # : Hash[Symbol, untyped]
        ))
      end

      @previous_tree = nil
      @restarting = false
      @running = false unless @daemon
    end

    def handle_renderer_restarted
      @logger.info("plushie: renderer restarted, re-sending settings and snapshot")
      @consecutive_errors = 0
      @consecutive_view_errors = 0

      # Clear stale interaction state from the old renderer.
      fail_pending_interact("renderer_restarted")
      flush_pending_effects_on_exit
      flush_pending_stub_acks
      @canvas_widgets = {}
      @widget_statuses = {}
      @focused_widget_id = nil
      # Keep @previous_tree intact. render_and_snapshot overwrites it on
      # success. If view fails, resend_last_snapshot uses it as a fallback
      # so the new renderer has something to display.

      # The new renderer expects Settings as the first message.
      send_settings

      # Reset tracked windows so sync_windows re-opens them all.
      @tracked_windows = Set.new

      # Re-render to get a fresh tree and send a full snapshot.
      render_and_snapshot

      # Reset renderer subscriptions so sync sees them as new and
      # re-sends subscribe messages to the fresh renderer.
      reset_renderer_subscriptions
      sync_subscriptions
      @restarting = false
    end

    # -- Status-based focus tracking -----------------------------------------

    # Handle a status event from the renderer. Updates internal focus
    # tracking state and dispatches derived :focused/:blurred events
    # Render a typed Diagnostic variant as a single-line summary for
    # the log channel. Falls back to inspect for variants without a
    # natural one-line form.
    def describe_diagnostic(diag)
      return diag.inspect unless diag.respond_to?(:to_h)
      kind = diag.class.name.to_s.split("::").last.gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, "")
      fields = diag.to_h.reject { |_, v| v.nil? }
      return kind if fields.empty?
      pairs = fields.map { |k, v| "#{k}=#{v.inspect}" }.join(" ")
      "#{kind}: #{pairs}"
    end

    # through update. The raw :status event is not passed to user code.
    def handle_status_event(event)
      status = event.value
      return unless status.is_a?(String)

      id = event.id
      prev_status = @widget_statuses[id]
      @widget_statuses[id] = status

      if status == "focused"
        @focused_widget_id = id
      elsif prev_status == "focused" && @focused_widget_id == id
        @focused_widget_id = nil
      end

      # Derive focused/blurred events from status transitions
      if prev_status != "focused" && status == "focused"
        dispatch_event(Event::Widget.new(
          type: :focused, id: id, window_id: event.window_id, scope: event.scope
        ))
      elsif prev_status == "focused" && status != "focused"
        dispatch_event(Event::Widget.new(
          type: :blurred, id: id, window_id: event.window_id, scope: event.scope
        ))
      end
    end

    # -- Init validation -------------------------------------------------------

    def validate_app!(app)
      missing = %i[init update view].reject { |m| app.respond_to?(m) }
      return if missing.empty?

      raise ArgumentError,
        "app must respond to #{missing.join(", ")}. " \
        "Include Plushie::App or define init/update/view methods."
    end

    def validate_transport!(transport)
      case transport
      when :spawn, :stdio then nil
      when Array
        raise ArgumentError, "unsupported transport: #{transport.inspect}" unless transport[0] == :iostream
      else
        raise ArgumentError,
          "unsupported transport: #{transport.inspect}. Expected :spawn, :stdio, or [:iostream, adapter]"
      end
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

    VIEW_ERROR_WARN_THRESHOLD = 5

    def handle_view_error(error)
      @consecutive_view_errors += 1
      handle_callback_error("view", error)
      return unless @consecutive_view_errors == VIEW_ERROR_WARN_THRESHOLD

      @logger.warn("plushie: view has failed #{VIEW_ERROR_WARN_THRESHOLD} consecutive times; UI is stale")
      inject_frozen_ui_overlay
    end

    # Inject a red error bar into the stale tree to alert the user
    # that the UI is frozen due to view errors. Runs in every mode;
    # the overlay is a production safety net, not a dev-only banner.
    def inject_frozen_ui_overlay
      tree = @previous_tree
      return unless tree && @bridge

      overlay_node = Node.new(
        id: "__frozen_ui__",
        type: "container",
        props: {
          width: "fill",
          height: 40,
          padding: 8,
          style: {background: "#dc2626"}
        },
        children: [
          Node.new(id: "__frozen_ui_text__", type: "text", props: {
            content: "View error: UI is frozen. Fix the error and save to reload.",
            size: 14,
            color: "#ffffff"
          })
        ]
      )

      # Inject the overlay as the first child of the root
      if tree.children.any?
        first_window = tree.children[0]
        new_children = [overlay_node] + first_window.children
        new_window = first_window.with(children: new_children)
        rest = tree.children[1..] || []
        new_tree = tree.with(children: [new_window] + rest)

        bridge = @bridge
        ops = Tree.diff(@previous_tree, new_tree)
        if !ops.empty? && bridge
          bridge.send_encoded(Protocol::Encode.encode_patch(ops, @format))
          @previous_tree = new_tree
        end
      end
    rescue => e
      @logger.debug("plushie: failed to inject frozen UI overlay: #{e.message}")
    end

    # Re-render after a widget's handle_event returned {:update_state, ...}
    # without emitting an event. The widget state changed but the app's
    # update was never called, so we need to re-render to pick up any
    # view changes driven by the new widget state.
    #
    # widgets_before is the registry before the event was dispatched.
    # On view error we revert to this to prevent state-tree desync.
    def rerender_after_widget_state_change(widgets_before)
      render_and_patch
      sync_subscriptions
    rescue => e
      @canvas_widgets = widgets_before
      handle_view_error(e)
    end

    # -- Await async notification --------------------------------------------

    def notify_await_async(tag)
      ack_queue = @pending_await_async.delete(tag)
      ack_queue&.push(:ok)
    end

    # -- Interact ------------------------------------------------------------

    # Internal timeout for pending_interact. If the renderer drops or
    # never responds, this prevents permanent blocking.
    INTERACT_TIMEOUT_S = 15

    def handle_interact_request(action, selector, payload, result_queue)
      id = SecureRandom.hex(4)
      queue = @event_queue
      timer = Thread.new do
        sleep(INTERACT_TIMEOUT_S)
        queue.push([:interact_timeout, id])
      end
      timer.name = "plushie-interact-timeout"
      @pending_interact = {id: id, result_queue: result_queue, timeout_timer: timer}
      bridge = @bridge or raise Plushie::Error, "bridge not started"
      bridge.send_encoded(
        Protocol::Encode.encode_interact(id, action, selector, payload, @format)
      )
    end

    def handle_interact_step(response)
      # Flush pending coalescables so interact-step ordering stays
      # deterministic and the snapshot reflects all prior events.
      flush_coalescables
      events = extract_interact_events(response)
      # Process events WITHOUT rendering after each one.
      # Matches Elixir's apply_event which defers view/render.
      events.each { |ev| apply_event(ev) }
      # Render once and send a single snapshot (headless protocol).
      render_and_snapshot
      sync_subscriptions
    end

    def handle_interact_response(response)
      flush_coalescables
      events = extract_interact_events(response)
      events.each { |ev| dispatch_event(ev) }
      pending = @pending_interact
      @pending_interact = nil
      return unless pending

      # @type var result: Hash[Symbol, untyped]
      result = {events: events}
      result[:view_error] = true if @consecutive_view_errors > 0
      pending[:timeout_timer]&.kill
      pending[:result_queue]&.push(result)
    end

    def handle_interact_timeout(id)
      pending = @pending_interact
      return unless pending && pending[:id] == id

      @logger.warn("plushie: interact #{id} timed out")
      @pending_interact = nil
      pending[:result_queue]&.push({error: "interact timed out"})
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

      pending[:timeout_timer]&.kill
      pending[:result_queue]&.push({error: reason})
    end

    # -- Resync helpers -------------------------------------------------------

    # Send app settings to the renderer. Used after a restart so the
    # new renderer has the app's configuration.
    def send_settings
      bridge = @bridge or return
      bridge.send_encoded(Protocol::Encode.encode_settings(build_settings, @format))
    end

    # Flush pending effect requests: the renderer that would have
    # responded is gone. Deliver error events through update so the
    # app can react. Each effect is removed individually before its
    # error event so new effects started during the flush survive.
    # Rendering is skipped since the renderer is dead.
    def flush_pending_effects_on_exit
      ids = @pending_effects.keys
      ids.each do |id|
        timer = @pending_effects.delete(id)
        timer&.kill
        tag = @effect_ids.delete(id)
        @effect_kinds.delete(id)
        @effect_tags.delete(tag) if tag
        next unless tag

        event = Event::Effect.new(tag: tag, result: Event::Effect::Result::RendererRestarted.new)
        saved_model = @model
        begin
          result = @app.update(@model, event)
          @model, commands = unwrap_result(result)
          execute_commands(commands)
        rescue => e
          @model = saved_model
          handle_callback_error("update (effect flush)", e)
        end
      end
    end

    # Flush pending stub ack queues with an error so callers know the old
    # renderer's stub registry was lost. Callers must re-register.
    def flush_pending_stub_acks
      @pending_stub_acks.each_value { |q| q.push({error: "renderer_restarted"}) }
      @pending_stub_acks.clear
    end

    # Clear renderer-side subscriptions so sync_subscriptions sees them
    # as new and re-sends subscribe messages to the fresh renderer.
    # Timer subscriptions are kept alive: they run locally.
    def reset_renderer_subscriptions
      renderer_keys = @subscriptions.each_with_object([]) do |(key, entry), keys|
        keys << key if entry[:sub_type] == :renderer
      end
      renderer_keys.each { |key| @subscriptions.delete(key) }
      @subscription_keys = @subscriptions.keys.sort_by(&:to_s)
    end

    # Converts a raw renderer exit reason into a structured RendererExit.
    def build_renderer_exit(reason)
      case reason
      in {type: :connection_closed, reason: :heartbeat_timeout}
        RendererExit.new(
          type: :heartbeat_timeout,
          message: "renderer unresponsive (heartbeat timeout)"
        )
      in {type: :connection_closed}
        RendererExit.new(
          type: :connection_lost,
          message: "renderer connection closed"
        )
      in {type: :connection_error, error:}
        RendererExit.new(
          type: :crash,
          message: "renderer connection error: #{error}",
          details: error
        )
      in Exception
        RendererExit.new(
          type: :crash,
          message: "renderer exited unexpectedly: #{reason.message}",
          details: reason
        )
      else
        RendererExit.new(
          type: :crash,
          message: "renderer exited unexpectedly: #{reason.inspect}",
          details: reason
        )
      end
    end

    # -- Shutdown ------------------------------------------------------------

    def shutdown
      @dev_server&.stop
      @bridge&.stop
      @pending_interact&.dig(:timeout_timer)&.kill
      @async_tasks.each_value do |entry|
        entry[:thread]&.kill
        entry[:thread]&.join(0.5)
      end
      @async_tasks.clear
      flush_pending_effects_on_exit
      @pending_coalesce.clear
      @coalesce_order = []
      @pending_timers.each_value do |entry|
        entry[:thread]&.kill
        entry[:thread]&.join(0.5)
      end
      @pending_timers.clear
      @timer_scheduler.stop
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
