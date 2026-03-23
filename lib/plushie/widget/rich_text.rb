# frozen_string_literal: true

module Plushie
  module Widget
    # Rich text display with individually styled spans.
    #
    # @example
    #   rt = Plushie::Widget::RichText.new("msg",
    #     spans: [{text: "Hello ", size: 16}, {text: "World", color: "#f00"}])
    #   node = rt.build
    #
    # Props:
    # - spans (array of hashes) -- list of span descriptors.
    # - width (length) -- widget width.
    # - height (length) -- widget height.
    # - size (number) -- default font size.
    # - font (string|hash) -- default font.
    # - color (string) -- default text color.
    # - line_height (number|hash) -- line height.
    # - wrapping (symbol) -- text wrapping mode.
    # - ellipsis (string) -- text ellipsis mode.
    # - a11y (hash) -- accessibility overrides.
    class RichText
      # Supported property keys for this widget.
      # @api private
      PROPS = %i[spans width height size font color line_height wrapping
        ellipsis a11y].freeze

      # @!parse
      #   attr_reader :id, :spans, :width, :height, :size, :font, :color, :line_height, :wrapping, :ellipsis, :a11y
      class_eval { attr_reader :id, *PROPS }

      # @param id [String] widget identifier
      # @param opts [Hash] optional properties
      def initialize(id, **opts)
        @id = id.to_s
        PROPS.each { |k| instance_variable_set(:"@#{k}", opts[k]) if opts.key?(k) }
      end

      PROPS.each do |prop|
        define_method(:"set_#{prop}") do |value|
          dup.tap { _1.instance_variable_set(:"@#{prop}", value) }
        end
      end

      # @return [Plushie::Node]
      def build
        props = {}
        PROPS.each do |key|
          val = instance_variable_get(:"@#{key}")
          Build.put_if(props, key, val)
        end
        Node.new(id: @id, type: "rich_text", props: props)
      end
    end
  end
end
