# frozen_string_literal: true

module Plushie
  module Widget
    # Tooltip -- shows a popup tip over child content on hover.
    #
    # @example
    #   tt = Plushie::Widget::Tooltip.new("help", "Click for help", position: :top)
    #     .push(Plushie::Widget::Button.new("btn", "?"))
    #   node = tt.build
    #
    # Props:
    # - tip (string) -- tooltip text.
    # - position (symbol) -- :top, :bottom, :left, :right, :follow_cursor.
    # - gap (number) -- gap between tooltip and content in pixels.
    # - padding (number) -- tooltip padding in pixels.
    # - snap_within_viewport (boolean) -- keep tooltip in viewport.
    # - delay (integer) -- delay in ms before showing.
    # - style (symbol|hash) -- named style or style map.
    # - a11y (hash) -- accessibility overrides.
    class Tooltip
      PROPS = %i[tip position gap padding snap_within_viewport delay
        style a11y].freeze

      attr_reader :id, :children, *PROPS

      # @param id [String] widget identifier
      # @param tip [String] tooltip text
      # @param opts [Hash] optional properties
      def initialize(id, tip = nil, **opts)
        @id = id.to_s
        @tip = tip
        @children = opts.delete(:children) || []
        PROPS.each { |k| instance_variable_set(:"@#{k}", opts[k]) if opts.key?(k) }
        @tip = opts[:tip] if opts.key?(:tip)
      end

      PROPS.each do |prop|
        define_method(:"set_#{prop}") do |value|
          dup.tap { _1.instance_variable_set(:"@#{prop}", value) }
        end
      end

      # Append a child widget.
      # @param child [Plushie::Node, #build] child widget
      # @return [Tooltip] new instance with the child appended
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
        Node.new(id: @id, type: "tooltip", props: props,
          children: Build.children_to_nodes(@children))
      end
    end
  end
end
