# frozen_string_literal: true

module Plushie
  module Widget
    # Typed builder for the text widget (Layer 2 API).
    #
    # Construct a Text, set properties via fluent +set_*+ methods,
    # then call {#build} to produce a {Plushie::Node} for the view tree.
    class Text
      # Supported property keys for this widget.
      # @api private
      PROPS = %i[content size color font width height line_height align_x align_y
        wrapping ellipsis shaping style a11y].freeze

      # @!parse
      #   attr_reader :id, :content, :size, :color, :font, :width, :height, :line_height, :align_x, :align_y, :wrapping, :ellipsis, :shaping, :style, :a11y
      class_eval { attr_reader :id, *PROPS }

      def initialize(id, content = nil, **opts)
        @id = id.to_s
        @content = content
        PROPS.each { |k| instance_variable_set(:"@#{k}", opts[k]) if opts.key?(k) }
        @content ||= opts[:content]
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
        Build.put_if(props, :content, @content)
        Build.put_if(props, :size, @size)
        Build.put_if(props, :color, @color)
        Build.put_if(props, :font, @font)
        Build.put_if(props, :width, @width)
        Build.put_if(props, :height, @height)
        Build.put_if(props, :line_height, @line_height)
        Build.put_if(props, :align_x, @align_x)
        Build.put_if(props, :align_y, @align_y)
        Build.put_if(props, :wrapping, @wrapping)
        Build.put_if(props, :ellipsis, @ellipsis)
        Build.put_if(props, :shaping, @shaping)
        Build.put_if(props, :style, @style)
        Build.put_if(props, :a11y, @a11y)
        Node.new(id: @id, type: "text", props: props)
      end
    end
  end
end
