# frozen_string_literal: true

module Plushie
  module Protocol
    # Shared string-to-symbol parsers used by the decode layer.
    #
    # These convert wire-format strings into Ruby symbols for pattern
    # matching in user code.
    module Parsers
      # Mouse button name mapping.
      # @api private
      MOUSE_BUTTONS = {
        "left" => :left, "right" => :right, "middle" => :middle,
        "back" => :back, "forward" => :forward
      }.freeze

      module_function

      # Parse a mouse button string to a symbol.
      #
      # @param str [String, nil] "left", "right", "middle", "back", "forward"
      # @return [Symbol, String, nil]
      def parse_mouse_button(str)
        return nil if str.nil?
        MOUSE_BUTTONS.fetch(str, str)
      end

      # Parse a scroll unit string to a symbol.
      #
      # @param str [String, nil] "line", "lines", "pixel", "pixels"
      # @return [Symbol, nil] :line, :pixel, or nil
      def parse_scroll_unit(str)
        case str
        when "line", "lines" then :line
        when "pixel", "pixels" then :pixel
        end
      end

      # Parse a pane drag action string to a symbol.
      #
      # @param str [String, nil] "picked", "dropped", "canceled"
      # @return [Symbol, nil]
      def parse_pane_action(str)
        case str
        when "picked" then :picked
        when "dropped" then :dropped
        when "canceled" then :canceled
        end
      end

      # Parse a pane region/edge string to a symbol.
      #
      # @param str [String, nil] "center", "top", "bottom", "left", "right"
      # @return [Symbol, nil]
      def parse_pane_region(str)
        case str
        when "center" then :center
        when "top" then :top
        when "bottom" then :bottom
        when "left" then :left
        when "right" then :right
        end
      end
    end
  end
end
