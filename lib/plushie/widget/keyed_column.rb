# frozen_string_literal: true

module Plushie
  module Widget
    # Keyed column layout -- vertical layout with stable identity keys.
    #
    # @example
    #   kc = Plushie::Widget::KeyedColumn.new("list", spacing: 4)
    #     .push(Plushie::Widget::Text.new("item1", "First"))
    #   node = kc.build
    #
    # Props:
    # - spacing (number) -- vertical space between children in pixels.
    # - padding (number|hash) -- padding inside the column.
    # - width (length) -- column width.
    # - height (length) -- column height.
    # - max_width (number) -- maximum width in pixels.
    # - a11y (hash) -- accessibility overrides.
    class KeyedColumn < BuiltIn
      wire_type :keyed_column
      children :many
      prop :spacing, :padding, :width, :height, :max_width, :a11y
    end
  end
end
