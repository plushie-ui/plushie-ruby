# frozen_string_literal: true

module Plushie
  module Canvas
    module Shape
      # Clipping rectangle value type for canvas groups.
      #
      # @example
      #   Clip.new(x: 10, y: 10, w: 100, h: 80)
      Clip = ::Data.define(:x, :y, :w, :h) do
        def initialize(x:, y:, w:, h:)
          super
        end

        # @return [Hash] wire-ready clip map
        def to_wire
          {type: "clip", x: x, y: y, w: w, h: h}
        end
      end
    end
  end
end
