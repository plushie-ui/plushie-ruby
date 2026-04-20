# frozen_string_literal: true

module Plushie
  class Runtime
    # Command execution engine for the Plushie runtime.
    #
    # Handles all Command::Cmd types returned by app.update and app.init.
    # Included into Runtime as a mixin.
    #
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
        when :task then execute_async(cmd.payload[:callable], cmd.payload[:tag])
        when :stream then execute_stream(cmd.payload[:callable], cmd.payload[:tag])
        when :cancel then cancel_task(cmd.payload[:tag])
        when :dispatch then execute_done(cmd.payload[:value], cmd.payload[:mapper])
        when :send_after then execute_send_after(cmd.payload[:delay], cmd.payload[:event])
        when :exit then @running = false

        # Unified widget-targeted command (focus, scroll, text, pane, native)
        when :command
          send_command(cmd.payload)

        # Batched widget-targeted commands
        when :commands
          send_commands(cmd.payload[:commands])

        # Global widget operations (not targeted at a specific widget)
        when :widget_op
          send_widget_op(cmd.payload[:op], cmd.payload.except(:op))

        # Window operations
        when :window_op
          send_window_op(cmd.payload)

        when :window_query
          send_window_query(cmd.payload)

        when :system_op
          send_system_op(cmd.payload)

        when :system_query
          send_system_query(cmd.payload)

        # Effects
        when :effect
          execute_effect(cmd.payload)

        # Image operations
        when :image_op
          send_image_op(cmd.payload)

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
        rescue => e
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
        rescue => e
          queue.push([:async_result, tag, nonce, [:error, e]])
        end
        thread.name = "plushie-stream-#{tag}"

        @async_tasks[tag] = {thread: thread, nonce: nonce}
      end

      # Cancel a running async/stream task.
      # Marks the entry as cancelled instead of deleting it. The async
      # result handler owns cleanup, preventing a race where Thread.kill
      # triggers the rescue block that pushes an async_result after the
      # entry was already deleted.
      def cancel_task(tag)
        entry = @async_tasks[tag]
        return unless entry && entry[:nonce] != :cancelled

        entry[:thread]&.kill
        @async_tasks[tag] = {thread: entry[:thread], nonce: :cancelled}
      end

      # Dispatch a done command immediately.
      def execute_done(value, mapper)
        event = mapper.call(value)
        @event_queue.push([:send_after_event, event])
      rescue => e
        @logger.warn("plushie: Command.done mapper error: #{e.class}: #{e.message}")
      end

      # Schedule a delayed event.
      # Uses a monotonic nonce to handle the Thread.kill race: if the old
      # timer already pushed its event to the queue before being killed,
      # the handler discards stale nonces.
      def execute_send_after(delay_ms, event)
        queue = @event_queue
        # Cancel existing timer for the same event key
        old_entry = @pending_timers[event]
        old_entry&.fetch(:thread)&.kill

        nonce = rand(1 << 64)
        thread = Thread.new do
          sleep(delay_ms / 1000.0)
          queue.push([:send_after_event, event, nonce])
        end
        thread.name = "plushie-timer"
        @pending_timers[event] = {thread: thread, nonce: nonce}
      end

      # Execute an effect request (send to renderer + start timeout).
      def execute_effect(payload)
        id = payload[:id]
        tag = payload[:tag]
        kind = payload[:kind]
        opts = payload[:opts] || {}

        # One effect per tag: discard previous if same tag is in flight.
        if tag && (prev_id = @effect_tags[tag])
          timer = @pending_effects.delete(prev_id)
          timer&.kill
          @effect_ids.delete(prev_id)
          @effect_kinds.delete(prev_id)
        end

        # Track tag <-> wire ID mapping plus the effect kind (needed
        # by the response decoder to pick the right typed result).
        @effect_tags[tag] = id if tag
        @effect_ids[id] = tag
        @effect_kinds[id] = kind

        @bridge.send_encoded(
          Protocol::Encode.encode_effect(id, kind, opts, @format)
        )

        # Start timeout timer
        timeout = payload[:timeout] || Effect.default_timeout(kind)
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
        settings[:tag] = payload[:tag].to_s if payload[:tag]
        @bridge.send_encoded(
          Protocol::Encode.encode_window_op(op, window_id, settings, @format)
        )
      end

      # Send a system-level operation.
      def send_system_op(payload)
        op = payload[:op]
        settings = payload.except(:op)
        @bridge.send_encoded(
          Protocol::Encode.encode_system_op(op, settings, @format)
        )
      end

      # Send a system-level query.
      def send_system_query(payload)
        op = payload[:op]
        settings = payload.except(:op)
        @bridge.send_encoded(
          Protocol::Encode.encode_system_query(op, settings, @format)
        )
      end

      # Send an image operation.
      def send_image_op(payload)
        @bridge.send_encoded(
          Protocol::Encode.encode_image_op(payload[:op].to_s, payload, @format)
        )
      end

      # Send a single widget-targeted command via the unified wire format.
      def send_command(payload)
        @bridge.send_encoded(
          Protocol::Encode.encode_command(
            payload[:id], payload[:family], payload[:value], @format
          )
        )
      end

      # Send batched widget-targeted commands.
      def send_commands(commands)
        @bridge.send_encoded(
          Protocol::Encode.encode_commands(commands, @format)
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
