# frozen_string_literal: true

module Plushie
  module Widget
    # SVG display -- renders a vector image from a file path.
    #
    # @example
    #   svg = Plushie::Widget::Svg.new("logo", "logo.svg",
    #     width: 64, height: 64)
    #   node = svg.build
    #
    # Props:
    # - source (string) -- path to the SVG file.
    # - width (length) -- SVG width.
    # - height (length) -- SVG height.
    # - content_fit (symbol) -- how the SVG fits its bounds.
    # - rotation (number) -- rotation angle in degrees.
    # - opacity (number) -- opacity 0.0-1.0.
    # - color (string) -- color tint applied to the SVG.
    # - alt (string) -- accessible label.
    # - description (string) -- extended accessible description.
    # - decorative (boolean) -- hide from assistive technology.
    # - a11y (hash) -- accessibility overrides.
    class Svg
      # Supported property keys for this widget.
      # @api private
      PROPS = %i[source width height content_fit rotation opacity color
        alt description decorative a11y].freeze

      # @!parse
      #   attr_reader :id, :source, :width, :height, :content_fit, :rotation, :opacity, :color, :alt, :description, :decorative, :a11y
      class_eval { attr_reader :id, *PROPS }

      # @param id [String] widget identifier
      # @param source [String] path to SVG file
      # @param opts [Hash] optional properties
      def initialize(id, source = nil, **opts)
        @id = id.to_s
        @source = source
        PROPS.each { |k| instance_variable_set(:"@#{k}", opts[k]) if opts.key?(k) }
        @source = opts[:source] if opts.key?(:source)
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
        Node.new(id: @id, type: "svg", props: props)
      end
    end
  end
end
