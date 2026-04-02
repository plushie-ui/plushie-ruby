# frozen_string_literal: true

module Plushie
  module Widget
    # Empty space -- invisible spacer widget.
    #
    # @example
    #   sp = Plushie::Widget::Space.new("gap", width: 20, height: 10)
    #   node = sp.build
    #
    # Props:
    # - width (length) -- space width.
    # - height (length) -- space height.
    # - a11y (hash) -- accessibility overrides.
    class Space < BuiltIn
      wire_type :space
      children :none
      prop :width, :height, :a11y
    end
  end
end
