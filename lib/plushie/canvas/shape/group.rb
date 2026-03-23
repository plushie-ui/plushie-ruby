# frozen_string_literal: true

module Plushie
  module Canvas
    module Shape
      # Group of shapes with transforms, clipping, and interactive properties.
      #
      # Children are drawn relative to any applied transforms. Interactive
      # fields (previously nested under an Interactive struct) live at the
      # top level of the group.
      Group = ::Data.define(
        :children, :transforms, :clip, :opacity,
        :id, :on_click, :on_hover, :draggable, :drag_axis, :drag_bounds,
        :cursor, :hit_rect, :tooltip, :hover_style, :pressed_style,
        :focus_style, :show_focus_ring, :focusable, :a11y
      ) do
        def initialize(
          children:, transforms: nil, clip: nil, opacity: nil,
          id: nil, on_click: nil, on_hover: nil, draggable: nil,
          drag_axis: nil, drag_bounds: nil, cursor: nil, hit_rect: nil,
          tooltip: nil, hover_style: nil, pressed_style: nil,
          focus_style: nil, show_focus_ring: nil, focusable: nil, a11y: nil
        )
          super
        end

        # Access shape properties by key.
        #
        # @param key [Symbol]
        # @return [Object]
        def [](key) = to_wire[key]

        # Encode shape for the wire protocol.
        # @api private
        def to_wire
          h = {type: "group"}
          h[:children] = children.map { |s| s.respond_to?(:to_wire) ? s.to_wire : s }
          if transforms
            h[:transforms] = transforms.map { |t| t.respond_to?(:to_wire) ? t.to_wire : t }
          end
          h[:clip] = clip.respond_to?(:to_wire) ? clip.to_wire : clip if clip
          h[:opacity] = opacity if opacity
          h[:id] = id if id
          h[:on_click] = on_click unless on_click.nil?
          h[:on_hover] = on_hover unless on_hover.nil?
          h[:draggable] = draggable unless draggable.nil?
          h[:drag_axis] = drag_axis if drag_axis
          h[:drag_bounds] = drag_bounds.respond_to?(:to_wire) ? drag_bounds.to_wire : drag_bounds if drag_bounds
          h[:cursor] = cursor if cursor
          h[:hit_rect] = hit_rect.respond_to?(:to_wire) ? hit_rect.to_wire : hit_rect if hit_rect
          h[:tooltip] = tooltip if tooltip
          h[:hover_style] = hover_style.respond_to?(:to_wire) ? hover_style.to_wire : hover_style if hover_style
          h[:pressed_style] = pressed_style.respond_to?(:to_wire) ? pressed_style.to_wire : pressed_style if pressed_style
          h[:focus_style] = focus_style.respond_to?(:to_wire) ? focus_style.to_wire : focus_style if focus_style
          h[:show_focus_ring] = show_focus_ring unless show_focus_ring.nil?
          h[:focusable] = focusable unless focusable.nil?
          h[:a11y] = a11y if a11y
          h
        end
      end
    end
  end
end
