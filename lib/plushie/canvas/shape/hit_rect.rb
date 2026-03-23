# frozen_string_literal: true

module Plushie
  module Canvas
    module Shape
      # Explicit hit test rectangle override for interactive canvas shapes.
      #
      # @example
      #   HitRect.new(x: 0, y: 0, w: 100, h: 50)
      HitRect = ::Data.define(:x, :y, :w, :h) do
        def initialize(x:, y:, w:, h:)
          super
        end

        # Backward-compatible hash-style access.
        def [](key) = to_wire[key]

        # @return [Hash] wire-ready hit rect map
        def to_wire
          {x: x, y: y, w: w, h: h}
        end
      end
    end
  end
end
