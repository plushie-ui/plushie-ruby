# frozen_string_literal: true

module Plushie
  # Typed widget builder modules (Layer 2 API).
  module Widget
    # Internal helpers for widget builder `build` implementations.
    module Build
      module_function

      # Adds key => value to props hash if value is non-nil.
      def put_if(props, key, value)
        props[key] = value unless value.nil?
        props
      end

      # Adds key => transform(value) to props hash if value is non-nil.
      def put_if_map(props, key, value, &transform)
        props[key] = transform.call(value) unless value.nil?
        props
      end

      # Converts an array of children (Nodes or builder objects) to Nodes.
      def children_to_nodes(children)
        children.map do |child|
          case child
          when Plushie::Node then child
          else
            child.respond_to?(:build) ? child.build : child
          end
        end
      end

      # Returns true if the value is a renderer-side animation descriptor
      # (Transition, Spring, or Sequence).
      #
      # @param value [Object]
      # @return [Boolean]
      def animation_descriptor?(value)
        value.is_a?(Animation::Transition) ||
          value.is_a?(Animation::Spring) ||
          value.is_a?(Animation::Sequence)
      end

      # Wraps a widget build pipeline with animation descriptor passthrough.
      #
      # Separates animation descriptors and the +:exit+ prop from the opts
      # before calling the build block, then merges them onto the resulting
      # node's props. This ensures animation descriptors pass through to the
      # wire without widget builders needing to know about them.
      #
      # @param opts [Hash] widget options (may contain animation descriptors)
      # @yield [widget_opts] the options with animation props removed
      # @yieldreturn [Plushie::Node] the built node
      # @return [Plushie::Node] the node with animation props merged back
      def build_with_animations(opts)
        anim_opts = {}
        widget_opts = {}

        opts.each do |key, value|
          if key == :exit || animation_descriptor?(value)
            anim_opts[key] = value
          else
            widget_opts[key] = value
          end
        end

        node = yield(widget_opts)

        if anim_opts.empty?
          node
        else
          # The exit prop is passed through as-is; its values may be
          # animation descriptors which the Encode module handles via to_wire.

          merged_props = node.props.merge(anim_opts)
          Plushie::Node.new(id: node.id, type: node.type, props: merged_props,
            children: node.children)
        end
      end

      # Validates that a widget has at most one child.
      #
      # Raises ArgumentError if the children list has more than one element.
      # Called from #build in single-child wrappers (container, tooltip,
      # pointer_area, scrollable, themer, floating, responsive, pin,
      # sensor, window).
      #
      # @param id [String] widget ID for the error message
      # @param type [String] widget type name for the error message
      # @param children [Array] children to validate
      # @raise [ArgumentError] if children.length > 1
      def validate_single_child!(id, type, children)
        return if children.length <= 1
        raise ArgumentError,
          "#{type} #{id.inspect} accepts at most 1 child, got #{children.length}"
      end

      # Validates that a widget has exactly the expected number of children.
      #
      # Raises ArgumentError if the children count does not match expected.
      # Called from #build for widgets with strict child count requirements
      # (overlay requires exactly 2).
      #
      # @param id [String] widget ID for the error message
      # @param type [String] widget type name for the error message
      # @param children [Array] children to validate
      # @param expected [Integer] required child count
      # @raise [ArgumentError] if children.length != expected
      def validate_children_count!(id, type, children, expected)
        return if children.length == expected
        raise ArgumentError,
          "#{type} #{id.inspect} requires exactly #{expected} children, got #{children.length}"
      end
    end
  end
end
