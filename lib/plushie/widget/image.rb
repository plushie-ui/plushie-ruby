# frozen_string_literal: true

module Plushie
  module Widget
    # Image -- display an image from a file path or URL.
    #
    # @example
    #   img = Plushie::Widget::Image.new("avatar", "/path/to/photo.png",
    #     width: 64, height: 64, content_fit: :cover, border_radius: 32)
    #   node = img.build
    #
    # Props:
    # - source (string) -- image file path or URL.
    # - width (length) -- display width.
    # - height (length) -- display height.
    # - content_fit (symbol) -- how the image fits: :contain, :cover, :fill, etc.
    # - rotation (number) -- rotation angle in degrees.
    # - opacity (number) -- opacity from 0.0 to 1.0.
    # - border_radius (number) -- corner radius in pixels.
    # - filter_method (symbol) -- resampling filter: :nearest, :linear.
    # - expand (boolean) -- expand to fill available space.
    # - scale (number) -- image scale factor.
    # - crop (hash) -- crop region { x, y, width, height }.
    # - alt (string) -- alt text for accessibility.
    # - description (string) -- longer description for accessibility.
    # - decorative (boolean) -- mark as decorative (hidden from a11y tree).
    # - a11y (hash) -- accessibility overrides.
    class Image
      # Supported property keys for the image widget.
      PROPS = %i[source width height content_fit rotation opacity border_radius
        filter_method expand scale crop alt description decorative a11y].freeze

      attr_reader :id, *PROPS

      # @param id [String] widget identifier
      # @param source [String, nil] image file path or URL
      # @param opts [Hash] optional properties matching PROPS keys
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
        Node.new(id: @id, type: "image", props: props)
      end
    end
  end
end
