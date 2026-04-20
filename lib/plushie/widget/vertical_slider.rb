# frozen_string_literal: true

module Plushie
  module Widget
    # Vertical slider: vertical range input.
    #
    # @example
    #   vs = Plushie::Widget::VerticalSlider.new("vol", [0, 100], 50, step: 5)
    #   node = vs.build
    #
    # Props:
    # - range (array): [min, max] range.
    # - value (number): current slider value.
    # - step (number): step increment.
    # - shift_step (number): step when Shift is held.
    # - default (number): double-click reset value.
    # - width (length): slider width.
    # - height (length): slider height.
    # - rail_color (string): rail color.
    # - rail_width (number): rail thickness in pixels.
    # - style (symbol|hash): named style or style map.
    # - label (string): accessible label.
    VerticalSlider = Plushie::Widget.define(:vertical_slider) do
      children :none
      positional :range
      positional :value
      prop :range, :value, :step, :shift_step, :default, :width, :height,
        :rail_color, :rail_width, :style, :label
      prop :a11y, :event_rate
      default_a11y role: :slider, label_from: :label
    end
  end
end
