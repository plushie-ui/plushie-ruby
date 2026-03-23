# frozen_string_literal: true

module Plushie
  module Widget
    # Themer -- per-subtree theme override.
    #
    # @example
    #   t = Plushie::Widget::Themer.new("dark", :dark)
    #     .push(Plushie::Widget::Text.new("msg", "Dark themed"))
    #   node = t.build
    #
    # Props:
    # - theme (symbol|hash) -- built-in theme atom or custom palette map.
    # - a11y (hash) -- accessibility overrides.
    class Themer
      # Supported property keys for this widget.
      # @api private
      PROPS = %i[theme a11y].freeze

      # @!parse
      #   attr_reader :id, :children, :theme, :a11y
      class_eval { attr_reader :id, :children, *PROPS }

      # @param id [String] widget identifier
      # @param theme [Symbol, Hash, nil] theme to apply
      # @param opts [Hash] optional properties
      def initialize(id, theme = nil, **opts)
        @id = id.to_s
        @theme = theme
        @children = opts.delete(:children) || []
        PROPS.each { |k| instance_variable_set(:"@#{k}", opts[k]) if opts.key?(k) }
        @theme = opts[:theme] if opts.key?(:theme)
      end

      PROPS.each do |prop|
        define_method(:"set_#{prop}") do |value|
          dup.tap { _1.instance_variable_set(:"@#{prop}", value) }
        end
      end

      # Append a child widget.
      # @param child [Plushie::Node, #build] child widget
      # @return [Themer] new instance with the child appended
      def push(child)
        dup.tap { _1.instance_variable_set(:@children, @children + [child]) }
      end

      # @return [Plushie::Node]
      def build
        props = {}
        PROPS.each do |key|
          val = instance_variable_get(:"@#{key}")
          Build.put_if(props, key, val)
        end
        Node.new(id: @id, type: "themer", props: props,
          children: Build.children_to_nodes(@children))
      end
    end
  end
end
