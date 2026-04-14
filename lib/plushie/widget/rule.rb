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
    Rule = Plushie::Widget.define(:rule) do
      children :none
      prop :height, :width, :direction, :style
    end
  end
end
