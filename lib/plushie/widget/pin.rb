# frozen_string_literal: true

module Plushie
  module Widget
    # Pin layout: positions child at absolute coordinates.
    #
    # @example
    #   p = Plushie::Widget::Pin.new("badge", x: 100, y: 50)
    #     .push(Plushie::Widget::Text.new("label", "!"))
    #   node = p.build
    #
    # Props:
    # - x (number): x position in pixels.
    # - y (number): y position in pixels.
    # - width (length): pin container width.
    # - height (length): pin container height.
    Pin = Plushie::Widget.define(:pin) do
      children :single
      prop :x, :y, :width, :height
    end
  end
end
