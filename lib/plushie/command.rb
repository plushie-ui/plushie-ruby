# frozen_string_literal: true

module Plushie
  # Commands describe side effects that update wants the runtime to perform.
  #
  # They are pure data: inspectable, testable, serializable. The runtime
  # interprets them after update returns. Nothing executes inside update.
  #
  # == Widget commands
  #
  # Widget-targeted commands (focus, scroll, text cursor, pane grid,
  # native widget ops) use the unified wire format:
  #   {type: "command", id: "widget_id", family: "op_name", value: ...}
  #
  # All named constructors (focus, scroll_to, select_all, etc.) call
  # +widget_command+ internally. Use +widget_command+ directly for
  # native widget operations.
  #
  # @example Async work
  #   [model, Command.async(-> { fetch_data }, :data_loaded)]
  #
  # @example Focus a widget
  #   [model, Command.focus("input_field")]
  #
  # @example Scroll to top
  #   [model, Command.scroll_to("content", 0)]
  #
  # @example Native widget command
  #   [model, Command.widget_command("chart-1", "append_data", {values: [1.0, 2.5]})]
  #
  # @example Multiple commands
  #   [model, Command.batch([Command.focus("input"), Command.send_after(3000, :auto_save)])]
  #
  class Command
    # The immutable command data object. All constructors return this.
    Cmd = Data.define(:type, :payload)

    # -------------------------------------------------------------------
    # Basic
    # -------------------------------------------------------------------

    # @return [Cmd] no-op command
    def self.none = Cmd.new(type: :none, payload: {})

    # Run a callable asynchronously. Result delivered as Event::Async.
    # @param callable [Proc, Lambda] the work to run
    # @param tag [Symbol] event tag for the result
    # @return [Cmd]
    def self.async(callable, tag) = Cmd.new(type: :async, payload: {callable:, tag:})

    # Run a callable that emits multiple values via an emit callback.
    # Each emit delivers Event::Stream; the final return delivers Event::Async.
    # @param callable [Proc] receives an emit proc as argument
    # @param tag [Symbol] event tag
    # @return [Cmd]
    def self.stream(callable, tag) = Cmd.new(type: :stream, payload: {callable:, tag:})

    # Cancel a running async or stream task by tag.
    # @param tag [Symbol]
    # @return [Cmd]
    def self.cancel(tag) = Cmd.new(type: :cancel, payload: {tag:})

    # Lift an already-resolved value into the command pipeline.
    # @param value [Object] the resolved value
    # @param mapper_fn [Proc] function that wraps value into an event
    # @return [Cmd]
    def self.done(value, mapper_fn) = Cmd.new(type: :done, payload: {value:, mapper: mapper_fn})

    # Send an event to update after a delay.
    # @param delay_ms [Integer] delay in milliseconds
    # @param event [Object] event to deliver
    # @return [Cmd]
    def self.send_after(delay_ms, event) = Cmd.new(type: :send_after, payload: {delay: delay_ms, event:})

    # Terminate the application.
    # @return [Cmd]
    def self.exit = Cmd.new(type: :exit, payload: {})

    # Combine multiple commands. Executed sequentially.
    # @param commands [Array<Cmd>]
    # @return [Cmd]
    def self.batch(commands) = Cmd.new(type: :batch, payload: {commands:})

    # -------------------------------------------------------------------
    # Widget command (unified wire format)
    # -------------------------------------------------------------------

    # Send a command to a widget by ID.
    #
    # Uses the unified wire format matching events:
    #   {"type": "command", "id": "gauge", "family": "set_value", "value": 72.0}
    #
    # The +value+ defaults to nil for commands with no payload (e.g. reset).
    # The +family+ string identifies the operation. For native widgets, it
    # maps to the Rust widget's handle_widget_op dispatch.
    #
    # @param id [String] target widget ID (supports "window#path" format)
    # @param family [String] operation name
    # @param value [Object, nil] operation-specific data
    # @return [Cmd]
    def self.widget_command(id, family, value = nil)
      Cmd.new(type: :command, payload: {id: id, family: family.to_s, value: value})
    end

    # Send a batch of widget commands processed atomically in one cycle.
    #
    # Each command in the list is a +{id:, family:, value:}+ Hash.
    # All commands are applied before any resulting events are emitted.
    #
    # @param commands [Array<Hash>] each with :id, :family, :value keys
    # @return [Cmd]
    def self.widget_commands(commands)
      Cmd.new(type: :commands, payload: {commands: commands})
    end

    # -------------------------------------------------------------------
    # Focus
    # -------------------------------------------------------------------

    # Focus the widget identified by +widget_id+.
    #
    # Supports window-qualified paths: +"main#email"+ targets widget
    # +"email"+ in window +"main"+.
    #
    # @param widget_id [String]
    # @return [Cmd]
    def self.focus(widget_id)
      widget_command(widget_id, "focus")
    end

    # Move focus to the next focusable widget.
    # @return [Cmd]
    def self.focus_next = Cmd.new(type: :widget_op, payload: {op: "focus_next"})

    # Move focus to the previous focusable widget.
    # @return [Cmd]
    def self.focus_previous = Cmd.new(type: :widget_op, payload: {op: "focus_previous"})

    # -------------------------------------------------------------------
    # Text editing
    # -------------------------------------------------------------------

    # Select all text in a text widget. Supports +"window#path"+.
    # @param widget_id [String]
    # @return [Cmd]
    def self.select_all(widget_id)
      widget_command(widget_id, "select_all")
    end

    # Move cursor to the beginning. Supports +"window#path"+.
    # @param widget_id [String]
    # @return [Cmd]
    def self.move_cursor_to_front(widget_id)
      widget_command(widget_id, "move_cursor_to_front")
    end

    # Move cursor to the end. Supports +"window#path"+.
    # @param widget_id [String]
    # @return [Cmd]
    def self.move_cursor_to_end(widget_id)
      widget_command(widget_id, "move_cursor_to_end")
    end

    # Move cursor to a specific position. Supports +"window#path"+.
    # @param widget_id [String]
    # @param position [Integer]
    # @return [Cmd]
    def self.move_cursor_to(widget_id, position)
      widget_command(widget_id, "move_cursor_to", {position: position})
    end

    # Select a range of text. Supports +"window#path"+.
    # @param widget_id [String]
    # @param start_pos [Integer]
    # @param end_pos [Integer]
    # @return [Cmd]
    def self.select_range(widget_id, start_pos, end_pos)
      widget_command(widget_id, "select_range", {start: start_pos, end: end_pos})
    end

    # -------------------------------------------------------------------
    # Scroll
    # -------------------------------------------------------------------

    # Scroll to an absolute vertical offset. Supports +"window#path"+.
    # @param widget_id [String]
    # @param offset [Numeric] vertical offset in pixels
    # @return [Cmd]
    def self.scroll_to(widget_id, offset)
      widget_command(widget_id, "scroll_to", {x: 0.0, y: offset})
    end

    # Snap to a relative position (0.0 to 1.0). Supports +"window#path"+.
    # @param widget_id [String]
    # @param x [Float] horizontal relative position
    # @param y [Float] vertical relative position
    # @return [Cmd]
    def self.snap_to(widget_id, x, y)
      widget_command(widget_id, "snap_to", {x: x, y: y})
    end

    # Snap to the end of scrollable content. Supports +"window#path"+.
    # @param widget_id [String]
    # @return [Cmd]
    def self.snap_to_end(widget_id)
      widget_command(widget_id, "snap_to_end")
    end

    # Scroll by a relative delta. Supports +"window#path"+.
    # @param widget_id [String]
    # @param x [Numeric] horizontal delta
    # @param y [Numeric] vertical delta
    # @return [Cmd]
    def self.scroll_by(widget_id, x, y)
      widget_command(widget_id, "scroll_by", {x: x, y: y})
    end

    # -------------------------------------------------------------------
    # PaneGrid operations
    # -------------------------------------------------------------------

    # Split a pane in the pane grid.
    # @param grid_id [String]
    # @param pane_id [String]
    # @param axis [Symbol] :horizontal or :vertical
    # @param new_pane_id [String]
    # @return [Cmd]
    def self.pane_split(grid_id, pane_id, axis, new_pane_id)
      widget_command(grid_id, "pane_split", {pane: pane_id, axis: axis.to_s, new_pane_id: new_pane_id})
    end

    # Close a pane in the pane grid.
    # @param grid_id [String]
    # @param pane_id [String]
    # @return [Cmd]
    def self.pane_close(grid_id, pane_id)
      widget_command(grid_id, "pane_close", {pane: pane_id})
    end

    # Swap two panes in the pane grid.
    # @param grid_id [String]
    # @param pane_a [String]
    # @param pane_b [String]
    # @return [Cmd]
    def self.pane_swap(grid_id, pane_a, pane_b)
      widget_command(grid_id, "pane_swap", {a: pane_a, b: pane_b})
    end

    # Maximize a pane in the pane grid.
    # @param grid_id [String]
    # @param pane_id [String]
    # @return [Cmd]
    def self.pane_maximize(grid_id, pane_id)
      widget_command(grid_id, "pane_maximize", {pane: pane_id})
    end

    # Restore all panes from maximized state.
    # @param grid_id [String]
    # @return [Cmd]
    def self.pane_restore(grid_id)
      widget_command(grid_id, "pane_restore")
    end

    # -------------------------------------------------------------------
    # Window operations
    # -------------------------------------------------------------------

    # @param window_id [String]
    # @return [Cmd]
    def self.close_window(window_id) = Cmd.new(type: :widget_op, payload: {op: "close_window", window_id: window_id})

    # @param window_id [String]
    # @param width [Integer]
    # @param height [Integer]
    # @return [Cmd]
    def self.resize_window(window_id, width, height) = Cmd.new(type: :window_op, payload: {op: :resize, window_id:, width:, height:})

    # @param window_id [String]
    # @param x [Integer]
    # @param y [Integer]
    # @return [Cmd]
    def self.move_window(window_id, x, y) = Cmd.new(type: :window_op, payload: {op: :move, window_id:, x:, y:})

    # @param window_id [String]
    # @param maximized [Boolean]
    # @return [Cmd]
    def self.maximize_window(window_id, maximized = true) = Cmd.new(type: :window_op, payload: {op: :maximize, window_id:, maximized:})

    # @param window_id [String]
    # @param minimized [Boolean]
    # @return [Cmd]
    def self.minimize_window(window_id, minimized = true) = Cmd.new(type: :window_op, payload: {op: :minimize, window_id:, minimized:})

    # @param window_id [String]
    # @param mode [Symbol] :fullscreen, :windowed, :hidden
    # @return [Cmd]
    def self.set_window_mode(window_id, mode) = Cmd.new(type: :window_op, payload: {op: :set_mode, window_id:, mode: mode.to_s})

    # @param window_id [String]
    # @return [Cmd]
    def self.toggle_maximize(window_id) = Cmd.new(type: :window_op, payload: {op: :toggle_maximize, window_id:})

    # @param window_id [String]
    # @return [Cmd]
    def self.toggle_decorations(window_id) = Cmd.new(type: :window_op, payload: {op: :toggle_decorations, window_id:})

    # Bring window to front and give it focus.
    # @param window_id [String]
    # @return [Cmd]
    def self.focus_window(window_id) = Cmd.new(type: :window_op, payload: {op: :gain_focus, window_id:})

    # @param window_id [String]
    # @param level [Symbol] :normal, :always_on_top, :always_on_bottom
    # @return [Cmd]
    def self.set_window_level(window_id, level) = Cmd.new(type: :window_op, payload: {op: :set_level, window_id:, level: level.to_s})

    # @param window_id [String]
    # @return [Cmd]
    def self.drag_window(window_id) = Cmd.new(type: :window_op, payload: {op: :drag, window_id:})

    # @param window_id [String]
    # @param direction [Symbol]
    # @return [Cmd]
    def self.drag_resize_window(window_id, direction) = Cmd.new(type: :window_op, payload: {op: :drag_resize, window_id:, direction: direction.to_s})

    # @param window_id [String]
    # @param urgency [Symbol] :informational, :critical
    # @return [Cmd]
    def self.request_user_attention(window_id, urgency) = Cmd.new(type: :window_op, payload: {op: :request_attention, window_id:, urgency: urgency&.to_s})

    # @param window_id [String]
    # @param tag [Symbol]
    # @return [Cmd]
    def self.screenshot(window_id, tag) = Cmd.new(type: :window_query, payload: {op: :screenshot, window_id:, tag: tag.to_s})

    # @param window_id [String]
    # @param resizable [Boolean]
    # @return [Cmd]
    def self.set_resizable(window_id, resizable) = Cmd.new(type: :window_op, payload: {op: :set_resizable, window_id:, resizable:})

    # @param window_id [String]
    # @param width [Integer]
    # @param height [Integer]
    # @return [Cmd]
    def self.set_min_size(window_id, width, height) = Cmd.new(type: :window_op, payload: {op: :set_min_size, window_id:, width:, height:})

    # @param window_id [String]
    # @param width [Integer]
    # @param height [Integer]
    # @return [Cmd]
    def self.set_max_size(window_id, width, height) = Cmd.new(type: :window_op, payload: {op: :set_max_size, window_id:, width:, height:})

    # @param window_id [String]
    # @return [Cmd]
    def self.enable_mouse_passthrough(window_id) = Cmd.new(type: :window_op, payload: {op: :mouse_passthrough, window_id:, enabled: true})

    # @param window_id [String]
    # @return [Cmd]
    def self.disable_mouse_passthrough(window_id) = Cmd.new(type: :window_op, payload: {op: :mouse_passthrough, window_id:, enabled: false})

    # @param window_id [String]
    # @return [Cmd]
    def self.show_system_menu(window_id) = Cmd.new(type: :window_op, payload: {op: :show_system_menu, window_id:})

    # @param window_id [String]
    # @param rgba_data [String] raw RGBA pixel data
    # @param width [Integer]
    # @param height [Integer]
    # @return [Cmd]
    def self.set_icon(window_id, rgba_data, width, height) = Cmd.new(type: :window_op, payload: {op: :set_icon, window_id:, icon_data: rgba_data, width:, height:})

    # @param window_id [String]
    # @param width [Integer]
    # @param height [Integer]
    # @return [Cmd]
    def self.set_resize_increments(window_id, width, height) = Cmd.new(type: :window_op, payload: {op: :set_resize_increments, window_id:, width:, height:})

    # @param enabled [Boolean]
    # @return [Cmd]
    def self.allow_automatic_tabbing(enabled) = Cmd.new(type: :system_op, payload: {op: :allow_automatic_tabbing, enabled:})

    # -------------------------------------------------------------------
    # Window queries
    # -------------------------------------------------------------------

    # @param window_id [String]
    # @param tag [Symbol]
    # @return [Cmd]
    def self.get_window_size(window_id, tag) = Cmd.new(type: :window_query, payload: {op: :get_size, window_id:, tag: tag.to_s})

    # @param window_id [String]
    # @param tag [Symbol]
    # @return [Cmd]
    def self.get_window_position(window_id, tag) = Cmd.new(type: :window_query, payload: {op: :get_position, window_id:, tag: tag.to_s})

    # @param window_id [String]
    # @param tag [Symbol]
    # @return [Cmd]
    def self.is_maximized(window_id, tag) = Cmd.new(type: :window_query, payload: {op: :is_maximized, window_id:, tag: tag.to_s})

    # @param window_id [String]
    # @param tag [Symbol]
    # @return [Cmd]
    def self.is_minimized(window_id, tag) = Cmd.new(type: :window_query, payload: {op: :is_minimized, window_id:, tag: tag.to_s})

    # @param window_id [String]
    # @param tag [Symbol]
    # @return [Cmd]
    def self.get_mode(window_id, tag) = Cmd.new(type: :window_query, payload: {op: :get_mode, window_id:, tag: tag.to_s})

    # @param window_id [String]
    # @param tag [Symbol]
    # @return [Cmd]
    def self.get_scale_factor(window_id, tag) = Cmd.new(type: :window_query, payload: {op: :get_scale_factor, window_id:, tag: tag.to_s})

    # @param window_id [String]
    # @param tag [Symbol]
    # @return [Cmd]
    def self.raw_id(window_id, tag) = Cmd.new(type: :window_query, payload: {op: :raw_id, window_id:, tag: tag.to_s})

    # @param window_id [String]
    # @param tag [Symbol]
    # @return [Cmd]
    def self.monitor_size(window_id, tag) = Cmd.new(type: :window_query, payload: {op: :monitor_size, window_id:, tag: tag.to_s})

    # -------------------------------------------------------------------
    # System queries
    # -------------------------------------------------------------------

    # @param tag [Symbol]
    # @return [Cmd]
    def self.get_system_theme(tag) = Cmd.new(type: :system_query, payload: {op: :get_system_theme, tag: tag.to_s})

    # @param tag [Symbol]
    # @return [Cmd]
    def self.get_system_info(tag) = Cmd.new(type: :system_query, payload: {op: :get_system_info, tag: tag.to_s})

    # -------------------------------------------------------------------
    # Image operations
    # -------------------------------------------------------------------

    # Create an image from encoded data (PNG/JPEG).
    # @param handle [String] image handle name
    # @param data [String] encoded image bytes
    # @return [Cmd]
    def self.create_image(handle, data = nil, width: nil, height: nil, pixels: nil)
      if pixels
        Cmd.new(type: :image_op, payload: {op: :create_image, handle:, pixels:, width:, height:})
      else
        Cmd.new(type: :image_op, payload: {op: :create_image, handle:, data:})
      end
    end

    # Update an existing image handle.
    # @param handle [String]
    # @param data [String, nil] encoded image bytes
    # @return [Cmd]
    def self.update_image(handle, data = nil, width: nil, height: nil, pixels: nil)
      if pixels
        Cmd.new(type: :image_op, payload: {op: :update_image, handle:, pixels:, width:, height:})
      else
        Cmd.new(type: :image_op, payload: {op: :update_image, handle:, data:})
      end
    end

    # Delete an image handle.
    # @param handle [String]
    # @return [Cmd]
    def self.delete_image(handle) = Cmd.new(type: :image_op, payload: {op: :delete_image, handle:})

    # List all image handles. Result via Event::System.
    # @param tag [Symbol]
    # @return [Cmd]
    def self.list_images(tag) = Cmd.new(type: :widget_op, payload: {op: :list_images, tag: tag.to_s})

    # Remove all image handles.
    # @return [Cmd]
    def self.clear_images = Cmd.new(type: :widget_op, payload: {op: :clear_images})

    # -------------------------------------------------------------------
    # Widget queries
    # -------------------------------------------------------------------

    # Compute tree hash. Result via Event::System.
    # @param tag [Symbol]
    # @return [Cmd]
    def self.tree_hash(tag) = Cmd.new(type: :widget_op, payload: {op: :tree_hash, tag: tag.to_s})

    # Find focused widget. Result via Event::System.
    # @param tag [Symbol]
    # @return [Cmd]
    def self.find_focused(tag) = Cmd.new(type: :widget_op, payload: {op: :find_focused, tag: tag.to_s})

    # -------------------------------------------------------------------
    # Font
    # -------------------------------------------------------------------

    # Load a font at runtime from TTF/OTF data.
    # @param data [String] font file bytes
    # @return [Cmd]
    def self.load_font(data) = Cmd.new(type: :widget_op, payload: {op: :load_font, data:})

    # -------------------------------------------------------------------
    # Accessibility
    # -------------------------------------------------------------------

    # Screen reader announcement.
    # @param text [String]
    # @return [Cmd]
    def self.announce(text) = Cmd.new(type: :widget_op, payload: {op: :announce, text:})

    # -------------------------------------------------------------------
    # Test / headless
    # -------------------------------------------------------------------

    # Advance the animation clock. For deterministic testing.
    # @param timestamp [Integer] frame timestamp in milliseconds
    # @return [Cmd]
    def self.advance_frame(timestamp) = Cmd.new(type: :advance_frame, payload: {timestamp:})
  end
end
