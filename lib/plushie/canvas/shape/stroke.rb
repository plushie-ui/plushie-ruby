# frozen_string_literal: true

module Plushie
  module Canvas
    module Shape
      # Canvas stroke descriptor with color, width, and optional cap/join/dash.
      #
      # @example
      #   Stroke.new(color: "#000", width: 2)
      #   Stroke.new(color: "#000", width: 2, cap: "round", join: "miter")
      #   Stroke.new(color: "#000", width: 1, dash: Dash.new(segments: [4, 2], offset: 0))
      Stroke = ::Data.define(:color, :width, :cap, :join, :dash) do
        def initialize(color:, width:, cap: nil, join: nil, dash: nil)
          super
        end

        # Backward-compatible hash-style access.
        def [](key) = to_wire[key]

        # @return [Hash] wire-ready stroke map
        def to_wire
          h = {color: color, width: width}
          h[:cap] = cap if cap
          h[:join] = join if join
          h[:dash] = dash.respond_to?(:to_wire) ? dash.to_wire : dash if dash
          h
        end
      end
    end
  end
end
