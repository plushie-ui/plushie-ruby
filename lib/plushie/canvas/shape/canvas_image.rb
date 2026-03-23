# frozen_string_literal: true

module Plushie
  module Canvas
    module Shape
      # Canvas raster image shape with position, size, and optional rotation.
      #
      # @example
      #   CanvasImage.new(source: "icon.png", x: 10, y: 20, w: 64, h: 64)
      #   CanvasImage.new(source: "photo.jpg", x: 0, y: 0, w: 200, h: 150, rotation: 0.5)
      CanvasImage = ::Data.define(:source, :x, :y, :w, :h, :rotation, :opacity) do
        def initialize(source:, x:, y:, w:, h:, rotation: nil, opacity: nil)
          super
        end

        # Backward-compatible hash-style access.
        def [](key) = to_wire[key]

        # @return [Hash] wire-ready shape map
        def to_wire
          h = {type: "image", source: source, x: x, y: y, w: w, h: self.h}
          h[:rotation] = rotation if rotation
          h[:opacity] = opacity if opacity
          h
        end
      end
    end
  end
end
