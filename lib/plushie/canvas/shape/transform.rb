# frozen_string_literal: true

module Plushie
  module Canvas
    module Shape
      # Pushes the current transform state onto the stack.
      #
      # @example
      #   PushTransform.new
      PushTransform = ::Data.define do
        # @return [Hash] wire-ready transform map
        def to_wire
          {type: "push_transform"}
        end
      end

      # Pops the previously saved transform state from the stack.
      #
      # @example
      #   PopTransform.new
      PopTransform = ::Data.define do
        # @return [Hash] wire-ready transform map
        def to_wire
          {type: "pop_transform"}
        end
      end

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
      # @example
      #   Scale.new(x: 2.0, y: 2.0)
      Scale = ::Data.define(:x, :y) do
        def initialize(x:, y:)
          super
        end

        # @return [Hash] wire-ready transform map
        def to_wire
          {type: "scale", x: x, y: y}
        end
      end
    end
  end
end
