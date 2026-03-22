# frozen_string_literal: true

module Plushie
  module Widget
    class Container
      PROPS = %i[padding width height max_width max_height center clip
        align_x align_y background color border shadow style a11y].freeze

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

      def center_x(width = :fill)
        dup.tap do |c|
          c.instance_variable_set(:@width, width)
          c.instance_variable_set(:@align_x, :center)
        end
      end

      def center_y(height = :fill)
        dup.tap do |c|
          c.instance_variable_set(:@height, height)
          c.instance_variable_set(:@align_y, :center)
        end
      end

      def build
        props = {}
        PROPS.each do |key|
          val = instance_variable_get(:"@#{key}")
          Build.put_if(props, key, val)
        end
        Node.new(id: @id, type: "container", props: props,
          children: Build.children_to_nodes(@children))
      end
    end
  end
end
