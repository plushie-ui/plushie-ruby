# frozen_string_literal: true

module Plushie
  module Widget
    # Scrollable: scrollable container for overflow content.
    #
    # @example
    #   scrollable = Plushie::Widget::Scrollable.new("log",
    #     width: { fill: true }, height: 300, direction: :vertical)
    #   node = scrollable.push(some_child).build
    #
    # Props:
    # - width (length): viewport width.
    # - height (length): viewport height.
    # - direction (symbol): :vertical, :horizontal, or :both.
    # - spacing (number): spacing between children in pixels.
    # - scrollbar_width (number): scrollbar track width.
    # - scrollbar_margin (number): margin around scrollbar.
    # - scroller_width (number): scroller thumb width.
    # - anchor (symbol): scroll anchor: :start or :end.
    # - on_scroll (boolean): emit scroll events.
    # - auto_scroll (boolean): auto-scroll to end on content change.
    # - scrollbar_color (string): scrollbar track colour.
    # - scroller_color (string): scroller thumb colour.
    # - a11y (hash): accessibility overrides.
    class Scrollable < BuiltIn
      wire_type :scrollable
      default_a11y role: :scroll_view
      children :single
      prop :width, :height, :direction, :spacing, :scrollbar_width,
        :scrollbar_margin, :scroller_width, :anchor, :on_scroll,
        :auto_scroll, :scrollbar_color, :scroller_color, :a11y
    end
  end
end
