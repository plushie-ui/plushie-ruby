# frozen_string_literal: true

module Plushie
  module Canvas
    module Shape
      Rect = ::Data.define(:x, :y, :w, :h, :fill, :stroke, :stroke_width, :opacity, :interactive) do
        def initialize(x:, y:, w:, h:, fill: nil, stroke: nil, stroke_width: nil, opacity: nil, interactive: nil)
          super
        end

        # Backward-compatible hash-style access.
        def [](key) = to_wire[key]

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
