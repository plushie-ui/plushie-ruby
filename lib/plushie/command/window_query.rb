# frozen_string_literal: true

module Plushie
  class Command
    # Window query commands. Responses arrive as Event::System.
    #
    # @example
    #   Command::WindowQuery.get_window_size("main", :size_check)
    #
    module WindowQuery
      module_function

      # @param window_id [String]
      # @param tag [Symbol]
      # @return [Cmd]
      def get_window_size(window_id, tag) = Cmd.new(type: :window_query, payload: {op: "get_size", window_id:, tag: tag.to_s})

      # @param window_id [String]
      # @param tag [Symbol]
      # @return [Cmd]
      def get_window_position(window_id, tag) = Cmd.new(type: :window_query, payload: {op: "get_position", window_id:, tag: tag.to_s})

      # @param window_id [String]
      # @param tag [Symbol]
      # @return [Cmd]
      def is_maximized(window_id, tag) = Cmd.new(type: :window_query, payload: {op: "is_maximized", window_id:, tag: tag.to_s})

      # @param window_id [String]
      # @param tag [Symbol]
      # @return [Cmd]
      def is_minimized(window_id, tag) = Cmd.new(type: :window_query, payload: {op: "is_minimized", window_id:, tag: tag.to_s})

      # @param window_id [String]
      # @param tag [Symbol]
      # @return [Cmd]
      def get_mode(window_id, tag) = Cmd.new(type: :window_query, payload: {op: "get_mode", window_id:, tag: tag.to_s})

      # @param window_id [String]
      # @param tag [Symbol]
      # @return [Cmd]
      def get_scale_factor(window_id, tag) = Cmd.new(type: :window_query, payload: {op: "get_scale_factor", window_id:, tag: tag.to_s})

      # @param window_id [String]
      # @param tag [Symbol]
      # @return [Cmd]
      def raw_id(window_id, tag) = Cmd.new(type: :window_query, payload: {op: "raw_id", window_id:, tag: tag.to_s})

      # @param window_id [String]
      # @param tag [Symbol]
      # @return [Cmd]
      def monitor_size(window_id, tag) = Cmd.new(type: :window_query, payload: {op: "monitor_size", window_id:, tag: tag.to_s})
    end
  end
end
