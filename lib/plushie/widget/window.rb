# frozen_string_literal: true

module Plushie
  module Widget
    # Typed builder for the window widget (Layer 2 API).
    #
    # Construct a Window, set properties via fluent +set_*+ methods,
    # then call {#build} to produce a {Plushie::Node} for the view tree.
    class Window
      # Supported property keys for this widget.
      # @api private
      PROPS = %i[title size width height position min_size max_size
        maximized fullscreen visible resizable closeable minimizable
        decorations transparent blur level exit_on_close_request].freeze

      # @!parse
      #   attr_reader :id, :children, :title, :size, :width, :height, :position, :min_size, :max_size, :maximized, :fullscreen, :visible, :resizable, :closeable, :minimizable, :decorations, :transparent, :blur, :level, :exit_on_close_request
      class_eval { attr_reader :id, :children, *PROPS }

      def initialize(id, **opts)
        @id = id.to_s
        @children = opts.delete(:children) || []
        PROPS.each { |k| instance_variable_set(:"@#{k}", opts[k]) if opts.key?(k) }
      end

      PROPS.each do |prop|
        define_method(:"set_#{prop}") do |value|
          dup.tap { _1.instance_variable_set(:"@#{prop}", value) }
        end
      end

      # Return a copy with the given child appended.
      #
      # @param child [Object] a widget builder or Node to append
      # @return [self]
      def push(child)
        dup.tap { _1.instance_variable_set(:@children, @children + [child]) }
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
        Node.new(id: @id, type: "window", props: props,
          children: Build.children_to_nodes(@children))
      end
    end
  end
end
