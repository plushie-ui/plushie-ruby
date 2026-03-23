# frozen_string_literal: true

module Plushie
  # Utilities for working with UI trees.
  #
  # Provides normalization, search, and diffing for Node trees.
  # The diff algorithm produces patch operations per the wire protocol
  # spec (replace_node, update_props, insert_child, remove_child).
  #
  # @see ~/projects/plushie/docs/protocol.md "Patch"
  module Tree
    # -------------------------------------------------------------------
    # Search
    # -------------------------------------------------------------------

    # Find a node by ID (depth-first).
    #
    # @param tree [Node, Array<Node>, nil]
    # @param id [String] node ID to find
    # @return [Node, nil]
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
    #
    # @param tree [Node, Array<Node>, nil]
    # @param id [String]
    # @return [Boolean]
    def self.exists?(tree, id)
      !find(tree, id).nil?
    end

    # Return all node IDs in depth-first order.
    #
    # @param tree [Node, Array<Node>]
    # @return [Array<String>]
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
    #
    # @param tree [Node, Array<Node>]
    # @yield [Node] predicate block
    # @return [Array<Node>]
    def self.find_all(tree, &predicate)
      result = []
      trees = tree.is_a?(Array) ? tree : [tree]

      trees.each do |node|
        result << node if predicate.call(node)
        result.concat(find_all(node.children, &predicate))
      end

      result
    end

    # -------------------------------------------------------------------
    # Normalization
    # -------------------------------------------------------------------

    # Normalize a tree for wire transport.
    # Converts symbol prop values to strings via Encode, resolves
    # scoped IDs, and validates tree structure.
    #
    # @param tree [Node, Array<Node>]
    # @return [Array<Node>] normalized tree (always an array)
    def self.normalize(tree)
      return [Node.new(id: "root", type: "container")] if tree.nil?
      trees = tree.is_a?(Array) ? tree : [tree]
      trees.compact.map { |node| normalize_node(node, "") }
    end

    # -------------------------------------------------------------------
    # Diffing
    # -------------------------------------------------------------------

    # Diff two normalized trees, producing an array of patch operations.
    #
    # Each op is a Hash with string keys matching the wire protocol:
    #   { "op" => "replace_node", "path" => [...], "node" => {...} }
    #   { "op" => "update_props", "path" => [...], "props" => {...} }
    #   { "op" => "insert_child", "path" => [...], "index" => n, "node" => {...} }
    #   { "op" => "remove_child", "path" => [...], "index" => n }
    #
    # @param old_tree [Node, nil] previous normalized tree
    # @param new_tree [Node, nil] current normalized tree
    # @return [Array<Hash>] patch operations
    def self.diff(old_tree, new_tree)
      return [] if old_tree.nil? && new_tree.nil?
      return [{"op" => "replace_node", "path" => [], "node" => node_to_wire(new_tree)}] if old_tree.nil?
      return [{"op" => "remove_child", "path" => [], "index" => 0}] if new_tree.nil?
      return [{"op" => "replace_node", "path" => [], "node" => node_to_wire(new_tree)}] if old_tree.id != new_tree.id

      diff_node(old_tree, new_tree, [])
    end

    # Convert a Node to a plain wire-ready Hash (recursive).
    #
    # @param node [Node]
    # @return [Hash]
    def self.node_to_wire(node)
      {
        "id" => node.id,
        "type" => node.type,
        "props" => encode_props(node.props),
        "children" => node.children.map { |c| node_to_wire(c) }
      }
    end

    # -------------------------------------------------------------------
    # Private implementation
    # -------------------------------------------------------------------

    def self.normalize_node(node, scope)
      # Compute scoped ID
      scoped_id = if scope.empty? || node.type == "window" || node.id.start_with?("auto:")
        node.id
      else
        "#{scope}/#{node.id}"
      end

      props = node.props.transform_values { |v| encode_value(v) }

      # Propagate scope: named (non-auto, non-window) containers create scope
      child_scope = if node.type == "window" || node.id.start_with?("auto:")
        scope
      else
        scoped_id
      end

      # Resolve a11y ID references relative to current scope
      if props.key?("a11y") || props.key?(:a11y)
        a11y = props["a11y"] || props[:a11y]
        if a11y.is_a?(Hash)
          %w[labelled_by described_by error_message].each do |ref_key|
            ref = a11y[ref_key] || a11y[ref_key.to_sym]
            if ref.is_a?(String) && !ref.include?("/") && !scope.empty?
              a11y = a11y.merge(ref_key => "#{scope}/#{ref}")
            end
          end
          props = props.merge("a11y" => a11y)
        end
      end

      # Detect canvas shape structs leaked into the widget tree
      node.children.each do |child|
        if child.respond_to?(:to_wire) && !child.is_a?(Plushie::Node)
          raise ArgumentError, "Canvas shape #{child.class} found in widget tree. " \
            "Shapes belong inside canvas/layer/group blocks, not as widget children."
        end
      end

      children = node.children.map { |c| normalize_node(c, child_scope) }
      Node.new(id: scoped_id, type: node.type, props: props, children: children)
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
        if value.respond_to?(:to_wire)
          encode_value(value.to_wire)
        else
          value.to_s
        end
      end
    end
    private_class_method :encode_value

    def self.encode_props(props)
      props.each_with_object({}) do |(k, v), h|
        h[k.to_s] = encode_value(v)
      end
    end
    private_class_method :encode_props

    # -- Diff internals ----------------------------------------------------

    def self.diff_node(old, new, path)
      # Different type -> replace entire node
      if old.type != new.type
        return [{"op" => "replace_node", "path" => path, "node" => node_to_wire(new)}]
      end

      # Check children first (reorder detection may produce a full replace)
      child_result = diff_children(old.children, new.children, path)
      if child_result == :reordered
        return [{"op" => "replace_node", "path" => path, "node" => node_to_wire(new)}]
      end

      prop_ops = diff_props(old.props, new.props, path)
      prop_ops + child_result
    end
    private_class_method :diff_node

    def self.diff_props(old_props, new_props, path)
      return [] if old_props == new_props

      changed = {}

      # Changed or added keys
      new_props.each do |k, v|
        changed[k] = v unless old_props.key?(k) && old_props[k] == v
      end

      # Removed keys -> nil
      old_props.each_key do |k|
        changed[k] = nil unless new_props.key?(k)
      end

      return [] if changed.empty?
      [{"op" => "update_props", "path" => path, "props" => encode_props(changed)}]
    end
    private_class_method :diff_props

    def self.diff_children(old_children, new_children, path)
      old_by_id = {}
      old_children.each_with_index { |c, i| old_by_id[c.id] = [c, i] }
      new_by_id = {}
      new_children.each_with_index { |c, i| new_by_id[c.id] = [c, i] }

      # Reorder detection: compare sequence of IDs that appear in both
      # old and new. If the relative order changed, fall back to
      # replace_node for the parent. This is O(n), not LCS.
      common_old = old_children.map(&:id).select { |id| new_by_id.key?(id) }
      common_new = new_children.map(&:id).select { |id| old_by_id.key?(id) }
      return :reordered if common_old != common_new

      # Removals: old IDs not in new, highest index first
      removed_indices = old_by_id
        .reject { |id, _| new_by_id.key?(id) }
        .map { |_, (_, idx)| idx }

      remove_ops = removed_indices
        .sort.reverse
        .map { |idx| {"op" => "remove_child", "path" => path, "index" => idx} }

      # Walk new children for updates and inserts
      update_ops = []
      insert_ops = []

      new_children.each_with_index do |child, idx|
        if (entry = old_by_id[child.id])
          old_child, old_idx = entry
          # Adjust old index for removals that happened before it
          adjusted = index_after_removals(old_idx, removed_indices)
          child_path = path + [adjusted]
          update_ops.concat(diff_node(old_child, child, child_path))
        else
          insert_ops << {"op" => "insert_child", "path" => path, "index" => idx,
                         "node" => node_to_wire(child)}
        end
      end

      # Protocol-mandated order: removals, then updates, then inserts
      remove_ops + update_ops + insert_ops
    end
    private_class_method :diff_children

    def self.index_after_removals(old_idx, removed_indices)
      old_idx - removed_indices.count { |ri| ri < old_idx }
    end
    private_class_method :index_after_removals
  end
end
