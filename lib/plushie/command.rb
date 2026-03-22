# frozen_string_literal: true

module Plushie
  # Commands describe side effects that update wants the runtime to perform.
  #
  # They are pure data -- inspectable, testable, serializable. The runtime
  # interprets them after update returns. Nothing executes inside update.
  #
  #   def update(model, event)
  #     case event
  #     in Event::Widget[type: :click, id: "save"]
  #       [model, Command.async(-> { save(model) }, :save_result)]
  #     end
  #   end
  #
  class Command
    Cmd = Data.define(:type, :payload)

    # No-op command. Returned implicitly when update returns a bare model.
    def self.none
      Cmd.new(type: :none, payload: {})
    end

    # Run a callable asynchronously. Result delivered as Event::Async.
    #
    #   Command.async(-> { fetch_data }, :data_loaded)
    #
    def self.async(callable, tag)
      Cmd.new(type: :async, payload: {callable:, tag:})
    end

    # Run a callable that emits multiple values. Each emit delivers
    # Event::Stream; the final return delivers Event::Async.
    #
    #   Command.stream(->(emit) { lines.each { emit.(_1) } }, :import)
    #
    def self.stream(callable, tag)
      Cmd.new(type: :stream, payload: {callable:, tag:})
    end

    # Cancel a running async or stream task by tag.
    def self.cancel(tag)
      Cmd.new(type: :cancel, payload: {tag:})
    end

    # Lift an already-resolved value into the command pipeline.
    # Dispatches mapper_fn.(value) through update immediately.
    def self.done(value, mapper_fn)
      Cmd.new(type: :done, payload: {value:, mapper: mapper_fn})
    end

    # Send an event to update after a delay.
    #
    #   Command.send_after(3000, :clear_message)
    #
    def self.send_after(delay_ms, event)
      Cmd.new(type: :send_after, payload: {delay: delay_ms, event:})
    end

    # Terminate the application.
    def self.exit
      Cmd.new(type: :exit, payload: {})
    end

    # Focus a widget by ID.
    def self.focus(widget_id)
      Cmd.new(type: :focus, payload: {target: widget_id})
    end

    # Focus the next focusable widget.
    def self.focus_next
      Cmd.new(type: :focus, payload: {target: :next})
    end

    # Focus the previous focusable widget.
    def self.focus_previous
      Cmd.new(type: :focus, payload: {target: :previous})
    end

    # Select all text in a widget.
    def self.select_all(widget_id)
      Cmd.new(type: :select_all, payload: {target: widget_id})
    end

    # Scroll to absolute vertical position.
    def self.scroll_to(widget_id, offset_y)
      Cmd.new(type: :scroll_to, payload: {target: widget_id, offset_y:})
    end

    # Snap scroll to absolute offset.
    def self.snap_to(widget_id, x, y)
      Cmd.new(type: :snap_to, payload: {target: widget_id, x:, y:})
    end

    # Snap to end of scrollable content.
    def self.snap_to_end(widget_id)
      Cmd.new(type: :snap_to_end, payload: {target: widget_id})
    end

    # Scroll by relative delta.
    def self.scroll_by(widget_id, x, y)
      Cmd.new(type: :scroll_by, payload: {target: widget_id, x:, y:})
    end

    # Close a window by ID.
    def self.close_window(window_id)
      Cmd.new(type: :close_window, payload: {window_id:})
    end

    # Set window mode (:fullscreen, :windowed, etc.)
    def self.set_window_mode(window_id, mode)
      Cmd.new(type: :window_op, payload: {op: :set_mode, window_id:, mode:})
    end

    # Set window level (:normal, :always_on_top, :always_on_bottom)
    def self.set_window_level(window_id, level)
      Cmd.new(type: :window_op, payload: {op: :set_level, window_id:, level:})
    end

    # Resize a window.
    def self.resize_window(window_id, width, height)
      Cmd.new(type: :window_op, payload: {op: :resize, window_id:, width:, height:})
    end

    # Move a window.
    def self.move_window(window_id, x, y)
      Cmd.new(type: :window_op, payload: {op: :move, window_id:, x:, y:})
    end

    # Combine multiple commands. Executed sequentially by the runtime.
    #
    #   Command.batch([Command.focus("input"), Command.send_after(5000, :auto_save)])
    #
    def self.batch(commands)
      Cmd.new(type: :batch, payload: {commands:})
    end

    # Send a command directly to a native extension widget.
    def self.extension_command(node_id, op, payload = {})
      Cmd.new(type: :extension_command, payload: {node_id:, op:, data: payload})
    end
  end
end
