# frozen_string_literal: true

module Plushie
  # Utilities for working with UI trees.
  #
  # Provides normalization, search, and diffing for Node trees.
  # The diff algorithm produces patch operations per the wire protocol
  # spec (replace_node, update_props, insert_child, remove_child).
  #
  # @see ~/projects/plushie-renderer/docs/protocol.md "Patch"
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
      return [] if tree.nil?

      # @type var result: Array[String]
      result = []
      trees = (tree.is_a?(Array) ? tree : [tree]).compact

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
      return [] if tree.nil?

      # @type var result: Array[Node]
      result = []
      trees = (tree.is_a?(Array) ? tree : [tree]).compact

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
    # When a canvas widget registry is provided, canvas widget
    # placeholders are detected and rendered with stored state.
    #
    # @param tree [Node, Array<Node>]
    # @param registry [Hash, nil] canvas widget registry for state lookup
    # @return [Array<Node>] normalized tree (always an array)
    def self.normalize(tree, registry: nil)
      return [Node.new(id: "root", type: "container")] if tree.nil?
      trees = (tree.is_a?(Array) ? tree : [tree]).compact
      normalized = trees.compact.map { |node| normalize_node(node, "", registry, nil) }
      check_duplicate_ids!(normalized)
      normalized
    end

    # Normalize a top-level app view and require explicit windows.
    #
    # @param tree [Node, Array<Node>, nil]
    # @param registry [Hash, nil]
    # @return [Node] normalized synthetic root or window node
    def self.normalize_view(tree, registry: nil)
      windows = normalize(tree, registry: registry)

      if windows.empty? || !windows.all? { |node| node.type == "window" }
        raise ArgumentError, "view must return a window node or an array of window nodes"
      end

      Node.new(id: "root", type: "root", children: windows)
    end

    # -------------------------------------------------------------------
    # Diffing
    # -------------------------------------------------------------------

    # Diff two normalized trees, producing an array of patch operations.
    #
    # Each op is a Hash with string keys matching the wire protocol:
    #   `{ "op" => "replace_node", "path" => [...], "node" => {...} }`
    #   `{ "op" => "update_props", "path" => [...], "props" => {...} }`
    #   `{ "op" => "insert_child", "path" => [...], "index" => n, "node" => {...} }`
    #   `{ "op" => "remove_child", "path" => [...], "index" => n }`
    #
    # @param old_tree [Node, nil] previous normalized tree
    # @param new_tree [Node, nil] current normalized tree
    # @return [Array<Hash>] patch operations
    def self.diff(old_tree, new_tree)
      return [] if old_tree.nil? && new_tree.nil?
      return [{"op" => "replace_node", "path" => [], "node" => node_to_wire(new_tree)}] if old_tree.nil? && !new_tree.nil?
      return [{"op" => "replace_node", "path" => [], "node" => node_to_wire(Node.new(id: "root", type: "container"))}] if new_tree.nil?
      old_node = old_tree or raise ArgumentError, "old_tree cannot be nil here"
      new_node = new_tree or raise ArgumentError, "new_tree cannot be nil here"
      return [{"op" => "replace_node", "path" => [], "node" => node_to_wire(new_node)}] if old_node.id != new_node.id

      diff_node(old_node, new_node, [])
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

    def self.normalize_node(node, scope, registry, window_id)
      # Compute scoped ID
      scoped_id = if scope.empty? || node.type == "window" || node.id.start_with?("auto:")
        node.id
      else
        "#{scope}/#{node.id}"
      end
      current_window_id = (node.type == "window") ? node.id : window_id

      # Canvas widget rendering: if this node is a canvas_widget placeholder
      # (tagged in meta), render it with the best available state and
      # normalize the output. The rendered canvas node does NOT have the
      # placeholder meta, so normalization of the output won't re-trigger
      # rendering (no recursion possible).
      if registry && defined?(Plushie::CanvasWidget) && Plushie::CanvasWidget.placeholder?(node)
        result = Plushie::CanvasWidget.render_placeholder(
          node, current_window_id, scoped_id, node.id, registry
        )
        if result
          rendered_node, _entry = result
          # Normalize the rendered output. Pass empty scope because the
          # rendered node's ID is already fully scoped (set by
          # render_placeholder). Passing the parent scope would double-scope.
          normalized = normalize_node(rendered_node, "", registry, current_window_id)
          return normalized.with(meta: rendered_node.meta)
        end
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

      children = node.children.map { |c| normalize_node(c, child_scope, registry, current_window_id) }
      check_duplicate_ids!(children)
      Node.new(id: scoped_id, type: node.type, props: props, children: children)
    end
    private_class_method :normalize_node

    def self.check_duplicate_ids!(children)
      # @type var seen: Hash[String, bool]
      seen = {}
      # @type var duplicates: Array[String]
      duplicates = []

      children.each do |child|
        if seen[child.id]
          duplicates << child.id
        else
          seen[child.id] = true
        end
      end

      return if duplicates.empty?

      raise ArgumentError, "duplicate sibling IDs detected during normalize: #{duplicates.uniq.map(&:inspect).join(", ")}"
    end
    private_class_method :check_duplicate_ids!

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
      # @type var encoded: Hash[String, untyped]
      encoded = {}
      props.each_with_object(encoded) do |(k, v), h|
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

      child_ops = case child_result
      when Array
        child_result
      else
        raise "unexpected diff result"
      end

      prop_ops = diff_props(old.props, new.props, path)
      prop_ops + child_ops
    end
    private_class_method :diff_node

    def self.diff_props(old_props, new_props, path)
      return [] if old_props == new_props

      # @type var changed: Hash[String, untyped]
      changed = {}

      # Changed or added keys
      new_props.each do |k, v|
        changed[k.to_s] = v unless old_props.key?(k) && old_props[k] == v
      end

      # Removed keys -> nil
      old_props.each_key do |k|
        changed[k.to_s] = nil unless new_props.key?(k)
      end

      return [] if changed.empty?
      [{"op" => "update_props", "path" => path, "props" => encode_props(changed)}]
    end
    private_class_method :diff_props

    def self.diff_children(old_children, new_children, path)
      # @type var old_by_id: Hash[String, [Node, Integer]]
      old_by_id = {}
      old_children.each_with_index { |c, i| old_by_id[c.id] = [c, i] }
      # @type var new_by_id: Hash[String, [Node, Integer]]
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
      # @type var update_ops: Array[Hash[String, untyped]]
      update_ops = []
      # @type var insert_ops: Array[Hash[String, untyped]]
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
