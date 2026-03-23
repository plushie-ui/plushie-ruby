# frozen_string_literal: true

module Plushie
  module Canvas
    module Shape
      # Canvas SVG shape with position and size.
      #
      # @example
      #   CanvasSvg.new(source: "icon.svg", x: 10, y: 20, w: 32, h: 32)
      CanvasSvg = ::Data.define(:source, :x, :y, :w, :h) do
        def initialize(source:, x:, y:, w:, h:)
          super
        end

        # Backward-compatible hash-style access.
        def [](key) = to_wire[key]

        # @return [Hash] wire-ready shape map
        def to_wire
          {type: "svg", source: source, x: x, y: y, w: w, h: h}
        end
      end
    end
  end
end
