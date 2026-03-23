# frozen_string_literal: true

module Plushie
  module Widget
    # Responsive layout -- adapts to available size via resize events.
    #
    # @example
    #   r = Plushie::Widget::Responsive.new("layout", width: :fill, height: :fill)
    #     .push(Plushie::Widget::Text.new("content", "Responsive content"))
    #   node = r.build
    #
    # Props:
    # - width (length) -- container width.
    # - height (length) -- container height.
    # - a11y (hash) -- accessibility overrides.
    class Responsive
      # Supported property keys for this widget.
      # @api private
      PROPS = %i[width height a11y].freeze

      # @!parse
      #   attr_reader :id, :children, :width, :height, :a11y
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
      # @return [Responsive] new instance with the child appended
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
        Node.new(id: @id, type: "responsive", props: props,
          children: Build.children_to_nodes(@children))
      end
    end
  end
end
