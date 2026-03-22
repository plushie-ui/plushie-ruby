# frozen_string_literal: true

module Plushie
  module Widget
    # QR Code -- renders a QR code from a data string.
    #
    # @example
    #   qr = Plushie::Widget::QrCode.new("link", "https://example.com",
    #     cell_size: 6, error_correction: :high)
    #   node = qr.build
    #
    # Props:
    # - data (string) -- the data to encode.
    # - cell_size (number) -- size of each QR module in pixels.
    # - cell_color (string) -- color of dark modules.
    # - background_color (string) -- color of light modules.
    # - error_correction (symbol) -- :low, :medium, :quartile, :high.
    # - alt (string) -- accessible label.
    # - description (string) -- extended accessible description.
    # - a11y (hash) -- accessibility overrides.
    class QrCode
      PROPS = %i[data cell_size cell_color background_color error_correction
        alt description a11y].freeze

      attr_reader :id, *PROPS

      # @param id [String] widget identifier
      # @param data [String] data to encode
      # @param opts [Hash] optional properties
      def initialize(id, data = nil, **opts)
        @id = id.to_s
        @data = data
        PROPS.each { |k| instance_variable_set(:"@#{k}", opts[k]) if opts.key?(k) }
        @data = opts[:data] if opts.key?(:data)
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
        Node.new(id: @id, type: "qr_code", props: props)
      end
    end
  end
end
