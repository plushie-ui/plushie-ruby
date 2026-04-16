# frozen_string_literal: true

module Plushie
  class Command
    # Text input commands: selection and cursor movement.
    #
    # All functions support window-qualified paths ("window#widget").
    #
    # @example
    #   Command::Text.select_all("main#email")
    #   Command.select_all("email")  # also works via delegation
    #
    module Text
      module_function

      # Select all text in a text widget.
      # @param widget_id [String]
      # @return [Cmd]
      def select_all(widget_id)
        Command.widget_command(widget_id, 'select_all')
      end

      # Move cursor to the beginning.
      # @param widget_id [String]
      # @return [Cmd]
      def move_cursor_to_front(widget_id)
        Command.widget_command(widget_id, 'move_cursor_to_front')
      end

      # Move cursor to the end.
      # @param widget_id [String]
      # @return [Cmd]
      def move_cursor_to_end(widget_id)
        Command.widget_command(widget_id, 'move_cursor_to_end')
      end

      # Move cursor to a specific position.
      # @param widget_id [String]
      # @param position [Integer]
      # @return [Cmd]
      def move_cursor_to(widget_id, position)
        Command.widget_command(widget_id, 'move_cursor_to', position)
      end

      # Select a range of text.
      # @param widget_id [String]
      # @param start_pos [Integer]
      # @param end_pos [Integer]
      # @return [Cmd]
      def select_range(widget_id, start_pos, end_pos)
        Command.widget_command(widget_id, 'select_range', { start_pos: start_pos, end_pos: end_pos })
      end
    end
  end
end
