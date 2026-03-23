# frozen_string_literal: true

module Plushie
  module Widget
    # Typed builder for the canvas widget -- vector drawing surface
    # (Layer 2 API).
    #
    # Canvas supports layer-based composition: each layer is a named
    # collection of shapes. Use {#add_layer} to append layers, or
    # set flat +shapes+ for simple cases.
    #
    # PROPS: layers, shapes, width, height, background,
    # on_press, on_release, on_move, on_scroll, alt, description,
    # role, arrow_mode, event_rate, a11y.
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
    class Canvas
      # Supported property keys for the canvas widget.
      PROPS = %i[layers shapes width height background
        on_press on_release on_move on_scroll alt description
        role arrow_mode event_rate a11y].freeze

      # @!parse
      #   attr_reader :id, :layers, :shapes, :width, :height, :background, :on_press, :on_release, :on_move, :on_scroll, :alt, :description, :role, :arrow_mode, :event_rate, :a11y
      class_eval { attr_reader :id, *PROPS }

      # @param id [String] widget identifier
      # @param opts [Hash] optional properties matching PROPS keys
      def initialize(id, **opts)
        @id = id.to_s
        PROPS.each { |k| instance_variable_set(:"@#{k}", opts[k]) if opts.key?(k) }
      end

      PROPS.each do |prop|
        define_method(:"set_#{prop}") do |value|
          dup.tap { _1.instance_variable_set(:"@#{prop}", value) }
        end
      end

      # Add a named layer of shapes. Returns a new Canvas with the
      # layer merged into the existing layers hash.
      #
      # @param name [String] layer name (ordering follows insertion)
      # @param shapes [Array<Hash>] shape definitions for this layer
      # @return [Canvas] new instance with the layer added
      def add_layer(name, shapes)
        current = @layers || {}
        dup.tap { _1.instance_variable_set(:@layers, current.merge(name => shapes)) }
      end

      # Build a {Plushie::Node} from the current property values.
      #
      # @return [Plushie::Node]
      def build
        props = {}
        PROPS.each do |key|
          val = instance_variable_get(:"@#{key}")
          Build.put_if(props, key, val)
        end
        Node.new(id: @id, type: "canvas", props: props)
      end
    end
  end
end
