# frozen_string_literal: true

module Plushie
  module Widget
    # Radio button -- one-of-many selection.
    #
    # @example
    #   r = Plushie::Widget::Radio.new("opt_a", "a", "a",
    #     label: "Option A", group: "choices")
    #   node = r.build
    #
    # Props:
    # - value (string) -- the value this radio represents.
    # - selected (string|nil) -- currently selected value in the group.
    # - label (string) -- label text (defaults to value).
    # - group (string) -- group identifier.
    # - spacing (number) -- space between radio and label in pixels.
    # - width (length) -- widget width.
    # - size (number) -- radio button size in pixels.
    # - text_size (number) -- label text size in pixels.
    # - font (string|hash) -- label font.
    # - line_height (number|hash) -- label line height.
    # - shaping (symbol) -- text shaping strategy.
    # - wrapping (symbol) -- text wrapping mode.
    # - style (symbol|hash) -- named style or style map.
    # - a11y (hash) -- accessibility overrides.
    class Radio
      PROPS = %i[value selected label group spacing width size text_size
        font line_height shaping wrapping style a11y].freeze

      attr_reader :id, *PROPS

      # @param id [String] widget identifier
      # @param value [String] the value this radio represents
      # @param selected [String, nil] currently selected value in the group
      # @param opts [Hash] optional properties
      def initialize(id, value, selected, **opts)
        @id = id.to_s
        @value = value
        @selected = selected
        PROPS.each { |k| instance_variable_set(:"@#{k}", opts[k]) if opts.key?(k) }
        @value = opts[:value] if opts.key?(:value)
        @selected = opts[:selected] if opts.key?(:selected)
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
        Node.new(id: @id, type: "radio", props: props)
      end
    end
  end
end
