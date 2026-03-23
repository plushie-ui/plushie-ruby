# frozen_string_literal: true

module Plushie
  module Widget
    # Scrollable -- scrollable container for overflow content.
    #
    # A container widget: child nodes are placed inside the
    # scrollable viewport. Use {#push} to add children immutably.
    #
    # @example
    #   scrollable = Plushie::Widget::Scrollable.new("log",
    #     width: { fill: true }, height: 300, direction: :vertical)
    #   node = scrollable.push(some_child).build
    #
    # Props:
    # - width (length) -- viewport width.
    # - height (length) -- viewport height.
    # - direction (symbol) -- :vertical, :horizontal, or :both.
    # - spacing (number) -- spacing between children in pixels.
    # - scrollbar_width (number) -- scrollbar track width.
    # - scrollbar_margin (number) -- margin around scrollbar.
    # - scroller_width (number) -- scroller thumb width.
    # - anchor (symbol) -- scroll anchor: :start or :end.
    # - on_scroll (boolean) -- emit scroll events.
    # - auto_scroll (boolean) -- auto-scroll to end on content change.
    # - scrollbar_color (string) -- scrollbar track colour.
    # - scroller_color (string) -- scroller thumb colour.
    # - a11y (hash) -- accessibility overrides.
    class Scrollable
      # Supported property keys for the scrollable widget.
      PROPS = %i[width height direction spacing scrollbar_width scrollbar_margin
        scroller_width anchor on_scroll auto_scroll scrollbar_color
        scroller_color a11y].freeze

      # @!parse
      #   attr_reader :id, :children, :width, :height, :direction, :spacing, :scrollbar_width, :scrollbar_margin, :scroller_width, :anchor, :on_scroll, :auto_scroll, :scrollbar_color, :scroller_color, :a11y
      class_eval { attr_reader :id, :children, *PROPS }

      # @param id [String] widget identifier
      # @param opts [Hash] optional properties matching PROPS keys
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

      # Append a child node. Returns a new Scrollable (immutable).
      #
      # @param child [Object] child widget or node
      # @return [Scrollable]
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
        Node.new(id: @id, type: "scrollable", props: props,
          children: Build.children_to_nodes(@children))
      end
    end
  end
end
