# frozen_string_literal: true

module Plushie
  module Canvas
    module Shape
      # Path shape built from segments.
      Path = ::Data.define(:commands, :fill, :stroke, :stroke_width, :opacity, :interactive) do
        def initialize(commands:, fill: nil, stroke: nil, stroke_width: nil, opacity: nil, interactive: nil)
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
          h = {type: "path", commands: commands}
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
