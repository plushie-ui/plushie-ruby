# frozen_string_literal: true

module Plushie
  module Widget
    # Overlay container: positions second child as a floating overlay
    # relative to the first child (anchor).
    #
    # @example
    #   o = Plushie::Widget::Overlay.new("menu", position: :below, gap: 4)
    #     .push(Plushie::Widget::Button.new("trigger", "Open"))
    #     .push(Plushie::Widget::Text.new("content", "Menu items"))
    #   node = o.build
    #
    # Props:
    # - position (symbol): :below, :above, :left, :right.
    # - gap (number): space between anchor and overlay in pixels.
    # - offset_x (number): horizontal offset in pixels.
    # - offset_y (number): vertical offset in pixels.
    # - flip (boolean): auto-flip on viewport overflow.
    # - align (symbol): cross-axis alignment: :start, :center, :end.
    # - width (length): overlay node width.
    # - a11y (hash): accessibility overrides.
    class Overlay < BuiltIn
      wire_type :overlay
      children 2
      prop :position, :gap, :offset_x, :offset_y, :flip, :align, :width, :a11y
    end
  end
end
