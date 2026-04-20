# frozen_string_literal: true

module Plushie
  module Widget
    # Floating overlay: positions child with translation and scaling.
    #
    # @example
    #   f = Plushie::Widget::Floating.new("popup", translate_x: 10, translate_y: 20)
    #     .push(Plushie::Widget::Text.new("msg", "Hello"))
    #   node = f.build
    #
    # Props:
    # - translate_x (number): horizontal translation in pixels.
    # - translate_y (number): vertical translation in pixels.
    # - scale (number): scale factor.
    # - width (length): float width.
    # - height (length): float height.
    Floating = Plushie::Widget.define(:float) do
      children :single
      prop :translate_x, :translate_y, :scale, :width, :height
      prop :a11y, :event_rate
    end
  end
end
