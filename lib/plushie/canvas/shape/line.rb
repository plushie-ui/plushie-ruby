# frozen_string_literal: true

module Plushie
  module Canvas
    module Shape
      Line = ::Data.define(:x1, :y1, :x2, :y2, :stroke, :stroke_width, :opacity, :interactive) do
        def initialize(x1:, y1:, x2:, y2:, stroke: nil, stroke_width: nil, opacity: nil, interactive: nil)
          super
        end

        def [](key) = to_wire[key]

        def to_wire
          h = {type: "line", x1: x1, y1: y1, x2: x2, y2: y2}
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
