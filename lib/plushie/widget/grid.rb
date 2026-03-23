# frozen_string_literal: true

module Plushie
  module Widget
    # Grid layout -- arranges children in a fixed-column grid.
    #
    # @example
    #   g = Plushie::Widget::Grid.new("items", columns: 3, spacing: 8)
    #     .push(Plushie::Widget::Text.new("a", "A"))
    #     .push(Plushie::Widget::Text.new("b", "B"))
    #   node = g.build
    #
    # Props:
    # - columns (integer) -- number of columns.
    # - column_count (integer) -- alias for columns.
    # - spacing (number) -- spacing between cells in pixels.
    # - width (number) -- grid width in pixels.
    # - height (number) -- grid height in pixels.
    # - column_width (length) -- width of each column.
    # - row_height (length) -- height of each row.
    # - fluid (number) -- fluid mode max cell width in pixels.
    # - a11y (hash) -- accessibility overrides.
    class Grid
      # Supported property keys for this widget.
      # @api private
      PROPS = %i[columns column_count spacing width height column_width
        row_height fluid a11y].freeze

      # @!parse
      #   attr_reader :id, :children, :columns, :column_count, :spacing, :width, :height, :column_width, :row_height, :fluid, :a11y
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
      # @return [Grid] new instance with the child appended
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
        Node.new(id: @id, type: "grid", props: props,
          children: Build.children_to_nodes(@children))
      end
    end
  end
end
