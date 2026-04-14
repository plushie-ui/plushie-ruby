# frozen_string_literal: true

module Plushie
  module Tree
    # Tree diffing algorithm.
    #
    # Produces patch operations (replace_node, update_props, insert_child,
    # remove_child) per the wire protocol spec. Uses LIS-based (Longest
    # Increasing Subsequence) algorithm for minimal patches on reordered
    # children.
    module Diff
      # Diff two normalized trees.
      # @param old_tree [Node, nil]
      # @param new_tree [Node, nil]
      # @return [Array<Hash>] patch operations
      def self.diff(old_tree, new_tree)
        return [] if old_tree.nil? && new_tree.nil?

        if old_tree.nil?
          return [{"op" => "replace_node", "path" => [], "node" => Tree.node_to_wire(new_tree)}] if new_tree #: Node
          return []
        end

        return [{"op" => "replace_node", "path" => [], "node" => Tree.node_to_wire(Node.new(id: "root", type: "container"))}] if new_tree.nil?
        return [{"op" => "replace_node", "path" => [], "node" => Tree.node_to_wire(new_tree)}] if old_tree.id != new_tree.id

        diff_node(old_tree, new_tree, [])
      end

      # @api private
      def self.diff_node(old, new_node, path)
        if old.type != new_node.type
          return [{"op" => "replace_node", "path" => path, "node" => Tree.node_to_wire(new_node)}]
        end

        child_ops = diff_children(old.children, new_node.children, path)
        prop_ops = diff_props(old.props, new_node.props, path)
        prop_ops + child_ops
      end
      private_class_method :diff_node

      # @api private
      def self.diff_props(old_props, new_props, path)
        return [] if old_props == new_props

        # @type var changed: Hash[String, untyped]
        changed = {}

        new_props.each do |k, v|
          if old_props.key?(k)
            old_v = old_props[k]
            next if old_v == v
            next if id_keyed_lists_equal?(old_v, v)
          end
          changed[k.to_s] = v
        end

        old_props.each_key do |k|
          changed[k.to_s] = nil unless new_props.key?(k)
        end

        return [] if changed.empty?
        [{"op" => "update_props", "path" => path, "props" => Encode.encode_props(changed)}]
      end
      private_class_method :diff_props

      # @api private
      def self.diff_children(old_children, new_children, path)
        old_ids = old_children.map(&:id)
        new_ids = new_children.map(&:id)

        if old_ids == new_ids
          return old_children.each_with_index.flat_map { |old_child, idx|
            diff_node(old_child, new_children[idx], path + [idx])
          }
        end

        # @type var old_by_id: Hash[String, [Node, Integer]]
        old_by_id = {}
        old_children.each_with_index { |c, i| old_by_id[c.id] = [c, i] }
        # @type var new_by_id: Hash[String, [Node, Integer]]
        new_by_id = {}
        new_children.each_with_index { |c, i| new_by_id[c.id] = [c, i] }

        surviving_old_indices = new_ids.filter_map { |id| old_by_id[id]&.last }
        lis_set = lis_indices(surviving_old_indices)

        stable_old_ids = Set.new
        surviving_idx = 0
        new_ids.each do |id|
          next unless old_by_id.key?(id)
          stable_old_ids.add(id) if lis_set.include?(surviving_idx)
          surviving_idx += 1
        end

        # @type var removed_indices: Array[Integer]
        removed_indices = []
        old_children.each_with_index do |child, idx|
          removed_indices << idx unless new_by_id.key?(child.id) && stable_old_ids.include?(child.id)
        end

        remove_ops = removed_indices
          .sort.reverse
          .map { |idx| {"op" => "remove_child", "path" => path, "index" => idx} }

        # @type var update_ops: Array[Hash[String, untyped]]
        update_ops = []
        # @type var insert_ops: Array[Hash[String, untyped]]
        insert_ops = []

        new_children.each_with_index do |child, new_idx|
          if stable_old_ids.include?(child.id)
            old_child, old_idx = old_by_id[child.id]
            adjusted = index_after_removals(old_idx, removed_indices)
            update_ops.concat(diff_node(old_child, child, path + [adjusted]))
          else
            insert_ops << {"op" => "insert_child", "path" => path, "index" => new_idx,
                           "node" => Tree.node_to_wire(child)}
          end
        end

        remove_ops + update_ops + insert_ops
      end
      private_class_method :diff_children

      # Compute LIS indices. O(n log n) via patience sorting.
      # @api private
      def self.lis_indices(arr)
        return Set.new if arr.empty?

        # @type var tails: Array[Integer]
        tails = []
        # @type var positions: Array[Integer]
        positions = []
        predecessors = Array.new(arr.length, -1)

        arr.each_with_index do |val, i|
          lo, hi = 0, tails.length
          while lo < hi
            mid = (lo + hi) / 2
            if arr[positions[mid]] < val
              lo = mid + 1
            else
              hi = mid
            end
          end

          positions[lo] = i
          tails[lo] = val
          predecessors[i] = (lo > 0) ? positions[lo - 1] : -1
        end

        result = Set.new
        k = positions[tails.length - 1]
        while k >= 0
          result.add(k)
          k = predecessors[k]
        end
        result
      end
      private_class_method :lis_indices

      # @api private
      def self.index_after_removals(old_idx, removed_indices)
        lo, hi = 0, removed_indices.length
        while lo < hi
          mid = (lo + hi) / 2
          if removed_indices[mid] < old_idx
            lo = mid + 1
          else
            hi = mid
          end
        end
        old_idx - lo
      end
      private_class_method :index_after_removals

      # @api private
      def self.id_keyed_lists_equal?(old_val, new_val)
        return false unless old_val.is_a?(Array) && new_val.is_a?(Array)
        return false if old_val.length != new_val.length
        return false if old_val.empty?
        return false unless old_val.all? { |e| e.is_a?(Hash) && (e.key?(:id) || e.key?("id")) }
        return false unless new_val.all? { |e| e.is_a?(Hash) && (e.key?(:id) || e.key?("id")) }

        # @type var old_by_id: Hash[untyped, untyped]
        old_by_id = {}
        old_val.each { |e| old_by_id[e[:id] || e["id"]] = e }
        new_val.all? { |e| old_by_id[e[:id] || e["id"]] == e }
      end
      private_class_method :id_keyed_lists_equal?
    end
  end
end
