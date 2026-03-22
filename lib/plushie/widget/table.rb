# frozen_string_literal: true

module Plushie
  module Widget
    class Table
      PROPS = %i[columns rows header separator width padding sort_by sort_order
        header_text_size row_text_size cell_spacing row_spacing
        separator_thickness separator_color a11y].freeze

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
        Node.new(id: @id, type: "table", props: props,
          children: Build.children_to_nodes(@children))
      end
    end
  end
end
