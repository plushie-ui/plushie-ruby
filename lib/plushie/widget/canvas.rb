# frozen_string_literal: true

module Plushie
  module Widget
    # Typed builder for the canvas widget: vector drawing surface
    # (Layer 2 API).
    #
    # Canvas is a container widget. Its children are +__layer__+ nodes
    # (each mapping to an iced Cache for independent tessellation) or
    # direct shape nodes for simple cases.
    #
    # @example DSL usage
    #   canvas("drawing", width: 400, height: 300) do
    #     layer("bg") { canvas_rect(0, 0, 400, 300, fill: "#eee") }
    #     layer("fg") { canvas_circle(200, 150, 50, fill: "#f00") }
    #   end
    #
    # @example Builder API
    #   Canvas.new("drawing", width: 400, height: 300)
    #     .add_layer("bg", [Node.new(id: "r1", type: "rect", props: {x: 0, y: 0, w: 400, h: 300})])
    #     .build
    class Canvas < BuiltIn
      wire_type :canvas
      children :many
      prop :width, :height, :background,
        :on_press, :on_release, :on_move, :on_scroll,
        :interactive, :alt, :description,
        :role, :arrow_mode, :event_rate, :a11y

      # Add a named layer of shape nodes as children.
      #
      # @param name [String] layer name (used for cache keying)
      # @param shape_nodes [Array<Node>] shape child nodes
      # @return [Canvas] new Canvas with the layer appended
      def add_layer(name, shape_nodes)
        layer_node = Node.new(id: name, type: "__layer__", props: {name: name}, children: shape_nodes)
        push(layer_node)
      end
    end
  end
end
