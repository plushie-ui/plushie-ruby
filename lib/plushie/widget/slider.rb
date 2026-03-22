# frozen_string_literal: true

module Plushie
  module Widget
    class Slider
      PROPS = %i[range value step shift_step default width height
        circular_handle rail_color rail_width style label
        event_rate a11y].freeze

      attr_reader :id, *PROPS

      def initialize(id, range, value, **opts)
        @id = id.to_s
        @range = range
        @value = value
        PROPS.each { |k| instance_variable_set(:"@#{k}", opts[k]) if opts.key?(k) }
        @range = opts[:range] if opts.key?(:range)
        @value = opts[:value] if opts.key?(:value)
      end

      PROPS.each do |prop|
        define_method(:"set_#{prop}") do |value|
          dup.tap { _1.instance_variable_set(:"@#{prop}", value) }
        end
      end

      def build
        props = {}
        PROPS.each do |key|
          val = instance_variable_get(:"@#{key}")
          Build.put_if(props, key, val)
        end
        Node.new(id: @id, type: "slider", props: props)
      end
    end
  end
end
