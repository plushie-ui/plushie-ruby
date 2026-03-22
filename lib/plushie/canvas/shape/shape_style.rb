# frozen_string_literal: true

module Plushie
  module Canvas
    module Shape
      # Style overrides for interactive canvas shape states (hover, pressed).
      #
      # @example
      #   ShapeStyle.new(fill: "#ff0000", opacity: 0.8)
      #   ShapeStyle.new(stroke: "#000", fill: "blue")
      ShapeStyle = ::Data.define(:fill, :stroke, :opacity) do
        def initialize(fill: nil, stroke: nil, opacity: nil)
          super
        end

        # Backward-compatible hash-style access.
        def [](key) = to_wire[key]

        # @return [Hash] wire-ready style map (nil fields stripped)
        def to_wire
          h = {}
          h[:fill] = fill if fill
          h[:stroke] = stroke if stroke
          h[:opacity] = opacity if opacity
          h
        end
      end
    end
  end
end
