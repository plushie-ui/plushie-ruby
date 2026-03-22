# frozen_string_literal: true

module Plushie
  # Utilities for working with UI trees.
  #
  # Provides normalization, search, and diffing for Node trees.
  module Tree
    # Find a node by ID (depth-first).
    # Returns the Node or nil.
    def self.find(tree, id)
      return nil if tree.nil?
      trees = tree.is_a?(Array) ? tree : [tree]

      trees.each do |node|
        return node if node.id == id
        found = find(node.children, id)
        return found if found
      end

      nil
    end

    # Check if a node with the given ID exists.
    def self.exists?(tree, id)
      !find(tree, id).nil?
    end

    # Return all node IDs in depth-first order.
    def self.ids(tree)
      result = []
      trees = tree.is_a?(Array) ? tree : [tree]

      trees.each do |node|
        result << node.id
        result.concat(ids(node.children))
      end

      result
    end

    # Find all nodes matching a predicate (depth-first).
    def self.find_all(tree, &predicate)
      result = []
      trees = tree.is_a?(Array) ? tree : [tree]

      trees.each do |node|
        result << node if predicate.call(node)
        result.concat(find_all(node.children, &predicate))
      end

      result
    end

    # Normalize a tree for wire transport.
    # Converts symbol prop values to strings, resolves scoped IDs, etc.
    def self.normalize(tree)
      trees = tree.is_a?(Array) ? tree : [tree]
      trees.map { |node| normalize_node(node, []) }
    end

    def self.normalize_node(node, scope)
      props = node.props.transform_values { |v| encode_value(v) }

      child_scope = if node.type == "window" || node.id.start_with?("auto:")
        scope
      else
        [node.id] + scope
      end

      children = node.children.map { |c| normalize_node(c, child_scope) }
      Node.new(id: node.id, type: node.type, props:, children:)
    end
    private_class_method :normalize_node

    def self.encode_value(value)
      case value
      when true, false, nil, Integer, Float, String
        value
      when Symbol
        value.to_s
      when Array
        value.map { |v| encode_value(v) }
      when Hash
        value.transform_keys(&:to_s).transform_values { |v| encode_value(v) }
      else
        value.to_s
      end
    end
    private_class_method :encode_value
  end
end
