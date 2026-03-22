# frozen_string_literal: true

module Plushie
  module Type
    # Gradient specification for widget backgrounds.
    #
    # Currently supports linear gradients with angle and color stops.
    #
    # @example
    #   Gradient.linear(45, [[0.0, :red], [1.0, :blue]])
    module Gradient
      module_function

      # Create a linear gradient.
      #
      # @param angle [Numeric] angle in degrees
      # @param stops [Array<Array(Float, String|Symbol)>] color stops as [offset, color] pairs
      # @return [Hash] wire-ready gradient map
      def linear(angle, stops)
        {
          type: "linear",
          angle: angle,
          stops: stops.map { |offset, color|
            {offset: offset.to_f, color: Color.cast(color)}
          }
        }
      end

      # Encode a gradient for the wire protocol.
      #
      # @param value [Hash] gradient specification
      # @return [Hash]
      def encode(value)
        case value
        when Hash then value
        else raise ArgumentError, "invalid gradient: #{value.inspect}"
        end
      end
    end
  end
end
