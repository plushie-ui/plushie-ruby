# frozen_string_literal: true

module Plushie
  module Canvas
    module Shape
      # Drag constraint bounds for interactive canvas shapes.
      #
      # @example
      #   DragBounds.new(min_x: 0, max_x: 400, min_y: 0, max_y: 300)
      #   DragBounds.new(min_x: 0, max_x: 100)
      DragBounds = ::Data.define(:min_x, :max_x, :min_y, :max_y) do
        def initialize(min_x: nil, max_x: nil, min_y: nil, max_y: nil)
          super
        end

        # Backward-compatible hash-style access.
        def [](key) = to_wire[key]

        # @return [Hash] wire-ready bounds map (nil fields stripped)
        def to_wire
          h = {}
          h[:min_x] = min_x if min_x
          h[:max_x] = max_x if max_x
          h[:min_y] = min_y if min_y
          h[:max_y] = max_y if max_y
          h
        end
      end
    end
  end
end
