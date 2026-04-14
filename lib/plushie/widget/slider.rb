# frozen_string_literal: true

module Plushie
  module Widget
    # Slider: horizontal range input.
    #
    # @example
    #   slider = Plushie::Widget::Slider.new("volume", [0, 100], 75, step: 5)
    #   node = slider.build
    #
    # Props:
    # - range (array): two-element [min, max] range.
    # - value (numeric): current slider value.
    # - step (numeric): value increment per step.
    # - shift_step (numeric): value increment when shift is held.
    # - default (numeric): default value on double-click.
    # - width (length): widget width.
    # - height (number): rail height in pixels.
    # - circular_handle (boolean): use a circular handle.
    # - rail_color (string): rail background colour.
    # - rail_width (number): rail thickness in pixels.
    # - style (symbol|hash): named style or style map.
    # - label (string): accessible label.
    # - event_rate (number): throttle rate for change events (ms).
    # - a11y (hash): accessibility overrides.
    class Slider < BuiltIn
      wire_type :slider
      default_a11y role: :slider, label_from: :label
      children :none
      positional :range
      positional :value
      prop :range, :value, :step, :shift_step, :default, :width, :height,
        :circular_handle, :handle_radius, :rail_color, :rail_width, :style,
        :label, :event_rate, :a11y
    end
  end
end
