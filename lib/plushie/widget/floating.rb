# frozen_string_literal: true

module Plushie
  module Widget
    # Floating overlay -- positions child with translation and scaling.
    #
    # @example
    #   f = Plushie::Widget::Floating.new("popup", translate_x: 10, translate_y: 20)
    #     .push(Plushie::Widget::Text.new("msg", "Hello"))
    #   node = f.build
    #
    # Props:
    # - translate_x (number) -- horizontal translation in pixels.
    # - translate_y (number) -- vertical translation in pixels.
    # - scale (number) -- scale factor.
    # - width (length) -- float width.
    # - height (length) -- float height.
    # - a11y (hash) -- accessibility overrides.
    class Floating
      PROPS = %i[translate_x translate_y scale width height a11y].freeze

      attr_reader :id, :children, *PROPS

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
      # @return [Floating] new instance with the child appended
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
        Node.new(id: @id, type: "float", props: props,
          children: Build.children_to_nodes(@children))
      end
    end
  end
end
