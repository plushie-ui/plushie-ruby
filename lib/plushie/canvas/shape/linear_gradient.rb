# frozen_string_literal: true

module Plushie
  module Canvas
    module Shape
      # Linear gradient descriptor usable as a canvas fill value.
      #
      # @example
      #   LinearGradient.new(from: [0, 0], to: [200, 0],
      #     stops: [[0.0, "#ff0000"], [1.0, "#0000ff"]])
      LinearGradient = ::Data.define(:from, :to, :stops) do
        def initialize(from:, to:, stops:)
          super
        end

        # Backward-compatible hash-style access.
        def [](key) = to_wire[key]

        # @return [Hash] wire-ready gradient map
        def to_wire
          {type: "linear", start: from, end: to, stops: stops}
        end
      end
    end
  end
end
