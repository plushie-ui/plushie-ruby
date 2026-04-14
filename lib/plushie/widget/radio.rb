# frozen_string_literal: true

module Plushie
  module Widget
    # Radio button: one-of-many selection.
    #
    # @example
    #   r = Plushie::Widget::Radio.new("opt_a", "a", "a",
    #     label: "Option A", group: "choices")
    #   node = r.build
    #
    # Props:
    # - value (string): the value this radio represents.
    # - selected (string|nil): currently selected value in the group.
    # - label (string): label text (defaults to value).
    # - group (string): group identifier.
    # - spacing (number): space between radio and label in pixels.
    # - width (length): widget width.
    # - size (number): radio button size in pixels.
    # - text_size (number): label text size in pixels.
    # - font (string|hash): label font.
    # - line_height (number|hash): label line height.
    # - shaping (symbol): text shaping strategy.
    # - wrapping (symbol): text wrapping mode.
    # - style (symbol|hash): named style or style map.
    # - a11y (hash): accessibility overrides.
    class Radio < BuiltIn
      wire_type :radio
      default_a11y role: :radio_button, label_from: :label
      children :none
      positional :value
      positional :selected
      prop :value, :selected, :label, :group, :spacing, :width, :size,
        :text_size, :font, :line_height, :shaping, :wrapping, :style, :a11y
    end
  end
end
