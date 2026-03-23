# frozen_string_literal: true

module Plushie
  module Widget
    # Overlay container -- positions second child as a floating overlay
    # relative to the first child (anchor).
    #
    # @example
    #   o = Plushie::Widget::Overlay.new("menu", position: :below, gap: 4)
    #     .push(Plushie::Widget::Button.new("trigger", "Open"))
    #     .push(Plushie::Widget::Text.new("content", "Menu items"))
    #   node = o.build
    #
    # Props:
    # - position (symbol) -- :below, :above, :left, :right.
    # - gap (number) -- space between anchor and overlay in pixels.
    # - offset_x (number) -- horizontal offset in pixels.
    # - offset_y (number) -- vertical offset in pixels.
    # - flip (boolean) -- auto-flip on viewport overflow.
    # - align (symbol) -- cross-axis alignment: :start, :center, :end.
    # - width (length) -- overlay node width.
    # - a11y (hash) -- accessibility overrides.
    class Overlay
      # Supported property keys for this widget.
      # @api private
      PROPS = %i[position gap offset_x offset_y flip align width a11y].freeze

      # @!parse
      #   attr_reader :id, :children, :position, :gap, :offset_x, :offset_y, :flip, :align, :width, :a11y
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
      # @return [Overlay] new instance with the child appended
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
        Node.new(id: @id, type: "overlay", props: props,
          children: Build.children_to_nodes(@children))
      end
    end
  end
end
