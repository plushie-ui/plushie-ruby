# frozen_string_literal: true

module Plushie
  module Widget
    # Progress bar -- displays progress within a range.
    #
    # @example
    #   pb = Plushie::Widget::ProgressBar.new("upload", [0, 100], 42,
    #     style: :primary)
    #   node = pb.build
    #
    # Props:
    # - range (array) -- [min, max] range.
    # - value (number) -- current progress value.
    # - width (length) -- bar width.
    # - height (length) -- bar height.
    # - style (symbol|hash) -- :primary, :secondary, :success, :danger, :warning, or style map.
    # - vertical (boolean) -- render vertically.
    # - label (string) -- accessible label.
    # - a11y (hash) -- accessibility overrides.
    class ProgressBar
      PROPS = %i[range value width height style vertical label a11y].freeze

      attr_reader :id, *PROPS

      # @param id [String] widget identifier
      # @param range [Array<Numeric>] [min, max] range
      # @param value [Numeric] current progress value
      # @param opts [Hash] optional properties
      def initialize(id, range, value, **opts)
        @id = id.to_s
        @range = range
        @value = value
        PROPS.each { |k| instance_variable_set(:"@#{k}", opts[k]) if opts.key?(k) }
        @range = opts[:range] if opts.key?(:range)
        @value = opts[:value] if opts.key?(:value)
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
        Node.new(id: @id, type: "progress_bar", props: props)
      end
    end
  end
end
