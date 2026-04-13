# frozen_string_literal: true

module Plushie
  module Widget
    # Typed builder for the canvas widget: vector drawing surface
    # (Layer 2 API).
    #
    # Canvas supports layer-based composition: each layer is a named
    # collection of shapes. Use {#add_layer} to append layers, or
    # set flat +shapes+ for simple cases.
    #
    # @example Layer-based usage
    #   Canvas.new("drawing", width: 400, height: 300)
    #     .add_layer("bg", [{ type: "rect", x: 0, y: 0, w: 400, h: 300, fill: "#eee" }])
    #     .add_layer("fg", [{ type: "circle", cx: 200, cy: 150, r: 50, fill: "#f00" }])
    #     .build
    #
    # @example Flat shapes (no layers)
    #   Canvas.new("icon", width: 24, height: 24,
    #     shapes: [{ type: "line", x1: 0, y1: 0, x2: 24, y2: 24 }])
    #     .build
    class Canvas < BuiltIn
      wire_type :canvas
      children :none
      prop :layers, :shapes, :width, :height, :background,
        :on_press, :on_release, :on_move, :on_scroll, :alt, :description,
        :role, :arrow_mode, :event_rate, :a11y

      # Add a named layer of shapes.
      def add_layer(name, shapes)
        current = @layers || {}
        dup.tap { |copy| copy.instance_variable_set(:@layers, current.merge(name => shapes)) }
      end
    end
  end
end
