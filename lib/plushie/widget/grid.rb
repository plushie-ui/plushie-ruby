# frozen_string_literal: true

module Plushie
  module Widget
    # Grid layout: arranges children in a fixed-column grid.
    #
    # @example
    #   g = Plushie::Widget::Grid.new("items", columns: 3, spacing: 8)
    #     .push(Plushie::Widget::Text.new("a", "A"))
    #     .push(Plushie::Widget::Text.new("b", "B"))
    #   node = g.build
    #
    # Props:
    # - columns (integer): number of columns.
    # - spacing (number): spacing between cells in pixels.
    # - width (number): grid width in pixels.
    # - height (number): grid height in pixels.
    # - column_width (length): width of each column.
    # - row_height (length): height of each row.
    # - fluid (number): fluid mode max cell width in pixels.
    # - a11y (hash): accessibility overrides.
    class Grid < BuiltIn
      wire_type :grid
      children :many
      prop :columns, :spacing, :width, :height, :column_width,
        :row_height, :fluid, :a11y
    end
  end
end
