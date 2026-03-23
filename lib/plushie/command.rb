# frozen_string_literal: true

module Plushie
  # Commands describe side effects that update wants the runtime to perform.
  #
  # They are pure data -- inspectable, testable, serializable. The runtime
  # interprets them after update returns. Nothing executes inside update.
  #
  # @example Async work
  #   [model, Command.async(-> { fetch_data }, :data_loaded)]
  #
  # @example Focus a widget
  #   [model, Command.focus("input_field")]
  #
  # @example Multiple commands
  #   [model, Command.batch([Command.focus("input"), Command.send_after(3000, :auto_save)])]
  #
  # @see ~/projects/toddy-elixir/lib/plushie/command.ex (reference: 72+ constructors)
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
    # Focus
    # -------------------------------------------------------------------

    # @param widget_id [String]
    # @return [Cmd]
    def self.focus(widget_id) = Cmd.new(type: :focus, payload: {target: widget_id})

    # @return [Cmd]
    def self.focus_next = Cmd.new(type: :focus_next, payload: {})

    # @return [Cmd]
    def self.focus_previous = Cmd.new(type: :focus_previous, payload: {})

    # -------------------------------------------------------------------
    # Text editing
    # -------------------------------------------------------------------

    # @param widget_id [String]
    # @return [Cmd]
    def self.select_all(widget_id) = Cmd.new(type: :select_all, payload: {target: widget_id})

    # @param widget_id [String]
    # @return [Cmd]
    def self.move_cursor_to_front(widget_id) = Cmd.new(type: :move_cursor_to_front, payload: {target: widget_id})

    # @param widget_id [String]
    # @return [Cmd]
    def self.move_cursor_to_end(widget_id) = Cmd.new(type: :move_cursor_to_end, payload: {target: widget_id})

    # @param widget_id [String]
    # @param position [Integer]
    # @return [Cmd]
    def self.move_cursor_to(widget_id, position) = Cmd.new(type: :move_cursor_to, payload: {target: widget_id, position:})

    # @param widget_id [String]
    # @param start_pos [Integer]
    # @param end_pos [Integer]
    # @return [Cmd]
    def self.select_range(widget_id, start_pos, end_pos) = Cmd.new(type: :select_range, payload: {target: widget_id, start: start_pos, end: end_pos})

    # -------------------------------------------------------------------
    # Scroll
    # -------------------------------------------------------------------

    # @param widget_id [String]
    # @param offset_y [Numeric]
    # @return [Cmd]
    def self.scroll_to(widget_id, offset_y) = Cmd.new(type: :scroll_to, payload: {target: widget_id, offset_y:})

    # @param widget_id [String]
    # @param x [Float] relative position 0.0-1.0
    # @param y [Float] relative position 0.0-1.0
    # @return [Cmd]
    def self.snap_to(widget_id, x, y) = Cmd.new(type: :snap_to, payload: {target: widget_id, x:, y:})

    # @param widget_id [String]
    # @return [Cmd]
    def self.snap_to_end(widget_id) = Cmd.new(type: :snap_to_end, payload: {target: widget_id})

    # @param widget_id [String]
    # @param x [Numeric]
    # @param y [Numeric]
    # @return [Cmd]
    def self.scroll_by(widget_id, x, y) = Cmd.new(type: :scroll_by, payload: {target: widget_id, x:, y:})

    # -------------------------------------------------------------------
    # Window operations
    # -------------------------------------------------------------------

    # @param window_id [String]
    # @return [Cmd]
    def self.close_window(window_id) = Cmd.new(type: :close_window, payload: {window_id:})

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

    # @param window_id [String]
    # @return [Cmd]
    def self.gain_focus(window_id) = Cmd.new(type: :window_op, payload: {op: :gain_focus, window_id:})

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
    def self.screenshot(window_id, tag) = Cmd.new(type: :window_query, payload: {op: :screenshot, window_id:, tag:})

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
    def self.allow_automatic_tabbing(enabled) = Cmd.new(type: :window_op, payload: {op: :allow_automatic_tabbing, window_id: "_global", enabled:})

    # -------------------------------------------------------------------
    # Window queries
    # -------------------------------------------------------------------

    # @param window_id [String]
    # @param tag [Symbol]
    # @return [Cmd]
    def self.get_window_size(window_id, tag) = Cmd.new(type: :window_query, payload: {op: :get_size, window_id:, tag:})

    # @param window_id [String]
    # @param tag [Symbol]
    # @return [Cmd]
    def self.get_window_position(window_id, tag) = Cmd.new(type: :window_query, payload: {op: :get_position, window_id:, tag:})

    # @param window_id [String]
    # @param tag [Symbol]
    # @return [Cmd]
    def self.is_maximized(window_id, tag) = Cmd.new(type: :window_query, payload: {op: :is_maximized, window_id:, tag:})

    # @param window_id [String]
    # @param tag [Symbol]
    # @return [Cmd]
    def self.is_minimized(window_id, tag) = Cmd.new(type: :window_query, payload: {op: :is_minimized, window_id:, tag:})

    # @param window_id [String]
    # @param tag [Symbol]
    # @return [Cmd]
    def self.get_mode(window_id, tag) = Cmd.new(type: :window_query, payload: {op: :get_mode, window_id:, tag:})

    # @param window_id [String]
    # @param tag [Symbol]
    # @return [Cmd]
    def self.get_scale_factor(window_id, tag) = Cmd.new(type: :window_query, payload: {op: :get_scale_factor, window_id:, tag:})

    # @param window_id [String]
    # @param tag [Symbol]
    # @return [Cmd]
    def self.raw_id(window_id, tag) = Cmd.new(type: :window_query, payload: {op: :raw_id, window_id:, tag:})

    # @param window_id [String]
    # @param tag [Symbol]
    # @return [Cmd]
    def self.monitor_size(window_id, tag) = Cmd.new(type: :window_query, payload: {op: :monitor_size, window_id:, tag:})

    # -------------------------------------------------------------------
    # System queries
    # -------------------------------------------------------------------

    # @param tag [Symbol]
    # @return [Cmd]
    def self.get_system_theme(tag) = Cmd.new(type: :window_query, payload: {op: :get_system_theme, window_id: "_system", tag:})

    # @param tag [Symbol]
    # @return [Cmd]
    def self.get_system_info(tag) = Cmd.new(type: :window_query, payload: {op: :get_system_info, window_id: "_system", tag:})

    # -------------------------------------------------------------------
    # PaneGrid operations
    # -------------------------------------------------------------------

    # @param grid_id [String]
    # @param pane_id [String]
    # @param axis [Symbol] :horizontal, :vertical
    # @param new_pane_id [String]
    # @return [Cmd]
    def self.pane_split(grid_id, pane_id, axis, new_pane_id) = Cmd.new(type: :widget_op, payload: {op: :pane_split, target: grid_id, pane: pane_id, axis: axis.to_s, new_pane_id:})

    # @param grid_id [String]
    # @param pane_id [String]
    # @return [Cmd]
    def self.pane_close(grid_id, pane_id) = Cmd.new(type: :widget_op, payload: {op: :pane_close, target: grid_id, pane: pane_id})

    # @param grid_id [String]
    # @param pane_a [String]
    # @param pane_b [String]
    # @return [Cmd]
    def self.pane_swap(grid_id, pane_a, pane_b) = Cmd.new(type: :widget_op, payload: {op: :pane_swap, target: grid_id, a: pane_a, b: pane_b})

    # @param grid_id [String]
    # @param pane_id [String]
    # @return [Cmd]
    def self.pane_maximize(grid_id, pane_id) = Cmd.new(type: :widget_op, payload: {op: :pane_maximize, target: grid_id, pane: pane_id})

    # @param grid_id [String]
    # @return [Cmd]
    def self.pane_restore(grid_id) = Cmd.new(type: :widget_op, payload: {op: :pane_restore, target: grid_id})

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
    # Extension
    # -------------------------------------------------------------------

    # Send a command to a native extension widget.
    # @param node_id [String]
    # @param op [String]
    # @param payload [Hash]
    # @return [Cmd]
    def self.extension_command(node_id, op, payload = {}) = Cmd.new(type: :extension_command, payload: {node_id:, op:, data: payload})

    # Batch multiple extension commands.
    # @param commands [Array<Hash>] each with :node_id, :op, :payload
    # @return [Cmd]
    def self.extension_commands(commands) = Cmd.new(type: :extension_commands, payload: {commands:})

    # -------------------------------------------------------------------
    # Test / headless
    # -------------------------------------------------------------------

    # Advance the animation clock. For deterministic testing.
    # @param timestamp [Integer] frame timestamp in milliseconds
    # @return [Cmd]
    def self.advance_frame(timestamp) = Cmd.new(type: :advance_frame, payload: {timestamp:})
  end
end
