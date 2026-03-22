# frozen_string_literal: true

module Plushie
  module Canvas
    module Shape
      # Pushes a clipping rectangle onto the clip stack.
      #
      # @example
      #   PushClip.new(x: 10, y: 10, w: 100, h: 80)
      PushClip = ::Data.define(:x, :y, :w, :h) do
        def initialize(x:, y:, w:, h:)
          super
        end

        # @return [Hash] wire-ready clip map
        def to_wire
          {type: "push_clip", x: x, y: y, w: w, h: self.h}
        end
      end

      # Pops the most recent clipping rectangle from the clip stack.
      #
      # @example
      #   PopClip.new
      PopClip = ::Data.define do
        # @return [Hash] wire-ready clip map
        def to_wire
          {type: "pop_clip"}
        end
      end
    end
  end
end
