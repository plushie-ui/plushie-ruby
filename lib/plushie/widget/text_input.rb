# frozen_string_literal: true

module Plushie
  module Widget
    # Typed builder for the single-line text input widget (Layer 2 API).
    #
    # Construct a TextInput, configure via fluent +set_*+ methods,
    # then call {#build} to produce a {Plushie::Node}.
    #
    # PROPS: value, placeholder, padding, width, size, font,
    # line_height, align_x, icon, on_submit, on_paste, secure,
    # ime_purpose, style, placeholder_color, selection_color, a11y.
    #
    # @example
    #   TextInput.new("email", "", placeholder: "you@example.com")
    #     .set_size(16)
    #     .build
    class TextInput
      # Supported property keys for the text input widget.
      PROPS = %i[value placeholder padding width size font line_height align_x
        icon on_submit on_paste secure ime_purpose style
        placeholder_color selection_color a11y].freeze

      # @!parse
      #   attr_reader :id, :value, :placeholder, :padding, :width, :size, :font, :line_height, :align_x, :icon, :on_submit, :on_paste, :secure, :ime_purpose, :style, :placeholder_color, :selection_color, :a11y
      class_eval { attr_reader :id, *PROPS }

      # @param id [String] widget identifier
      # @param value [String] initial text value
      # @param opts [Hash] optional properties matching PROPS keys
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

      # Build a {Plushie::Node} from the current property values.
      #
      # @return [Plushie::Node]
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
