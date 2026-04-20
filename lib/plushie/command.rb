# frozen_string_literal: true

require "forwardable"
require_relative "command/text"
require_relative "command/scroll"
require_relative "command/window"
require_relative "command/window_query"
require_relative "command/image"

module Plushie
  # Commands describe side effects that update wants the runtime to perform.
  #
  # They are pure data: inspectable, testable, serializable. The runtime
  # interprets them after update returns. Nothing executes inside update.
  #
  # == Command categories
  #
  # - *Basic*: async, stream, cancel, done, send_after, exit, batch
  # - *Focus*: focus, focus_next, focus_previous
  # - *Text* ({Command::Text}): select_all, move_cursor_to, select_range, ...
  # - *Scroll* ({Command::Scroll}): scroll_to, snap_to, scroll_by, ...
  # - *Window* ({Command::Window}): resize_window, close_window, focus_window, ...
  # - *Window queries* ({Command::WindowQuery}): window_size, window_mode, ...
  # - *Image* ({Command::Image}): create_image, create_image_rgba,
  #   update_image, update_image_rgba, delete_image, ...
  # - *Widget command*: widget_command for native widget operations
  #
  # All submodule methods are also available directly on Command via delegation:
  #   Command.scroll_to("list", 0, 100)       # via delegation
  #   Command::Scroll.scroll_to("list", 0, 100)  # directly
  #
  # @example Async work
  #   [model, Command.task(-> { fetch_data }, :data_loaded)]
  #
  # @example Focus a widget
  #   [model, Command.focus("input_field")]
  #
  # @example Native widget command
  #   [model, Command.widget_command("chart-1", "append_data", {values: [1.0, 2.5]})]
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
    def self.task(callable, tag) = Cmd.new(type: :task, payload: {callable:, tag:})

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
    def self.dispatch(value, mapper_fn) = Cmd.new(type: :dispatch, payload: {value:, mapper: mapper_fn})

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
    def self.widget_batch(commands)
      Cmd.new(type: :commands, payload: {commands: commands})
    end

    # -------------------------------------------------------------------
    # Focus
    # -------------------------------------------------------------------

    # Focus the widget identified by +widget_id+.
    # Supports window-qualified paths: +"main#email"+.
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

    # Move focus to the next focusable widget within the subtree rooted
    # at +scope+. Focus wraps at the subtree boundary. Useful for
    # menus, pane grids, and other keyboard containers that want a
    # bounded Tab cycle without leaking focus to siblings.
    # @param scope [String] the widget ID of the subtree root
    # @return [Cmd]
    def self.focus_next_within(scope)
      Cmd.new(type: :widget_op, payload: {op: "focus_next_within", scope: scope})
    end

    # Move focus to the previous focusable widget within the subtree
    # rooted at +scope+. See {.focus_next_within} for semantics.
    # @param scope [String] the widget ID of the subtree root
    # @return [Cmd]
    def self.focus_previous_within(scope)
      Cmd.new(type: :widget_op, payload: {op: "focus_previous_within", scope: scope})
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
    # System queries
    # -------------------------------------------------------------------

    # @param tag [Symbol]
    # @return [Cmd]
    def self.system_theme(tag) = Cmd.new(type: :system_query, payload: {op: "get_system_theme", tag: tag.to_s})

    # @param tag [Symbol]
    # @return [Cmd]
    def self.system_info(tag) = Cmd.new(type: :system_query, payload: {op: "get_system_info", tag: tag.to_s})

    # -------------------------------------------------------------------
    # Widget queries (global, not targeted at a widget)
    # -------------------------------------------------------------------

    # Compute tree hash. Result via Event::System.
    # @param tag [Symbol]
    # @return [Cmd]
    def self.tree_hash(tag) = Cmd.new(type: :widget_op, payload: {op: "tree_hash", tag: tag.to_s})

    # Find focused widget. Result via Event::System.
    # @param tag [Symbol]
    # @return [Cmd]
    def self.find_focused(tag) = Cmd.new(type: :widget_op, payload: {op: "find_focused", tag: tag.to_s})

    # -------------------------------------------------------------------
    # Font
    # -------------------------------------------------------------------

    # Load a font at runtime from TTF/OTF data.
    # @param family [String] font family name the app will refer to this font by
    # @param data [String] font file bytes
    # @return [Cmd]
    def self.load_font(family, data) = Cmd.new(type: :widget_op, payload: {op: "load_font", family:, data:})

    # -------------------------------------------------------------------
    # Accessibility
    # -------------------------------------------------------------------

    # Screen reader announcement.
    #
    # +politeness+ controls how assistive technology delivers the
    # announcement. +:polite+ (the default) waits for a gap in the
    # current announcement and is correct for most toast-style
    # feedback. +:assertive+ interrupts the current announcement and
    # should be reserved for urgent context the user must hear
    # immediately.
    # @param text [String]
    # @param politeness [Symbol] +:polite+ (default) or +:assertive+
    # @return [Cmd]
    def self.announce(text, politeness = :polite)
      unless %i[polite assertive].include?(politeness)
        raise ArgumentError, "politeness must be :polite or :assertive, got #{politeness.inspect}"
      end
      Cmd.new(type: :widget_op, payload: {op: "announce", text:, politeness: politeness.to_s})
    end

    # -------------------------------------------------------------------
    # Test / headless
    # -------------------------------------------------------------------

    # Advance the animation clock. For deterministic testing.
    # @param timestamp [Integer] frame timestamp in milliseconds
    # @return [Cmd]
    def self.advance_frame(timestamp) = Cmd.new(type: :advance_frame, payload: {timestamp:})

    # -------------------------------------------------------------------
    # Delegations from submodules
    # -------------------------------------------------------------------
    # Both Command.scroll_to(...) and Command::Scroll.scroll_to(...) work.

    # Text
    class << self
      extend Forwardable

      def_delegator Text, :select_all
      def_delegator Text, :move_cursor_to_front
      def_delegator Text, :move_cursor_to_end
      def_delegator Text, :move_cursor_to
      def_delegator Text, :select_range

      # Scroll
      def_delegator Scroll, :scroll_to
      def_delegator Scroll, :snap_to
      def_delegator Scroll, :snap_to_end
      def_delegator Scroll, :scroll_by

      # Window
      def_delegator Window, :close_window
      def_delegator Window, :resize_window
      def_delegator Window, :move_window
      def_delegator Window, :maximize_window
      def_delegator Window, :minimize_window
      def_delegator Window, :set_window_mode
      def_delegator Window, :toggle_maximize
      def_delegator Window, :toggle_decorations
      def_delegator Window, :focus_window
      def_delegator Window, :set_window_level
      def_delegator Window, :drag_window
      def_delegator Window, :drag_resize_window
      def_delegator Window, :request_attention
      def_delegator Window, :set_resizable
      def_delegator Window, :set_min_size
      def_delegator Window, :set_max_size
      def_delegator Window, :enable_mouse_passthrough
      def_delegator Window, :disable_mouse_passthrough
      def_delegator Window, :show_system_menu
      def_delegator Window, :set_icon
      def_delegator Window, :set_resize_increments
      def_delegator Window, :allow_automatic_tabbing
      def_delegator Window, :screenshot

      # Window queries
      def_delegator WindowQuery, :window_size
      def_delegator WindowQuery, :window_position
      def_delegator WindowQuery, :is_maximized
      def_delegator WindowQuery, :is_minimized
      def_delegator WindowQuery, :window_mode
      def_delegator WindowQuery, :scale_factor
      def_delegator WindowQuery, :raw_id
      def_delegator WindowQuery, :monitor_size

      # Image
      def_delegator Image, :create_image
      def_delegator Image, :create_image_rgba
      def_delegator Image, :update_image
      def_delegator Image, :update_image_rgba
      def_delegator Image, :delete_image
      def_delegator Image, :list_images
      def_delegator Image, :clear_images
    end
  end
end
