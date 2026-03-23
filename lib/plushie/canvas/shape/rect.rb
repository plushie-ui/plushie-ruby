# frozen_string_literal: true

module Plushie
  module Canvas
    module Shape
      # Rectangle shape.
      Rect = ::Data.define(:x, :y, :w, :h, :fill, :stroke, :stroke_width, :opacity, :interactive) do
        def initialize(x:, y:, w:, h:, fill: nil, stroke: nil, stroke_width: nil, opacity: nil, interactive: nil)
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
          h = {type: "rect", x: x, y: y, w: w, h: self.h}
          h[:fill] = fill if fill
          h[:stroke] = stroke if stroke
          h[:stroke_width] = stroke_width if stroke_width
          h[:opacity] = opacity if opacity
          h[:interactive] = interactive if interactive
          h
        end
      end
    end
  end
end
