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
    # - direction (symbol): :horizontal or :vertical.
    # - style (symbol|hash): :default, :weak, or style map.
    # - a11y (hash): accessibility overrides.
    class Rule < BuiltIn
      wire_type :rule
      children :none
      prop :height, :width, :direction, :style, :a11y
    end
  end
end
