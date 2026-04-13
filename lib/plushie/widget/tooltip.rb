# frozen_string_literal: true

module Plushie
  module Widget
    # Tooltip: shows a popup tip over child content on hover.
    #
    # @example
    #   tt = Plushie::Widget::Tooltip.new("help", "Click for help", position: :top)
    #     .push(Plushie::Widget::Button.new("btn", "?"))
    #   node = tt.build
    #
    # Props:
    # - tip (string): tooltip text.
    # - position (symbol): :top, :bottom, :left, :right, :follow_cursor.
    # - gap (number): gap between tooltip and content in pixels.
    # - padding (number): tooltip padding in pixels.
    # - snap_within_viewport (boolean): keep tooltip in viewport.
    # - delay (integer): delay in ms before showing.
    # - style (symbol|hash): named style or style map.
    # - a11y (hash): accessibility overrides.
    class Tooltip < BuiltIn
      wire_type :tooltip
      children :single
      positional :tip, default: nil
      prop :tip, :position, :gap, :padding, :snap_within_viewport, :delay,
        :style, :a11y
    end
  end
end
