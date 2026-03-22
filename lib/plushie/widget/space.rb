# frozen_string_literal: true

module Plushie
  module Widget
    # Empty space -- invisible spacer widget.
    #
    # @example
    #   sp = Plushie::Widget::Space.new("gap", width: 20, height: 10)
    #   node = sp.build
    #
    # Props:
    # - width (length) -- space width.
    # - height (length) -- space height.
    # - a11y (hash) -- accessibility overrides.
    class Space
      PROPS = %i[width height a11y].freeze

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
        Node.new(id: @id, type: "space", props: props)
      end
    end
  end
end
