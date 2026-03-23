# frozen_string_literal: true

module Plushie
  module Widget
    # Pick list -- dropdown selection.
    #
    # @example
    #   pl = Plushie::Widget::PickList.new("color", ["Red", "Green", "Blue"],
    #     selected: "Red", placeholder: "Choose...")
    #   node = pl.build
    #
    # Props:
    # - options (array of strings) -- available choices.
    # - selected (string|nil) -- currently selected value.
    # - placeholder (string) -- placeholder text.
    # - width (length) -- widget width.
    # - padding (number|hash) -- internal padding.
    # - text_size (number) -- text size in pixels.
    # - font (string|hash) -- font specification.
    # - line_height (number|hash) -- text line height.
    # - menu_height (number) -- max dropdown menu height in pixels.
    # - shaping (symbol) -- text shaping strategy.
    # - handle (hash) -- dropdown handle indicator config.
    # - ellipsis (string) -- text ellipsis strategy.
    # - menu_style (hash) -- dropdown menu style overrides.
    # - style (symbol|hash) -- named style or style map.
    # - on_open (boolean) -- emit open event.
    # - on_close (boolean) -- emit close event.
    # - a11y (hash) -- accessibility overrides.
    class PickList
      # Supported property keys for this widget.
      # @api private
      PROPS = %i[options selected placeholder width padding text_size font
        line_height menu_height shaping handle ellipsis menu_style style
        on_open on_close a11y].freeze

      # @!parse
      #   attr_reader :id, :options, :selected, :placeholder, :width, :padding, :text_size, :font, :line_height, :menu_height, :shaping, :handle, :ellipsis, :menu_style, :style, :on_open, :on_close, :a11y
      class_eval { attr_reader :id, *PROPS }

      # @param id [String] widget identifier
      # @param options [Array<String>] available choices
      # @param opts [Hash] optional properties
      def initialize(id, options = [], **opts)
        @id = id.to_s
        @options = options
        PROPS.each { |k| instance_variable_set(:"@#{k}", opts[k]) if opts.key?(k) }
        @options = opts[:options] if opts.key?(:options)
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
        Node.new(id: @id, type: "pick_list", props: props)
      end
    end
  end
end
