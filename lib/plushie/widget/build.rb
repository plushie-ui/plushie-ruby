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
    end
  end
end
