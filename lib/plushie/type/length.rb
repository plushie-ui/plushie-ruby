# frozen_string_literal: true

module Plushie
  module Type
    # Size value for the `width` and `height` props on most widgets.
    #
    # Accepts :fill, :shrink, [:fill_portion, n], or a numeric pixel value.
    # Maps to iced's Length enum.
    #
    # @example
    #   column(width: :fill)
    #   column(width: :shrink)
    #   column(width: 200)
    #   column(width: [:fill_portion, 3])
    module Length
      module_function

      # Encode a length value for the wire format.
      #
      # @param value [Symbol, Array, Numeric] the length
      # @return [String, Numeric, Hash]
      def encode(value)
        case value
        when :fill then "fill"
        when :shrink then "shrink"
        when Array
          if value.length == 2 && value[0] == :fill_portion
            {fill_portion: value[1]}
          else
            raise ArgumentError, "invalid length array: #{value.inspect}"
          end
        when Numeric
          raise ArgumentError, "length must be non-negative, got: #{value}" if value < 0
          value
        else
          raise ArgumentError, "invalid length: #{value.inspect}. Use :fill, :shrink, [:fill_portion, n], or a number"
        end
      end
    end
  end
end
