# frozen_string_literal: true

module Plushie
  module Widget
    class Canvas
      PROPS = %i[layers shapes width height background interactive
        on_press on_release on_move on_scroll alt description
        event_rate a11y].freeze

      attr_reader :id, *PROPS

      def initialize(id, **opts)
        @id = id.to_s
        PROPS.each { |k| instance_variable_set(:"@#{k}", opts[k]) if opts.key?(k) }
      end

      PROPS.each do |prop|
        define_method(:"set_#{prop}") do |value|
          dup.tap { _1.instance_variable_set(:"@#{prop}", value) }
        end
      end

      def add_layer(name, shapes)
        current = @layers || {}
        dup.tap { _1.instance_variable_set(:@layers, current.merge(name => shapes)) }
      end

      def build
        props = {}
        PROPS.each do |key|
          val = instance_variable_get(:"@#{key}")
          Build.put_if(props, key, val)
        end
        Node.new(id: @id, type: "canvas", props: props)
      end
    end
  end
end
