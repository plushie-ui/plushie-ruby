# frozen_string_literal: true

module Plushie
  module Canvas
    module Shape
      # Interactive shape descriptor for canvas hit testing and event handling.
      #
      # @example
      #   Interactive.new(id: "btn", on_click: true, cursor: "pointer")
      #   Interactive.new(id: "drag", draggable: true, drag_axis: "x",
      #     drag_bounds: DragBounds.new(min_x: 0, max_x: 400))
      Interactive = ::Data.define(
        :id, :on_click, :on_hover, :draggable, :drag_axis, :drag_bounds,
        :cursor, :hover_style, :pressed_style, :tooltip, :a11y, :hit_rect
      ) do
        def initialize(
          id:, on_click: nil, on_hover: nil, draggable: nil,
          drag_axis: nil, drag_bounds: nil, cursor: nil,
          hover_style: nil, pressed_style: nil, tooltip: nil,
          a11y: nil, hit_rect: nil
        )
          super
        end

        # Backward-compatible hash-style access.
        def [](key) = to_wire[key]

        # @return [Hash] wire-ready interactive map (nil fields stripped)
        def to_wire
          h = {id: id}
          h[:on_click] = on_click unless on_click.nil?
          h[:on_hover] = on_hover unless on_hover.nil?
          h[:draggable] = draggable unless draggable.nil?
          h[:drag_axis] = drag_axis if drag_axis
          h[:drag_bounds] = drag_bounds.respond_to?(:to_wire) ? drag_bounds.to_wire : drag_bounds if drag_bounds
          h[:cursor] = cursor if cursor
          h[:hover_style] = hover_style.respond_to?(:to_wire) ? hover_style.to_wire : hover_style if hover_style
          h[:pressed_style] = pressed_style.respond_to?(:to_wire) ? pressed_style.to_wire : pressed_style if pressed_style
          h[:tooltip] = tooltip if tooltip
          h[:a11y] = a11y if a11y
          h[:hit_rect] = hit_rect.respond_to?(:to_wire) ? hit_rect.to_wire : hit_rect if hit_rect
          h
        end
      end
    end
  end
end
