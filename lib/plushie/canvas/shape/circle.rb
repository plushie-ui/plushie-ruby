# frozen_string_literal: true

module Plushie
  module Canvas
    module Shape
      # Circle shape.
      Circle = ::Data.define(:x, :y, :r, :fill, :stroke, :stroke_width, :opacity) do
        def initialize(x:, y:, r:, fill: nil, stroke: nil, stroke_width: nil, opacity: nil)
          super
        end

        # Access shape properties by key.
        #
        # @param key [Symbol]
        # @return [Object]
        def [](key) = to_wire[key]

        # Encode shape for the wire protocol.
        # @api private
        def to_wire
          h = {type: "circle", x: x, y: y, r: r}
          h[:fill] = fill if fill
          h[:stroke] = stroke if stroke
          h[:stroke_width] = stroke_width if stroke_width
          h[:opacity] = opacity if opacity
          h
        end
      end
    end
  end
end
