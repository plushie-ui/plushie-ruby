# frozen_string_literal: true

module Plushie
  module Widget
    # Toggler: on/off switch.
    #
    # @example
    #   toggler = Plushie::Widget::Toggler.new("dark_mode", true, label: "Dark mode")
    #   node = toggler.build
    #
    # Props:
    # - is_toggled (boolean): whether the toggler is on.
    # - label (string): text label next to the toggler.
    # - spacing (number): space between toggler and label in pixels.
    # - width (length): widget width.
    # - size (number): toggler size in pixels.
    # - text_size (number): label text size in pixels.
    # - font (string|map): label font.
    # - line_height (number|map): label line height.
    # - shaping (symbol): text shaping: :basic, :advanced, :auto.
    # - wrapping (symbol): text wrapping: :none, :word, :glyph, :word_or_glyph.
    # - text_alignment (symbol): horizontal label alignment: :left, :center, :right.
    # - style (symbol): named style.
    # - disabled (boolean): whether the toggler is disabled.
    # - a11y (hash): accessibility overrides.
    class Toggler < BuiltIn
      wire_type :toggler
      default_a11y role: :switch, label_from: :label
      children :none
      positional :is_toggled, default: false
      prop :is_toggled, :label, :spacing, :width, :size, :text_size, :font,
        :line_height, :shaping, :wrapping, :text_alignment, :style,
        :disabled, :a11y
    end
  end
end
