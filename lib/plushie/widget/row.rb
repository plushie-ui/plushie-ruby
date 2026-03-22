# frozen_string_literal: true

module Plushie
  module Widget
    class Row
      PROPS = %i[spacing padding width height align_y max_width clip wrap a11y].freeze

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
        Node.new(id: @id, type: "row", props: props,
          children: Build.children_to_nodes(@children))
      end
    end
  end
end
