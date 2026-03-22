# frozen_string_literal: true

module Plushie
  module Widget
    # Horizontal or vertical rule (divider line).
    #
    # @example
    #   r = Plushie::Widget::Rule.new("divider", direction: :horizontal, height: 2)
    #   node = r.build
    #
    # Props:
    # - height (number) -- line thickness for horizontal rules.
    # - width (number) -- line thickness for vertical rules.
    # - direction (symbol) -- :horizontal or :vertical.
    # - style (symbol|hash) -- :default, :weak, or style map.
    # - a11y (hash) -- accessibility overrides.
    class Rule
      PROPS = %i[height width direction style a11y].freeze

      attr_reader :id, *PROPS

      # @param id [String] widget identifier
      # @param opts [Hash] optional properties
      def initialize(id, **opts)
        @id = id.to_s
        PROPS.each { |k| instance_variable_set(:"@#{k}", opts[k]) if opts.key?(k) }
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
        Node.new(id: @id, type: "rule", props: props)
      end
    end
  end
end
