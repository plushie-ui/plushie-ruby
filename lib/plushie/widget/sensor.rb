# frozen_string_literal: true

module Plushie
  module Widget
    # Sensor -- detects visibility and size changes on child content.
    #
    # @example
    #   s = Plushie::Widget::Sensor.new("detect", delay: 100, anticipate: 50)
    #     .push(Plushie::Widget::Text.new("content", "Watched"))
    #   node = s.build
    #
    # Props:
    # - delay (integer) -- delay in ms before emitting events.
    # - anticipate (number) -- anticipation distance in pixels.
    # - on_resize (string) -- event tag for resize events.
    # - event_rate (integer) -- max events per second.
    # - a11y (hash) -- accessibility overrides.
    class Sensor
      PROPS = %i[delay anticipate on_resize event_rate a11y].freeze

      attr_reader :id, :children, *PROPS

      # @param id [String] widget identifier
      # @param opts [Hash] optional properties
      def initialize(id, **opts)
        @id = id.to_s
        @children = opts.delete(:children) || []
        PROPS.each { |k| instance_variable_set(:"@#{k}", opts[k]) if opts.key?(k) }
      end

      PROPS.each do |prop|
        define_method(:"set_#{prop}") do |value|
          dup.tap { _1.instance_variable_set(:"@#{prop}", value) }
        end
      end

      # Append a child widget.
      # @param child [Plushie::Node, #build] child widget
      # @return [Sensor] new instance with the child appended
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
        Node.new(id: @id, type: "sensor", props: props,
          children: Build.children_to_nodes(@children))
      end
    end
  end
end
