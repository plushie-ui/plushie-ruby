# frozen_string_literal: true

module Plushie
  # A UI tree node. Produced by DSL methods and widget builders.
  #
  # Nodes are immutable value objects representing a single widget in the
  # view tree. The runtime diffs consecutive trees to produce patches
  # sent to the renderer.
  #
  # @!attribute [r] id [String] unique widget identifier (scoped within parent containers)
  # @!attribute [r] type [String] widget type name ("button", "column", "text_input", etc.)
  # @!attribute [r] props [Hash] frozen hash of property values (symbol keys)
  # @!attribute [r] children [Array<Node>] frozen array of child nodes (empty for leaf widgets)
  #
  # @example Creating a node
  #   Node.new(id: "greeting", type: "text", props: { content: "Hello" })
  # @example Pattern matching
  #   case node
  #   in Node[type: "button", id:]
  #     puts "Found button: #{id}"
  #   end
  #
  Node = Data.define(:id, :type, :props, :children) do
    # Create a new Node with string-coerced id and type, and frozen props/children.
    #
    # @param id [#to_s] unique widget identifier
    # @param type [#to_s] widget type name
    # @param props [Hash] widget properties (will be frozen)
    # @param children [Array<Node>] child nodes (will be frozen)
    # @return [Node]
    def initialize(id:, type:, props: {}, children: [])
      super(id: id.to_s, type: type.to_s, props: props.freeze, children: children.freeze)
    end

    # Return a new Node with the given fields replaced.
    # Unspecified fields retain their current values.
    #
    # @param changes [Hash] fields to replace (:id, :type, :props, :children)
    # @return [Node] new Node with the changes applied
    def with(**changes)
      self.class.new(**to_h.merge(changes))
    end
  end
end
