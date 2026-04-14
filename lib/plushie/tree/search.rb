# frozen_string_literal: true

module Plushie
  module Tree
    # Tree search and query functions.
    #
    # All methods accept a Node or Array of Nodes as the tree root.
    # Search is depth-first.
    module Search
      # Find a node by ID (depth-first).
      #
      # Supports both fully-qualified IDs ("main#form/email") and local
      # names ("email"). Local names match by suffix: a search for "email"
      # matches "main#form/email".
      #
      # @param tree [Node, Array<Node>, nil]
      # @param id [String] node ID to find
      # @return [Node, nil]
      def self.find(tree, id)
        return nil if tree.nil?
        trees = tree.is_a?(Array) ? tree : [tree]
        exact = id.include?("#")

        trees.each do |node|
          if exact
            return node if node.id == id
          elsif id_matches?(node.id, id)
            return node
          end
          found = find(node.children, id)
          return found if found
        end

        nil
      end

      # Check if a node with the given ID exists.
      # @param tree [Node, Array<Node>, nil]
      # @param id [String]
      # @return [Boolean]
      def self.exists?(tree, id)
        !find(tree, id).nil?
      end

      # Return all node IDs in depth-first order.
      # @param tree [Node, Array<Node>]
      # @return [Array<String>]
      def self.ids(tree)
        return [] if tree.nil?
        result = [] #: Array[String]
        trees = (tree.is_a?(Array) ? tree : [tree]).compact
        trees.each do |node|
          result << node.id
          result.concat(ids(node.children))
        end
        result
      end

      # Find the first node matching a predicate (depth-first).
      # @param tree [Node, Array<Node>]
      # @yield [Node] predicate block
      # @return [Node, nil]
      def self.find_first(tree, &predicate)
        return nil if tree.nil?
        trees = (tree.is_a?(Array) ? tree : [tree]).compact
        trees.each do |node|
          return node if predicate.call(node)
          found = find_first(node.children, &predicate)
          return found if found
        end
        nil
      end

      # Find all nodes matching a predicate (depth-first).
      # @param tree [Node, Array<Node>]
      # @yield [Node] predicate block
      # @return [Array<Node>]
      def self.find_all(tree, &predicate)
        return [] if tree.nil?
        result = [] #: Array[Node]
        trees = (tree.is_a?(Array) ? tree : [tree]).compact
        trees.each do |node|
          result << node if predicate.call(node)
          result.concat(find_all(node.children, &predicate))
        end
        result
      end

      # Check if a node ID matches a search string at a boundary.
      # @api private
      def self.id_matches?(node_id, search)
        return true if node_id == search
        node_id.end_with?("##{search}", "/#{search}")
      end
      private_class_method :id_matches?
    end
  end
end
