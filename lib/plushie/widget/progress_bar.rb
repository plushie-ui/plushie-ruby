# frozen_string_literal: true

module Plushie
  module Widget
    # Progress bar: displays progress within a range.
    #
    # @example
    #   pb = Plushie::Widget::ProgressBar.new("upload", [0, 100], 42,
    #     style: :primary)
    #   node = pb.build
    #
    # Props:
    # - range (array): [min, max] range.
    # - value (number): current progress value.
    # - width (length): bar width.
    # - height (length): bar height.
    # - style (symbol|hash): :primary, :secondary, :success, :danger, :warning, or style map.
    # - vertical (boolean): render vertically.
    # - label (string): accessible label.
    ProgressBar = Plushie::Widget.define(:progress_bar) do
      children :none
      positional :range
      positional :value
      prop :range, :value, :width, :height, :style, :vertical, :label
      default_a11y role: :progress_indicator, label_from: :label
    end
  end
end
