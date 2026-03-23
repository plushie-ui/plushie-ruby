# frozen_string_literal: true

module Plushie
  module Widget
    # Slider -- horizontal range input.
    #
    # @example
    #   slider = Plushie::Widget::Slider.new("volume", [0, 100], 75, step: 5)
    #   node = slider.build
    #
    # Props:
    # - range (array) -- two-element [min, max] range.
    # - value (numeric) -- current slider value.
    # - step (numeric) -- value increment per step.
    # - shift_step (numeric) -- value increment when shift is held.
    # - default (numeric) -- default value on double-click.
    # - width (length) -- widget width.
    # - height (number) -- rail height in pixels.
    # - circular_handle (boolean) -- use a circular handle.
    # - rail_color (string) -- rail background colour.
    # - rail_width (number) -- rail thickness in pixels.
    # - style (symbol|hash) -- named style or style map.
    # - label (string) -- accessible label.
    # - event_rate (number) -- throttle rate for change events (ms).
    # - a11y (hash) -- accessibility overrides.
    class Slider
      # Supported property keys for the slider widget.
      PROPS = %i[range value step shift_step default width height
        circular_handle rail_color rail_width style label
        event_rate a11y].freeze

      # @!parse
      #   attr_reader :id, :range, :value, :step, :shift_step, :default, :width, :height, :circular_handle, :rail_color, :rail_width, :style, :label, :event_rate, :a11y
      class_eval { attr_reader :id, *PROPS }

      # @param id [String] widget identifier
      # @param range [Array<Numeric>] two-element [min, max] range
      # @param value [Numeric] initial slider value
      # @param opts [Hash] optional properties matching PROPS keys
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
        Node.new(id: @id, type: "slider", props: props)
      end
    end
  end
end
