# frozen_string_literal: true

module Plushie
  module Widget
    # Mouse area -- captures mouse events on child content.
    #
    # @example
    #   ma = Plushie::Widget::MouseArea.new("clickable",
    #     cursor: :pointer, on_right_press: true)
    #     .push(Plushie::Widget::Text.new("label", "Right-click me"))
    #   node = ma.build
    #
    # Props:
    # - cursor (symbol) -- mouse cursor on hover.
    # - on_press (string) -- event tag for left press.
    # - on_release (string) -- event tag for left release.
    # - on_right_press (boolean) -- enable right press events.
    # - on_right_release (boolean) -- enable right release events.
    # - on_middle_press (boolean) -- enable middle press events.
    # - on_middle_release (boolean) -- enable middle release events.
    # - on_double_click (boolean) -- enable double-click events.
    # - on_enter (boolean) -- enable cursor enter events.
    # - on_exit (boolean) -- enable cursor exit events.
    # - on_move (boolean) -- enable cursor move events.
    # - on_scroll (boolean) -- enable scroll events.
    # - event_rate (integer) -- max events per second.
    # - a11y (hash) -- accessibility overrides.
    class MouseArea
      # Supported property keys for this widget.
      # @api private
      PROPS = %i[cursor on_press on_release on_right_press on_right_release
        on_middle_press on_middle_release on_double_click on_enter on_exit
        on_move on_scroll event_rate a11y].freeze

      # @!parse
      #   attr_reader :id, :children, :cursor, :on_press, :on_release, :on_right_press, :on_right_release, :on_middle_press, :on_middle_release, :on_double_click, :on_enter, :on_exit, :on_move, :on_scroll, :event_rate, :a11y
      class_eval { attr_reader :id, :children, *PROPS }

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
      # @return [MouseArea] new instance with the child appended
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
        Node.new(id: @id, type: "mouse_area", props: props,
          children: Build.children_to_nodes(@children))
      end
    end
  end
end
