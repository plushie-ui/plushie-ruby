# frozen_string_literal: true

module Plushie
  module Widget
    # Pane grid -- resizable tiled panes.
    #
    # @example
    #   pg = Plushie::Widget::PaneGrid.new("editor", spacing: 4)
    #     .push(Plushie::Widget::Text.new("left", "Left pane"))
    #     .push(Plushie::Widget::Text.new("right", "Right pane"))
    #   node = pg.build
    #
    # Props:
    # - panes (array of strings) -- pane identifiers.
    # - spacing (number) -- space between panes in pixels.
    # - width (length) -- grid width.
    # - height (length) -- grid height.
    # - min_size (number) -- minimum pane size in pixels.
    # - divider_color (string) -- divider color.
    # - divider_width (number) -- divider thickness in pixels.
    # - leeway (number) -- grabbable area around dividers.
    # - event_rate (integer) -- max events per second.
    # - a11y (hash) -- accessibility overrides.
    class PaneGrid
      # Supported property keys for this widget.
      # @api private
      PROPS = %i[panes spacing width height min_size divider_color
        divider_width leeway event_rate a11y].freeze

      # @!parse
      #   attr_reader :id, :children, :panes, :spacing, :width, :height, :min_size, :divider_color, :divider_width, :leeway, :event_rate, :a11y
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

      # Append a child pane.
      # @param child [Plushie::Node, #build] child widget
      # @return [PaneGrid] new instance with the child appended
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
        Node.new(id: @id, type: "pane_grid", props: props,
          children: Build.children_to_nodes(@children))
      end
    end
  end
end
