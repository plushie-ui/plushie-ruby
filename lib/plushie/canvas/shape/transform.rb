# frozen_string_literal: true

module Plushie
  module Canvas
    module Shape
      # Translates the canvas coordinate origin.
      #
      # @example
      #   Translate.new(x: 100, y: 50)
      Translate = ::Data.define(:x, :y) do
        def initialize(x:, y:)
          super
        end

        # @return [Hash] wire-ready transform map
        def to_wire
          {type: "translate", x: x, y: y}
        end
      end

      # Rotates the canvas coordinate system by an angle in radians.
      #
      # @example
      #   Rotate.new(angle: Math::PI / 4)
      Rotate = ::Data.define(:angle) do
        def initialize(angle:)
          super
        end

        # @return [Hash] wire-ready transform map
        def to_wire
          {type: "rotate", angle: angle}
        end
      end

      # Scales the canvas coordinate system.
      #
      # Use x/y for independent axis scaling, or factor for uniform scaling.
      #
      # @example Independent
      #   Scale.new(x: 2.0, y: 0.5)
      # @example Uniform
      #   Scale.new(factor: 2.0)
      Scale = ::Data.define(:x, :y, :factor) do
        def initialize(x: nil, y: nil, factor: nil)
          super
        end

        # @return [Hash] wire-ready transform map
        def to_wire
          h = {type: "scale"}
          h[:x] = x if x
          h[:y] = y if y
          h[:factor] = factor if factor
          h
        end
      end
    end
  end
end
