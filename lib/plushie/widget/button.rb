# frozen_string_literal: true

module Plushie
  module Widget
    # Typed builder for the button widget (Layer 2 API).
    #
    # Construct a Button, set properties via fluent +set_*+ methods,
    # then call {#build} to produce a {Plushie::Node} for the view tree.
    # Each +set_*+ method returns a shallow copy, so the original is
    # never mutated -- safe for reuse across renders.
    #
    # PROPS holds the list of supported property keys:
    # label, width, height, padding, clip, style, disabled, a11y.
    #
    # @example Basic usage
    #   Button.new("save", "Save").set_style(:primary).build
    #
    # @example With padding and disabled state
    #   Button.new("cancel", "Cancel", padding: 8, disabled: true).build
    class Button
      # Supported property keys for the button widget.
      PROPS = %i[label width height padding clip style disabled a11y].freeze

      attr_reader :id, *PROPS

      # @param id [String] widget identifier (first arg by convention)
      # @param label [String, nil] button label text
      # @param opts [Hash] optional properties matching PROPS keys
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

      # Build a {Plushie::Node} from the current property values.
      #
      # @return [Plushie::Node]
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
