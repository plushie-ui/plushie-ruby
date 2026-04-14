# frozen_string_literal: true

module Plushie
  class Command
    # Scroll commands: absolute, relative, and snap positioning.
    #
    # All functions support window-qualified paths ("window#widget").
    #
    # @example
    #   Command::Scroll.snap_to("main#content", 0.0, 0.0)
    #   Command.snap_to("content", 0.0, 0.0)  # also works via delegation
    #
    module Scroll
      module_function

      # Scroll to an absolute offset.
      # @param widget_id [String]
      # @param x [Numeric] horizontal offset in pixels
      # @param y [Numeric] vertical offset in pixels
      # @return [Cmd]
      def scroll_to(widget_id, x, y)
        Command.widget_command(widget_id, "scroll_to", {x: x, y: y})
      end

      # Snap to a relative position (0.0 to 1.0).
      # @param widget_id [String]
      # @param x [Float] horizontal relative position
      # @param y [Float] vertical relative position
      # @return [Cmd]
      def snap_to(widget_id, x, y)
        Command.widget_command(widget_id, "snap_to", {x: x, y: y})
      end

      # Snap to the end of scrollable content.
      # @param widget_id [String]
      # @return [Cmd]
      def snap_to_end(widget_id)
        Command.widget_command(widget_id, "snap_to_end")
      end

      # Scroll by a relative delta.
      # @param widget_id [String]
      # @param x [Numeric] horizontal delta
      # @param y [Numeric] vertical delta
      # @return [Cmd]
      def scroll_by(widget_id, x, y)
        Command.widget_command(widget_id, "scroll_by", {x: x, y: y})
      end
    end
  end
end
