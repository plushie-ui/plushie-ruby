# frozen_string_literal: true

module Plushie
  module Widget
    class Scrollable
      PROPS = %i[width height direction spacing scrollbar_width scrollbar_margin
        scroller_width anchor on_scroll auto_scroll scrollbar_color
        scroller_color a11y].freeze

      attr_reader :id, :children, *PROPS

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

      def push(child)
        dup.tap { _1.instance_variable_set(:@children, @children + [child]) }
      end

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
