# frozen_string_literal: true

module Plushie
  module Widget
    # Stack layout -- layers children on top of each other.
    #
    # @example
    #   s = Plushie::Widget::Stack.new("layers", width: :fill, clip: true)
    #     .push(Plushie::Widget::Text.new("bg", "Background"))
    #     .push(Plushie::Widget::Text.new("fg", "Foreground"))
    #   node = s.build
    #
    # Props:
    # - width (length) -- stack width.
    # - height (length) -- stack height.
    # - clip (boolean) -- clip overflowing children.
    # - a11y (hash) -- accessibility overrides.
    class Stack
      # Supported property keys for this widget.
      # @api private
      PROPS = %i[width height clip a11y].freeze

      # @!parse
      #   attr_reader :id, :children, :width, :height, :clip, :a11y
      class_eval { attr_reader :id, :children, *PROPS }

      # @param id [String] widget identifier
      # @param opts [Hash] optional properties
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

      # Append a child widget.
      # @param child [Plushie::Node, #build] child widget
      # @return [Stack] new instance with the child appended
      def push(child)
        dup.tap { _1.instance_variable_set(:@children, @children + [child]) }
      end

      # @return [Plushie::Node]
      def build
        props = {}
        PROPS.each do |key|
          val = instance_variable_get(:"@#{key}")
          Build.put_if(props, key, val)
        end
        Node.new(id: @id, type: "stack", props: props,
          children: Build.children_to_nodes(@children))
      end
    end
  end
end
