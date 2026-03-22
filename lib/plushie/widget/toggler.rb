# frozen_string_literal: true

module Plushie
  module Widget
    # Toggler -- on/off switch.
    #
    # @example
    #   toggler = Plushie::Widget::Toggler.new("dark_mode", true, label: "Dark mode")
    #   node = toggler.build
    #
    # Props:
    # - is_toggled (boolean) -- whether the toggler is on.
    # - label (string) -- text label next to the toggler.
    # - spacing (number) -- space between toggler and label in pixels.
    # - width (length) -- widget width.
    # - size (number) -- toggler size in pixels.
    # - text_size (number) -- label text size in pixels.
    # - font (string|map) -- label font.
    # - line_height (number|map) -- label line height.
    # - shaping (symbol) -- text shaping: :basic, :advanced, :auto.
    # - wrapping (symbol) -- text wrapping: :none, :word, :glyph, :word_or_glyph.
    # - text_alignment (symbol) -- horizontal label alignment: :left, :center, :right.
    # - style (symbol) -- named style.
    # - disabled (boolean) -- whether the toggler is disabled.
    # - a11y (hash) -- accessibility overrides.
    class Toggler
      PROPS = %i[is_toggled label spacing width size text_size font line_height
        shaping wrapping text_alignment style disabled a11y].freeze

      attr_reader :id, *PROPS

      # @param id [String] widget identifier
      # @param is_toggled [Boolean] whether the toggler is on
      # @param opts [Hash] optional properties
      def initialize(id, is_toggled = false, **opts)
        @id = id.to_s
        @is_toggled = is_toggled
        PROPS.each { |k| instance_variable_set(:"@#{k}", opts[k]) if opts.key?(k) }
        @is_toggled = opts[:is_toggled] if opts.key?(:is_toggled)
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
        Node.new(id: @id, type: "toggler", props: props)
      end
    end
  end
end
