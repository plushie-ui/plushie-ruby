# frozen_string_literal: true

module Plushie
  class Runtime
    # Command execution engine for the Plushie runtime.
    #
    # Handles all Command::Cmd types returned by app.update and app.init.
    # Included into Runtime as a mixin.
    #
    # @see ~/projects/toddy-elixir/lib/plushie/runtime/commands.ex
    module Commands
      private

      # Execute a command or list of commands, threading state.
      #
      # @param cmd [Command::Cmd, nil]
      def execute_commands(cmd)
        return if cmd.nil?

        case cmd.type
        when :none then nil
        when :batch then cmd.payload[:commands]&.each { |c| execute_commands(c) }
        when :async then execute_async(cmd.payload[:callable], cmd.payload[:tag])
        when :stream then execute_stream(cmd.payload[:callable], cmd.payload[:tag])
        when :cancel then cancel_task(cmd.payload[:tag])
        when :done then execute_done(cmd.payload[:value], cmd.payload[:mapper])
        when :send_after then execute_send_after(cmd.payload[:delay], cmd.payload[:event])
        when :exit then @running = false

        # Widget operations (sent to renderer via bridge)
        when :focus, :focus_next, :focus_previous,
          :select_all, :move_cursor_to_front, :move_cursor_to_end,
          :move_cursor_to, :select_range,
          :scroll_to, :snap_to, :snap_to_end, :scroll_by
          send_widget_op(cmd.type, cmd.payload)

        when :close_window
          send_widget_op(:close_window, cmd.payload)

        when :widget_op
          send_widget_op(cmd.payload[:op], cmd.payload.except(:op))

        # Window operations
        when :window_op
          send_window_op(cmd.payload)

        when :window_query
          send_window_query(cmd.payload)

        # Effects
        when :effect
          execute_effect(cmd.payload)

        # Image operations
        when :image_op
          send_image_op(cmd.payload)

        # Extensions
        when :extension_command
          send_extension_command(cmd.payload)

        when :extension_commands
          send_extension_commands(cmd.payload[:commands])

        # Test
        when :advance_frame
          send_advance_frame(cmd.payload[:timestamp])

        else
          @logger.debug("plushie: unhandled command type: #{cmd.type}")
        end
      end

      # Spawn a dedicated thread for async work with nonce tracking.
      def execute_async(callable, tag)
        cancel_task(tag)
        nonce = rand(1 << 64)
        queue = @event_queue

        thread = Thread.new do
          result = callable.call
          queue.push([:async_result, tag, nonce, result])
        rescue StandardError => e
          queue.push([:async_result, tag, nonce, [:error, e]])
        end
        thread.name = "plushie-async-#{tag}"

        @async_tasks[tag] = {thread: thread, nonce: nonce}
      end

      # Spawn a thread for streaming work with emit callback.
      def execute_stream(callable, tag)
        cancel_task(tag)
        nonce = rand(1 << 64)
        queue = @event_queue
        emit = ->(value) { queue.push([:stream_value, tag, nonce, value]) }

        thread = Thread.new do
          result = callable.call(emit)
          queue.push([:async_result, tag, nonce, result])
        rescue StandardError => e
          queue.push([:async_result, tag, nonce, [:error, e]])
        end
        thread.name = "plushie-stream-#{tag}"

        @async_tasks[tag] = {thread: thread, nonce: nonce}
      end

      # Cancel a running async/stream task.
      def cancel_task(tag)
        entry = @async_tasks.delete(tag)
        entry&.fetch(:thread)&.kill
      end

      # Dispatch a done command immediately.
      def execute_done(value, mapper)
        event = mapper.call(value)
        @event_queue.push([:send_after_event, event])
      end

      # Schedule a delayed event.
      def execute_send_after(delay_ms, event)
        queue = @event_queue
        # Cancel existing timer for the same event key
        old = @pending_timers.delete(event)
        old&.kill

        thread = Thread.new do
          sleep(delay_ms / 1000.0)
          queue.push([:send_after_event, event])
        end
        thread.name = "plushie-timer"
        @pending_timers[event] = thread
      end

      # Execute an effect request (send to renderer + start timeout).
      def execute_effect(payload)
        id = payload[:id]
        kind = payload[:kind]
        opts = payload[:opts] || {}

        @bridge.send_encoded(
          Protocol::Encode.encode_effect(id, kind, opts, @format)
        )

        # Start timeout timer
        timeout = payload[:timeout] || Effects.default_timeout(kind)
        queue = @event_queue
        timer = Thread.new do
          sleep(timeout / 1000.0)
          queue.push([:effect_timeout, id])
        end
        timer.name = "plushie-effect-timeout"
        @pending_effects[id] = timer
      end

      # Send a widget operation to the renderer.
      def send_widget_op(op, payload)
        @bridge.send_encoded(
          Protocol::Encode.encode_widget_op(op, payload, @format)
        )
      end

      # Send a window operation to the renderer.
      def send_window_op(payload)
        op = payload[:op]
        window_id = payload[:window_id]
        settings = payload.except(:op, :window_id)
        @bridge.send_encoded(
          Protocol::Encode.encode_window_op(op, window_id, settings, @format)
        )
      end

      # Send a window query (response arrives as effect_response or op_query_response).
      def send_window_query(payload)
        op = payload[:op]
        window_id = payload[:window_id]
        settings = payload.except(:op, :window_id, :tag)
        settings[:request_id] = payload[:tag].to_s if payload[:tag]
        @bridge.send_encoded(
          Protocol::Encode.encode_window_op(op, window_id, settings, @format)
        )
      end

      # Send an image operation.
      def send_image_op(payload)
        @bridge.send_encoded(
          Protocol::Encode.encode_image_op(payload[:op].to_s, payload, @format)
        )
      end

      # Send a single extension command.
      def send_extension_command(payload)
        @bridge.send_encoded(
          Protocol::Encode.encode_extension_command(
            payload[:node_id], payload[:op].to_s, payload[:data] || {}, @format
          )
        )
      end

      # Send batched extension commands.
      def send_extension_commands(commands)
        @bridge.send_encoded(
          Protocol::Encode.encode_extension_commands(commands, @format)
        )
      end

      # Advance the animation clock.
      def send_advance_frame(timestamp)
        @bridge.send_encoded(
          Protocol::Encode.encode_advance_frame(timestamp, @format)
        )
      end
    end
  end
end
