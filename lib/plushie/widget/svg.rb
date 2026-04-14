# frozen_string_literal: true

module Plushie
  module Widget
    # SVG display: renders a vector image from a file path.
    #
    # @example
    #   svg = Plushie::Widget::Svg.new("logo", "logo.svg",
    #     width: 64, height: 64)
    #   node = svg.build
    #
    # Props:
    # - source (string): path to the SVG file.
    # - width (length): SVG width.
    # - height (length): SVG height.
    # - content_fit (symbol): how the SVG fits its bounds.
    # - rotation (number): rotation angle in degrees.
    # - opacity (number): opacity 0.0-1.0.
    # - color (string): color tint applied to the SVG.
    # - alt (string): accessible label.
    # - description (string): extended accessible description.
    # - decorative (boolean): hide from assistive technology.
    # - a11y (hash): accessibility overrides.
    class Svg < BuiltIn
      wire_type :svg
      default_a11y role: :image
      children :none
      positional :source, default: nil
      prop :source, :width, :height, :content_fit, :rotation, :opacity,
        :color, :alt, :description, :decorative, :a11y
    end
  end
end
