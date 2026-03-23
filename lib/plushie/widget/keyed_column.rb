# frozen_string_literal: true

module Plushie
  module Widget
    # Keyed column layout -- vertical layout with stable identity keys.
    #
    # @example
    #   kc = Plushie::Widget::KeyedColumn.new("list", spacing: 4)
    #     .push(Plushie::Widget::Text.new("item1", "First"))
    #   node = kc.build
    #
    # Props:
    # - spacing (number) -- vertical space between children in pixels.
    # - padding (number|hash) -- padding inside the column.
    # - width (length) -- column width.
    # - height (length) -- column height.
    # - max_width (number) -- maximum width in pixels.
    # - a11y (hash) -- accessibility overrides.
    class KeyedColumn
      # Supported property keys for this widget.
      # @api private
      PROPS = %i[spacing padding width height max_width a11y].freeze

      # @!parse
      #   attr_reader :id, :children, :spacing, :padding, :width, :height, :max_width, :a11y
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
      # @return [KeyedColumn] new instance with the child appended
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
        Node.new(id: @id, type: "keyed_column", props: props,
          children: Build.children_to_nodes(@children))
      end
    end
  end
end
