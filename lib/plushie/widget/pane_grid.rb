# frozen_string_literal: true

module Plushie
  module Widget
    # Pane grid -- resizable tiled panes.
    #
    # @example
    #   pg = Plushie::Widget::PaneGrid.new("editor", spacing: 4)
    #     .push(Plushie::Widget::Text.new("left", "Left pane"))
    #     .push(Plushie::Widget::Text.new("right", "Right pane"))
    #   node = pg.build
    #
    # Props:
    # - panes (array of strings) -- pane identifiers.
    # - spacing (number) -- space between panes in pixels.
    # - width (length) -- grid width.
    # - height (length) -- grid height.
    # - min_size (number) -- minimum pane size in pixels.
    # - divider_color (string) -- divider color.
    # - divider_width (number) -- divider thickness in pixels.
    # - leeway (number) -- grabbable area around dividers.
    # - event_rate (integer) -- max events per second.
    # - a11y (hash) -- accessibility overrides.
    class PaneGrid < BuiltIn
      wire_type :pane_grid
      children :many
      prop :panes, :spacing, :width, :height, :min_size, :divider_color,
        :divider_width, :leeway, :event_rate, :a11y
    end
  end
end
