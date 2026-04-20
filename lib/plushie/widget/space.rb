# frozen_string_literal: true

module Plushie
  module Widget
    # Empty space: invisible spacer widget.
    #
    # @example
    #   sp = Plushie::Widget::Space.new("gap", width: 20, height: 10)
    #   node = sp.build
    #
    # Props:
    # - width (length): space width.
    # - height (length): space height.
    Space = Plushie::Widget.define(:space) do
      children :none
      prop :width, :height
      prop :a11y, :event_rate
    end
  end
end
