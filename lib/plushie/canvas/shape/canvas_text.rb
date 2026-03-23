# frozen_string_literal: true

module Plushie
  module Canvas
    module Shape
      # Text drawn on a canvas.
      CanvasText = ::Data.define(:x, :y, :content, :fill, :size, :font, :opacity, :interactive) do
        def initialize(x:, y:, content:, fill: nil, size: nil, font: nil, opacity: nil, interactive: nil)
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
          h = {type: "text", x: x, y: y, content: content}
          h[:fill] = fill if fill
          h[:size] = size if size
          h[:font] = font if font
          h[:opacity] = opacity if opacity
          h[:interactive] = interactive if interactive
          h
        end
      end
    end
  end
end
