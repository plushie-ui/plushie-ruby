# frozen_string_literal: true

module Plushie
  module Type
    # Line height for text widgets.
    #
    # Accepts three forms:
    # - A number (relative multiplier, e.g. 1.5)
    # - +{relative: n}+ for explicit relative line height
    # - +{absolute: n}+ for absolute pixel line height
    #
    # Numbers are passed through as-is (the renderer interprets plain
    # numbers as relative multipliers). Maps are passed through so the
    # renderer can distinguish the two explicit forms.
    #
    # @example
    #   text("msg", "Hello", line_height: 1.5)
    #   text("msg", "Hello", line_height: {relative: 1.2})
    #   text("msg", "Hello", line_height: {absolute: 24})
    module LineHeight
      module_function

      # Encode a line height value for the wire protocol.
      #
      # @param value [Numeric, Hash, nil]
      # @return [Numeric, Hash, nil]
      def encode(value)
        case value
        when Numeric then value
        when Hash
          if value.key?(:relative) || value.key?(:absolute)
            value
          else
            raise ArgumentError, "line_height hash must have :relative or :absolute key, got: #{value.inspect}"
          end
        when nil then nil
        else raise ArgumentError, "invalid line_height: #{value.inspect}"
        end
      end
    end
  end
end
