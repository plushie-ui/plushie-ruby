# frozen_string_literal: true

module Plushie
  module Widget
    class Button
      PROPS = %i[label width height padding clip style disabled a11y].freeze

      attr_reader :id, *PROPS

      def initialize(id, label = nil, **opts)
        @id = id.to_s
        @label = label
        PROPS.each { |k| instance_variable_set(:"@#{k}", opts[k]) if opts.key?(k) }
        @label ||= opts[:label]
      end

      PROPS.each do |prop|
        define_method(:"set_#{prop}") do |value|
          dup.tap { _1.instance_variable_set(:"@#{prop}", value) }
        end
      end

      def build
        props = {}
        Build.put_if(props, :label, @label)
        Build.put_if(props, :width, @width)
        Build.put_if(props, :height, @height)
        Build.put_if(props, :padding, @padding)
        Build.put_if(props, :clip, @clip)
        Build.put_if(props, :style, @style)
        Build.put_if(props, :disabled, @disabled)
        Build.put_if(props, :a11y, @a11y)
        Node.new(id: @id, type: "button", props: props)
      end
    end
  end
end
