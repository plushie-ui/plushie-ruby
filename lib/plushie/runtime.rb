# frozen_string_literal: true

require "logger"

module Plushie
  # Core event loop for Plushie applications.
  #
  # Owns the Elm-style update cycle: event -> model -> view -> diff -> patch.
  # Processes events sequentially from a thread-safe queue.
  class Runtime
    def initialize(app:, transport: :spawn, format: :msgpack, daemon: false,
      binary: nil, log_level: :error)
      @app = app
      @transport = transport
      @format = format
      @daemon = daemon
      @binary = binary
      @log_level = log_level
      @event_queue = Thread::Queue.new
      @model = nil
      @tree = nil
      @bridge = nil
      @running = false
      @async_tasks = {}
      @subscriptions = {}
      @consecutive_errors = 0
      @logger = Logger.new($stderr, level: :warn, progname: "plushie")
    end

    # Run the event loop in the calling thread (blocking).
    def run
      start_bridge
      initialize_app
      event_loop
    ensure
      shutdown
    end

    # Start the event loop in a background thread.
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

    private

    def start_bridge
      @bridge = Bridge.new(
        event_queue: @event_queue,
        format: @format,
        renderer_path: @binary,
        transport: @transport,
        log_level: @log_level
      )
      @bridge.start
    end

    def initialize_app
      result = @app.init({})
      @model, commands = unwrap_result(result)

      send_settings
      render_and_snapshot
      execute_commands(commands)
      sync_subscriptions

      @running = true
    end

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
          dispatch_event(Event::Timer.new(tag:, timestamp: Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)))
        in [:send_after_event, event]
          dispatch_event(event)
        else
          @logger.warn("unknown message: #{msg.inspect}")
        end
      end
    end

    def dispatch_event(event)
      result = @app.update(@model, event)
      @model, commands = unwrap_result(result)
      @consecutive_errors = 0

      render_and_patch
      execute_commands(commands)
      sync_subscriptions
    rescue NoMatchingPatternError => e
      handle_callback_error("update", e)
    rescue StandardError => e
      handle_callback_error("update", e)
    end

    def render_and_snapshot
      @tree = Tree.normalize(@app.view(@model))
      wire_tree = tree_to_wire(@tree)
      @bridge.send_message(Protocol::Encode.encode_snapshot(wire_tree, @format))
    rescue StandardError => e
      handle_callback_error("view", e)
    end

    def render_and_patch
      new_tree = Tree.normalize(@app.view(@model))
      # TODO: implement diffing; for now, send full snapshot
      @tree = new_tree
      wire_tree = tree_to_wire(@tree)
      @bridge.send_message(Protocol::Encode.encode_snapshot(wire_tree, @format))
    rescue StandardError => e
      handle_callback_error("view", e)
    end

    def send_settings
      settings = @app.settings
      @bridge.send_message(Protocol::Encode.encode_settings(settings, @format))
    end

    def unwrap_result(result)
      case result
      in [model, Command::Cmd => cmd]
        [model, cmd]
      in [model, Array => cmds]
        [model, Command.batch(cmds)]
      else
        [result, Command.none]
      end
    end

    def execute_commands(cmd)
      return if cmd.nil?

      case cmd
      in Command::Cmd[type: :none]
        nil
      in Command::Cmd[type: :batch, payload: {commands:}]
        commands.each { |c| execute_commands(c) }
      in Command::Cmd[type: :async, payload: {callable:, tag:}]
        execute_async(callable, tag)
      in Command::Cmd[type: :exit]
        @running = false
      in Command::Cmd[type: :send_after, payload: {delay:, event:}]
        Thread.new do
          sleep(delay / 1000.0)
          @event_queue.push([:send_after_event, event])
        end
      else
        @logger.debug("unhandled command: #{cmd.type}")
      end
    end

    def execute_async(callable, tag)
      # Cancel existing task with same tag
      old = @async_tasks.delete(tag)
      old&.fetch(:thread)&.kill

      nonce = rand(1 << 64)
      queue = @event_queue

      thread = Thread.new do
        result = callable.call
        queue.push([:async_result, tag, nonce, result])
      rescue StandardError => e
        queue.push([:async_result, tag, nonce, [:error, e]])
      end

      @async_tasks[tag] = {thread:, nonce:}
    end

    def handle_async_result(tag, nonce, result)
      entry = @async_tasks[tag]
      return unless entry && entry[:nonce] == nonce

      @async_tasks.delete(tag)
      dispatch_event(Event::Async.new(tag:, result:))
    end

    def handle_stream_value(tag, nonce, value)
      entry = @async_tasks[tag]
      return unless entry && entry[:nonce] == nonce

      dispatch_event(Event::Stream.new(tag:, value:))
    end

    def sync_subscriptions
      # TODO: implement subscription diffing
    end

    def handle_renderer_exit(reason)
      @logger.warn("renderer exited: #{reason}")
      @model = @app.handle_renderer_exit(@model, reason)
      @running = false unless @daemon
    end

    def handle_callback_error(callback_name, error)
      @consecutive_errors += 1
      if @consecutive_errors <= 100
        @logger.error("plushie: exception in #{callback_name}: #{error.class}: #{error.message}")
        error.backtrace&.first(5)&.each { |line| @logger.error("  #{line}") }
      elsif @consecutive_errors % 1000 == 0
        @logger.error("plushie: #{@consecutive_errors} consecutive errors in #{callback_name} (suppressing)")
      end
    end

    def tree_to_wire(trees)
      trees = [trees] unless trees.is_a?(Array)
      return trees.first.to_h if trees.length == 1
      trees.map(&:to_h)
    end

    def shutdown
      @bridge&.stop
      @async_tasks.each_value { |entry| entry[:thread]&.kill }
      @async_tasks.clear
    end
  end
end
