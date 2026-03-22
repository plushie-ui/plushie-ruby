# frozen_string_literal: true

module Plushie
  module Canvas
    module Shape
      # Group of shapes with translation offset.
      #
      # Children are drawn in local coordinates relative to the group's
      # x/y origin. Groups can carry interactive properties for composite
      # hit testing.
      Group = ::Data.define(:shapes, :x, :y, :transform, :clip, :opacity, :interactive) do
        def initialize(shapes:, x: 0, y: 0, transform: nil, clip: nil, opacity: nil, interactive: nil)
          super
        end

        def [](key) = to_wire[key]

        # @return [Hash] wire-ready shape map
        def to_wire
          h = {type: "group", x: x, y: y}
          h[:shapes] = shapes.map { |s| s.respond_to?(:to_wire) ? s.to_wire : s }
          h[:transform] = transform if transform
          h[:clip] = clip if clip
          h[:opacity] = opacity if opacity
          h[:interactive] = interactive if interactive
          h
        end
      end
    end
  end
end
