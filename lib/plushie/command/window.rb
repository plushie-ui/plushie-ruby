# frozen_string_literal: true

module Plushie
  class Command
    # Window operation commands.
    #
    # == Lifecycle
    # close_window
    #
    # == Sizing and position
    # resize_window, move_window, set_min_size, set_max_size,
    # set_resize_increments, set_resizable
    #
    # == Window state
    # maximize_window, minimize_window, toggle_maximize,
    # set_window_mode, toggle_decorations, set_window_level
    #
    # == Focus and interaction
    # focus_window, drag_window, drag_resize_window,
    # request_attention, show_system_menu
    #
    # == Input
    # enable_mouse_passthrough, disable_mouse_passthrough
    #
    # == Visuals
    # set_icon, screenshot
    #
    module Window
      module_function

      # @param window_id [String]
      # @return [Cmd]
      def close_window(window_id) = Cmd.new(type: :window_op, payload: {op: "close", window_id:})

      # @param window_id [String]
      # @param width [Integer]
      # @param height [Integer]
      # @return [Cmd]
      def resize_window(window_id, width, height) = Cmd.new(type: :window_op, payload: {op: "resize", window_id:, width:, height:})

      # @param window_id [String]
      # @param x [Integer]
      # @param y [Integer]
      # @return [Cmd]
      def move_window(window_id, x, y) = Cmd.new(type: :window_op, payload: {op: "move", window_id:, x:, y:})

      # @param window_id [String]
      # @param maximized [Boolean]
      # @return [Cmd]
      def maximize_window(window_id, maximized = true) = Cmd.new(type: :window_op, payload: {op: "maximize", window_id:, maximized:})

      # @param window_id [String]
      # @param minimized [Boolean]
      # @return [Cmd]
      def minimize_window(window_id, minimized = true) = Cmd.new(type: :window_op, payload: {op: "minimize", window_id:, minimized:})

      # @param window_id [String]
      # @param mode [Symbol] :fullscreen, :windowed, :hidden
      # @return [Cmd]
      def set_window_mode(window_id, mode) = Cmd.new(type: :window_op, payload: {op: "set_mode", window_id:, mode: mode.to_s})

      # @param window_id [String]
      # @return [Cmd]
      def toggle_maximize(window_id) = Cmd.new(type: :window_op, payload: {op: "toggle_maximize", window_id:})

      # @param window_id [String]
      # @return [Cmd]
      def toggle_decorations(window_id) = Cmd.new(type: :window_op, payload: {op: "toggle_decorations", window_id:})

      # Bring window to front and give it focus.
      # @param window_id [String]
      # @return [Cmd]
      def focus_window(window_id) = Cmd.new(type: :window_op, payload: {op: "gain_focus", window_id:})

      # @param window_id [String]
      # @param level [Symbol] :normal, :always_on_top, :always_on_bottom
      # @return [Cmd]
      def set_window_level(window_id, level) = Cmd.new(type: :window_op, payload: {op: "set_level", window_id:, level: level.to_s})

      # @param window_id [String]
      # @return [Cmd]
      def drag_window(window_id) = Cmd.new(type: :window_op, payload: {op: "drag", window_id:})

      # @param window_id [String]
      # @param direction [Symbol]
      # @return [Cmd]
      def drag_resize_window(window_id, direction) = Cmd.new(type: :window_op, payload: {op: "drag_resize", window_id:, direction: direction.to_s})

      # @param window_id [String]
      # @param urgency [Symbol] :informational, :critical
      # @return [Cmd]
      def request_attention(window_id, urgency) = Cmd.new(type: :window_op, payload: {op: "request_attention", window_id:, urgency: urgency&.to_s})

      # @param window_id [String]
      # @param tag [Symbol]
      # @return [Cmd]
      def screenshot(window_id, tag) = Cmd.new(type: :window_query, payload: {op: "screenshot", window_id:, tag: tag.to_s})

      # @param window_id [String]
      # @param resizable [Boolean]
      # @return [Cmd]
      def set_resizable(window_id, resizable) = Cmd.new(type: :window_op, payload: {op: "set_resizable", window_id:, resizable:})

      # @param window_id [String]
      # @param width [Integer]
      # @param height [Integer]
      # @return [Cmd]
      def set_min_size(window_id, width, height) = Cmd.new(type: :window_op, payload: {op: "set_min_size", window_id:, width:, height:})

      # @param window_id [String]
      # @param width [Integer]
      # @param height [Integer]
      # @return [Cmd]
      def set_max_size(window_id, width, height) = Cmd.new(type: :window_op, payload: {op: "set_max_size", window_id:, width:, height:})

      # @param window_id [String]
      # @return [Cmd]
      def enable_mouse_passthrough(window_id) = Cmd.new(type: :window_op, payload: {op: "mouse_passthrough", window_id:, enabled: true})

      # @param window_id [String]
      # @return [Cmd]
      def disable_mouse_passthrough(window_id) = Cmd.new(type: :window_op, payload: {op: "mouse_passthrough", window_id:, enabled: false})

      # @param window_id [String]
      # @return [Cmd]
      def show_system_menu(window_id) = Cmd.new(type: :window_op, payload: {op: "show_system_menu", window_id:})

      # @param window_id [String]
      # @param rgba_data [String] raw RGBA pixel data
      # @param width [Integer]
      # @param height [Integer]
      # @return [Cmd]
      def set_icon(window_id, rgba_data, width, height) = Cmd.new(type: :window_op, payload: {op: "set_icon", window_id:, icon_data: rgba_data, width:, height:})

      # @param window_id [String]
      # @param width [Integer]
      # @param height [Integer]
      # @return [Cmd]
      def set_resize_increments(window_id, width, height) = Cmd.new(type: :window_op, payload: {op: "set_resize_increments", window_id:, width:, height:})

      # @param enabled [Boolean]
      # @return [Cmd]
      def allow_automatic_tabbing(enabled) = Cmd.new(type: :system_op, payload: {op: "allow_automatic_tabbing", enabled:})
    end
  end
end
