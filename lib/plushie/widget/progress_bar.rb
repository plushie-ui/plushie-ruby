# frozen_string_literal: true

module Plushie
  module Widget
    # Progress bar -- displays progress within a range.
    #
    # @example
    #   pb = Plushie::Widget::ProgressBar.new("upload", [0, 100], 42,
    #     style: :primary)
    #   node = pb.build
    #
    # Props:
    # - range (array) -- [min, max] range.
    # - value (number) -- current progress value.
    # - width (length) -- bar width.
    # - height (length) -- bar height.
    # - style (symbol|hash) -- :primary, :secondary, :success, :danger, :warning, or style map.
    # - vertical (boolean) -- render vertically.
    # - label (string) -- accessible label.
    # - a11y (hash) -- accessibility overrides.
    class ProgressBar < BuiltIn
      wire_type :progress_bar
      children :none
      positional :range
      positional :value
      prop :range, :value, :width, :height, :style, :vertical, :label, :a11y
    end
  end
end
