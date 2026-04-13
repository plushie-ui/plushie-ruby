# frozen_string_literal: true

module Plushie
  module Widget
    # Responsive layout: adapts to available size via resize events.
    #
    # @example
    #   r = Plushie::Widget::Responsive.new("layout", width: :fill, height: :fill)
    #     .push(Plushie::Widget::Text.new("content", "Responsive content"))
    #   node = r.build
    #
    # Props:
    # - width (length): container width.
    # - height (length): container height.
    # - a11y (hash): accessibility overrides.
    class Responsive < BuiltIn
      wire_type :responsive
      children :single
      prop :width, :height, :a11y
    end
  end
end
