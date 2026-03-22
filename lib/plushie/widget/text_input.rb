# frozen_string_literal: true

module Plushie
  module Widget
    class TextInput
      PROPS = %i[value placeholder padding width size font line_height align_x
        icon on_submit on_paste secure ime_purpose style
        placeholder_color selection_color a11y].freeze

      attr_reader :id, *PROPS

      def initialize(id, value = "", **opts)
        @id = id.to_s
        @value = value
        PROPS.each { |k| instance_variable_set(:"@#{k}", opts[k]) if opts.key?(k) }
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
        Node.new(id: @id, type: "text_input", props: props)
      end
    end
  end
end
