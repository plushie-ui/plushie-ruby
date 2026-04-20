# frozen_string_literal: true

module Plushie
  module Widget
    # Horizontal or vertical rule (divider line).
    #
    # @example
    #   r = Plushie::Widget::Rule.new("divider", direction: :horizontal, height: 2)
    #   node = r.build
    #
    # Props:
    # - height (number): line thickness for horizontal rules.
    # - width (number): line thickness for vertical rules.
    # - thickness (number): direction-agnostic line thickness (fallback
    #   when the direction-specific width/height isn't set).
    # - direction (symbol): :horizontal or :vertical.
    # - style (symbol|hash): :default, :weak, or style map.
    Rule = Plushie::Widget.define(:rule) do
      children :none
      prop :height, :width, :thickness, :direction, :style
      prop :a11y, :event_rate
    end
  end
end
