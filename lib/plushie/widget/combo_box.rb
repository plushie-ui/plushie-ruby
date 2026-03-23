# frozen_string_literal: true

module Plushie
  module Widget
    # Combo box -- searchable dropdown with free-form text input.
    #
    # @example
    #   cb = Plushie::Widget::ComboBox.new("fruit", ["Apple", "Banana"],
    #     selected: "Apple", placeholder: "Search...")
    #   node = cb.build
    #
    # Props:
    # - options (array of strings) -- available choices.
    # - selected (string|nil) -- currently selected value.
    # - placeholder (string) -- placeholder text.
    # - width (length) -- widget width.
    # - padding (number|hash) -- internal padding.
    # - size (number) -- text size in pixels.
    # - font (string|hash) -- font specification.
    # - line_height (number|hash) -- text line height.
    # - menu_height (number) -- max dropdown menu height in pixels.
    # - icon (hash) -- icon inside the text input.
    # - on_option_hovered (boolean) -- emit option hover events.
    # - on_open (boolean) -- emit open event.
    # - on_close (boolean) -- emit close event.
    # - shaping (symbol) -- text shaping strategy.
    # - ellipsis (string) -- text ellipsis strategy.
    # - menu_style (hash) -- dropdown menu style overrides.
    # - style (symbol|hash) -- named style or style map.
    # - a11y (hash) -- accessibility overrides.
    class ComboBox
      # Supported property keys for this widget.
      # @api private
      PROPS = %i[options selected placeholder width padding size font
        line_height menu_height icon on_option_hovered on_open on_close
        shaping ellipsis menu_style style a11y].freeze

      # @!parse
      #   attr_reader :id, :options, :selected, :placeholder, :width, :padding, :size, :font, :line_height, :menu_height, :icon, :on_option_hovered, :on_open, :on_close, :shaping, :ellipsis, :menu_style, :style, :a11y
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
        Node.new(id: @id, type: "combo_box", props: props)
      end
    end
  end
end
