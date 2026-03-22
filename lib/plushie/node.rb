# frozen_string_literal: true

module Plushie
  # A UI tree node. Produced by DSL methods and widget builders.
  #
  # Nodes are plain value objects with four fields:
  #   id       - unique string identifier
  #   type     - widget type string ("button", "column", etc.)
  #   props    - hash of property values (symbol keys)
  #   children - array of child Nodes
  #
  Node = Data.define(:id, :type, :props, :children) do
    def initialize(id:, type:, props: {}, children: [])
      super(id: id.to_s, type: type.to_s, props: props.freeze, children: children.freeze)
    end

    # Return a new Node with the given fields replaced.
    def with(**changes)
      self.class.new(**to_h.merge(changes))
    end
  end
end
