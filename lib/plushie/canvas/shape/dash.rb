# frozen_string_literal: true

module Plushie
  module Canvas
    module Shape
      # Dash pattern for canvas shape strokes.
      #
      # @example
      #   Dash.new(segments: [4, 2], offset: 0)
      #   Dash.new(segments: [10, 5, 2, 5], offset: 3)
      Dash = ::Data.define(:segments, :offset) do
        def initialize(segments:, offset:)
          super
        end

        # Backward-compatible hash-style access.
        def [](key) = to_wire[key]

        # @return [Hash] wire-ready dash map
        def to_wire
          {segments: segments, offset: offset}
        end
      end
    end
  end
end
