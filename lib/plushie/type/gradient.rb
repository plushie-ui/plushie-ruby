# frozen_string_literal: true

module Plushie
  module Type
    # Gradient specification for widget backgrounds.
    #
    # Build gradients with +linear+:
    #
    #   Gradient.linear([0, 0], [100, 100], [[0.0, :red], [1.0, :blue]])
    #
    # Or from an angle with +linear_from_angle+:
    #
    #   Gradient.linear_from_angle(90, [[0.0, :red], [1.0, :blue]])
    #
    # Stop colors accept any form Color.cast supports (named atoms, hex
    # strings, RGBA maps). They are normalized to canonical hex strings.
    #
    # == Wire format
    #
    # Uses the coordinate-based format matching canvas gradients:
    #
    #   {type: "linear", start: [0, 0], end: [100, 100], stops: [[0.0, "#ff0000"], [1.0, "#0000ff"]]}
    #
    module Gradient
      module_function

      # Create a linear gradient between two coordinate points.
      #
      # @param from [Array(Numeric, Numeric)] start point [x, y]
      # @param to [Array(Numeric, Numeric)] end point [x, y]
      # @param stops [Array<Array(Float, String|Symbol)>] color stops as [offset, color] pairs
      # @return [Hash] wire-ready gradient map
      def linear(from, to, stops)
        {
          type: "linear",
          start: Array(from),
          end: Array(to),
          stops: stops.map { |offset, color| [offset.to_f, Color.cast(color)] }
        }
      end

      # Create a linear gradient from an angle (degrees) and stops.
      #
      # The angle is converted to start/end coordinates on a unit square
      # (0,0 to 1,1). Use this when you want angle-based gradients without
      # computing coordinates manually.
      #
      # @param angle [Numeric] angle in degrees (0 = bottom to top)
      # @param stops [Array<Array(Float, String|Symbol)>] color stops
      # @return [Hash] wire-ready gradient map
      def linear_from_angle(angle, stops)
        rad = angle * Math::PI / 180.0
        dx = Math.sin(rad)
        dy = -Math.cos(rad)
        from = [0.5 - dx * 0.5, 0.5 - dy * 0.5]
        to = [0.5 + dx * 0.5, 0.5 + dy * 0.5]
        linear(from, to, stops)
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
