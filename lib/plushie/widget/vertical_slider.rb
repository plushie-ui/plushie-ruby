# frozen_string_literal: true

module Plushie
  module Widget
    # Vertical slider -- vertical range input.
    #
    # @example
    #   vs = Plushie::Widget::VerticalSlider.new("vol", [0, 100], 50, step: 5)
    #   node = vs.build
    #
    # Props:
    # - range (array) -- [min, max] range.
    # - value (number) -- current slider value.
    # - step (number) -- step increment.
    # - shift_step (number) -- step when Shift is held.
    # - default (number) -- double-click reset value.
    # - width (length) -- slider width.
    # - height (length) -- slider height.
    # - rail_color (string) -- rail color.
    # - rail_width (number) -- rail thickness in pixels.
    # - style (symbol|hash) -- named style or style map.
    # - label (string) -- accessible label.
    # - event_rate (integer) -- max events per second.
    # - a11y (hash) -- accessibility overrides.
    class VerticalSlider
      # Supported property keys for this widget.
      # @api private
      PROPS = %i[range value step shift_step default width height
        rail_color rail_width style label event_rate a11y].freeze

      # @!parse
      #   attr_reader :id, :range, :value, :step, :shift_step, :default, :width, :height, :rail_color, :rail_width, :style, :label, :event_rate, :a11y
      class_eval { attr_reader :id, *PROPS }

      # @param id [String] widget identifier
      # @param range [Array<Numeric>] [min, max] range
      # @param value [Numeric] current value
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
        Node.new(id: @id, type: "vertical_slider", props: props)
      end
    end
  end
end
