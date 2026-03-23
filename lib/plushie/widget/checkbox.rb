# frozen_string_literal: true

module Plushie
  module Widget
    # Typed builder for the checkbox widget (Layer 2 API).
    #
    # Construct a Checkbox, set properties via fluent +set_*+ methods,
    # then call {#build} to produce a {Plushie::Node} for the view tree.
    class Checkbox
      # Supported property keys for this widget.
      # @api private
      PROPS = %i[label is_toggled spacing width size text_size font
        line_height shaping wrapping style icon disabled a11y].freeze

      # @!parse
      #   attr_reader :id, :label, :is_toggled, :spacing, :width, :size, :text_size, :font, :line_height, :shaping, :wrapping, :style, :icon, :disabled, :a11y
      class_eval { attr_reader :id, *PROPS }

      def initialize(id, label, is_toggled = false, **opts)
        @id = id.to_s
        @label = label
        @is_toggled = is_toggled
        PROPS.each { |k| instance_variable_set(:"@#{k}", opts[k]) if opts.key?(k) }
        @label = opts[:label] if opts.key?(:label)
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
        Build.put_if(props, :label, @label)
        Build.put_if(props, :checked, @is_toggled)
        Build.put_if(props, :spacing, @spacing)
        Build.put_if(props, :width, @width)
        Build.put_if(props, :size, @size)
        Build.put_if(props, :text_size, @text_size)
        Build.put_if(props, :font, @font)
        Build.put_if(props, :line_height, @line_height)
        Build.put_if(props, :shaping, @shaping)
        Build.put_if(props, :wrapping, @wrapping)
        Build.put_if(props, :style, @style)
        Build.put_if(props, :icon, @icon)
        Build.put_if(props, :disabled, @disabled)
        Build.put_if(props, :a11y, @a11y)
        Node.new(id: @id, type: "checkbox", props: props)
      end
    end
  end
end
