# frozen_string_literal: true

module Plushie
  # Utilities for working with UI trees.
  #
  # Provides normalization, search, and diffing for Node trees.
  # The diff algorithm produces patch operations per the wire protocol
  # spec (replace_node, update_props, insert_child, remove_child).
  #
  # @see ~/projects/plushie-rust/docs/protocol.md "Patch"
  module Tree
    # -------------------------------------------------------------------
    # Search
    # -------------------------------------------------------------------

    # Find a node by ID (depth-first).
    #
    # Supports both fully-qualified IDs ("main#form/email") and local
    # names ("email"). Local names match by suffix: a search for "email"
    # matches "main#form/email". The "#" or "/" before the local segment
    # is required for suffix matching (prevents "remail" from matching).
    #
    # @param tree [Node, Array<Node>, nil]
    # @param id [String] node ID to find
    # @return [Node, nil]
    def self.find(tree, id)
      return nil if tree.nil?
      trees = tree.is_a?(Array) ? tree : [tree]

      # If the search ID contains "#", it includes the window qualifier and
      # requires an exact match. Otherwise, match by suffix: the node.id
      # must equal the search ID or end with "#id" or "/id" at a boundary.
      # This allows "email" to match "main#form/email" and "form/email"
      # to match "main#form/email".
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

    # Check if a node ID matches a search string.
    # Matches exact, or at a "#" or "/" boundary.
    # @api private
    def self.id_matches?(node_id, search)
      return true if node_id == search
      node_id.end_with?("##{search}", "/#{search}")
    end
    private_class_method :id_matches?

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

    # Find the first node matching a predicate (depth-first).
    # Returns immediately on the first match.
    #
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
    # Maximum tree depth before raising. Protects against infinite
    # recursion from circular widget compositions.
    MAX_DEPTH = 256
    DEPTH_WARNING = 200

    def self.normalize(tree, registry: nil)
      return [Node.new(id: "root", type: "container")] if tree.nil?
      trees = (tree.is_a?(Array) ? tree : [tree]).compact
      normalized = trees.compact.map { |node| normalize_node(node, "", registry, nil, 0) }
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

    def self.normalize_node(node, scope, registry, window_id, depth = 0)
      if depth >= MAX_DEPTH
        raise ArgumentError,
          "tree depth exceeds #{MAX_DEPTH}. This usually means a widget " \
          "is composing itself recursively. Check widget view methods for cycles."
      end

      if depth == DEPTH_WARNING
        warn "plushie: tree depth reached #{DEPTH_WARNING}, approaching limit of #{MAX_DEPTH}"
      end

      # Handle memo nodes: check cache, evaluate block if miss
      if node.type == "__memo__" && node.meta
        return normalize_memo(node, scope, registry, window_id, depth)
      end

      # Validate user-provided IDs (non-auto)
      validate_user_id!(node.id) unless node.id.start_with?("auto:")

      # Compute scoped ID. Window nodes keep bare IDs. Children of windows
      # get "window#id". Deeper descendants get "window#parent/id".
      # The # only appears at the window boundary; / separates deeper scope.
      scoped_id = if node.id.start_with?("auto:")
        node.id
      elsif scope.empty?
        node.id
      elsif scope.end_with?("#")
        "#{scope}#{node.id}"
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
          normalized = normalize_node(rendered_node, "", registry, current_window_id, depth + 1)
          return normalized.with(meta: rendered_node.meta)
        end
      end

      props = node.props.transform_values { |v| encode_value(v) }

      # Determine scope for children: window nodes set "window#" as the
      # child scope. Named non-window nodes propagate their scoped ID.
      # Auto-ID nodes are transparent (don't create scope boundaries).
      child_scope = if node.type == "window"
        "#{scoped_id}#"
      elsif node.id.start_with?("auto:")
        scope
      else
        scoped_id
      end

      # Resolve a11y ID references relative to current scope.
      # Uses the same separator logic as scoped_id: "#" at window
      # boundary, "/" for deeper scope.
      if props.key?("a11y") || props.key?(:a11y)
        a11y = props["a11y"] || props[:a11y]
        if a11y.is_a?(Hash)
          %w[labelled_by described_by error_message].each do |ref_key|
            ref = a11y[ref_key] || a11y[ref_key.to_sym]
            if ref.is_a?(String) && !ref.include?("/") && !ref.include?("#") && !scope.empty?
              separator = scope.end_with?("#") ? "" : "/"
              a11y = a11y.merge(ref_key => "#{scope}#{separator}#{ref}")
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

      children = node.children.map { |c| normalize_node(c, child_scope, registry, current_window_id, depth + 1) }
      check_duplicate_ids!(children)
      children = infer_radio_groups(children)
      Node.new(id: scoped_id, type: node.type, props: props, children: children)
    end
    private_class_method :normalize_node

    # Scan normalized children for radio widgets sharing a group prop and
    # inject position_in_set / size_of_set into their a11y props. Respects
    # manual overrides: if position_in_set is already set, the node is left
    # untouched (but still counted toward size_of_set for siblings).
    def self.infer_radio_groups(children)
      # Group radio nodes by their group prop
      # @type var groups: Hash[String, Array[[Node, Integer]]]
      groups = {}
      children.each_with_index do |node, idx|
        next unless node.type == "radio"
        group = node.props[:group] || node.props["group"]
        next unless group.is_a?(String)
        (groups[group] ||= []) << [node, idx]
      end

      return children if groups.empty?

      # @type var patches: Hash[Integer, Hash[String, untyped]]
      patches = {}
      groups.each_value do |members|
        size = members.length
        members.each_with_index do |(node, child_idx), pos|
          a11y = node.props[:a11y] || node.props["a11y"] || {}
          a11y = a11y.dup if a11y.frozen?

          has_position = a11y[:position_in_set] || a11y["position_in_set"]
          has_size = a11y[:size_of_set] || a11y["size_of_set"]

          next if has_position && has_size

          a11y[:size_of_set] = size unless has_size
          a11y[:position_in_set] = pos + 1 unless has_position
          patches[child_idx] = a11y
        end
      end

      return children if patches.empty?

      children.each_with_index.map do |node, idx|
        if (a11y = patches[idx])
          node.with(props: node.props.merge(a11y: a11y))
        else
          node
        end
      end
    end
    private_class_method :infer_radio_groups

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

      msg = "duplicate sibling IDs detected during normalize: #{duplicates.uniq.map(&:inspect).join(", ")}"
      if duplicates.any? { |id| id.start_with?("auto:") }
        msg += ". For items in dynamic lists, provide explicit IDs instead of relying on auto-generated ones"
      end
      raise ArgumentError, msg
    end
    private_class_method :check_duplicate_ids!

    # Handle a __memo__ node during normalization.
    # Checks the memo cache; on hit returns the cached subtree,
    # on miss evaluates the block and caches the result.
    def self.normalize_memo(node, scope, registry, window_id, depth)
      deps = node.meta[:__memo_deps__]
      block = node.meta[:__memo_block__]
      cache_key = [node.id, scope, window_id, deps]

      prev_cache = UI::MemoCache.prev
      cached = prev_cache[cache_key]

      if cached
        # Cache hit: reuse previous normalized subtree
        UI::MemoCache.store(cache_key, cached)
        cached
      else
        # Cache miss: evaluate the block, normalize, cache
        # @type var children: Array[Node]
        children = []
        UI::Context.push(children)
        begin
          block.call
        ensure
          UI::Context.pop
        end

        # Normalize the memo body. If the block produced a single child,
        # normalize it directly. If multiple, wrap in a transparent container.
        # Use auto: prefix for wrapper IDs to bypass user ID validation.
        result = if children.length == 1
          normalize_node(children[0], scope, registry, window_id, depth + 1)
        elsif children.length > 1
          wrapper_id = "auto:memo_#{children.length}"
          wrapper = Node.new(id: wrapper_id, type: "container", children: children)
          normalize_node(wrapper, scope, registry, window_id, depth + 1)
        else
          Node.new(id: "auto:memo_empty", type: "container")
        end

        UI::MemoCache.store(cache_key, result)
        result
      end
    end
    private_class_method :normalize_memo

    # Printable ASCII range (0x21-0x7E), excludes space and control characters.
    VALID_ID_PATTERN = /\A[\x21-\x7e]+\z/

    # Validate a user-provided widget ID.
    # - Must not be empty
    # - Must not contain "/" (scope separators are built automatically)
    # - Must not contain "#" (reserved for window-qualified paths)
    # - Must not exceed 1024 bytes
    # - Must contain only printable ASCII (0x21-0x7E)
    def self.validate_user_id!(id)
      return if id.nil? || id.empty?

      if id.include?("/")
        raise ArgumentError,
          "widget ID #{id.inspect} cannot contain \"/\", " \
          "scoped paths are built automatically by named containers"
      end

      if id.include?("#")
        raise ArgumentError,
          "widget ID #{id.inspect} cannot contain \"#\", " \
          "\"#\" is reserved for window-qualified paths (e.g., \"window#widget\")"
      end

      if id.bytesize > 1024
        raise ArgumentError,
          "widget ID #{id.inspect} exceeds maximum length of 1024 bytes"
      end

      unless VALID_ID_PATTERN.match?(id)
        raise ArgumentError,
          "widget ID #{id.inspect} contains invalid characters, " \
          "IDs must contain only printable ASCII (0x21-0x7E)"
      end
    end
    private_class_method :validate_user_id!

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

    # Compare two list-valued props by element ID instead of structural equality.
    # Returns true if both are Arrays, all elements have an :id or "id" key,
    # and the ID-keyed content is equivalent.
    # @api private
    def self.id_keyed_lists_equal?(old_val, new_val)
      return false unless old_val.is_a?(Array) && new_val.is_a?(Array)
      return false if old_val.length != new_val.length
      return false if old_val.empty?

      # Check that all elements are Hashes with an :id key
      return false unless old_val.all? { |e| e.is_a?(Hash) && (e.key?(:id) || e.key?("id")) }
      return false unless new_val.all? { |e| e.is_a?(Hash) && (e.key?(:id) || e.key?("id")) }

      # Build ID-keyed lookup and compare
      # @type var old_by_id: Hash[untyped, untyped]
      old_by_id = {}
      old_val.each { |e| old_by_id[e[:id] || e["id"]] = e }
      new_val.all? { |e| old_by_id[e[:id] || e["id"]] == e }
    end
    private_class_method :id_keyed_lists_equal?

    # -- Diff internals ----------------------------------------------------

    def self.diff_node(old, new, path)
      # Different type -> replace entire node
      if old.type != new.type
        return [{"op" => "replace_node", "path" => path, "node" => node_to_wire(new)}]
      end

      child_ops = diff_children(old.children, new.children, path)
      prop_ops = diff_props(old.props, new.props, path)
      prop_ops + child_ops
    end
    private_class_method :diff_node

    def self.diff_props(old_props, new_props, path)
      return [] if old_props == new_props

      # @type var changed: Hash[String, untyped]
      changed = {}

      # Changed or added keys.
      # For list-valued props where every element has an :id, compare
      # by ID to avoid sending the full list when content is unchanged
      # (common for canvas shape lists that are rebuilt each render).
      new_props.each do |k, v|
        if old_props.key?(k)
          old_v = old_props[k]
          next if old_v == v
          next if id_keyed_lists_equal?(old_v, v)
        end
        changed[k.to_s] = v
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
      old_ids = old_children.map(&:id)
      new_ids = new_children.map(&:id)

      # Fast path: identical ID sequence -> pairwise prop diff only
      if old_ids == new_ids
        return old_children.each_with_index.flat_map { |old_child, idx|
          diff_node(old_child, new_children[idx], path + [idx])
        }
      end

      # Build lookup maps
      # @type var old_by_id: Hash[String, [Node, Integer]]
      old_by_id = {}
      old_children.each_with_index { |c, i| old_by_id[c.id] = [c, i] }
      # @type var new_by_id: Hash[String, [Node, Integer]]
      new_by_id = {}
      new_children.each_with_index { |c, i| new_by_id[c.id] = [c, i] }

      # Map old positions of surviving nodes to their new positions
      # for LIS computation
      surviving_old_indices = new_ids.filter_map { |id|
        old_by_id[id]&.last
      }

      # Compute LIS: elements in the longest increasing subsequence of
      # old indices maintain their relative order and don't need to move.
      lis_set = lis_indices(surviving_old_indices)

      # Build the set of old IDs that are in the LIS (don't need to move)
      stable_old_ids = Set.new
      surviving_idx = 0
      new_ids.each do |id|
        next unless old_by_id.key?(id)
        stable_old_ids.add(id) if lis_set.include?(surviving_idx)
        surviving_idx += 1
      end

      # Remove nodes not in new, and nodes not in the LIS (they'll be re-inserted)
      # @type var removed_indices: Array[Integer]
      removed_indices = []
      old_children.each_with_index do |child, idx|
        removed_indices << idx unless new_by_id.key?(child.id) && stable_old_ids.include?(child.id)
      end

      remove_ops = removed_indices
        .sort.reverse
        .map { |idx| {"op" => "remove_child", "path" => path, "index" => idx} }

      # Walk new children: update stable nodes in place, insert moved/new nodes
      # @type var update_ops: Array[Hash[String, untyped]]
      update_ops = []
      # @type var insert_ops: Array[Hash[String, untyped]]
      insert_ops = []

      new_children.each_with_index do |child, new_idx|
        if stable_old_ids.include?(child.id)
          # Stable node: diff in place
          old_child, old_idx = old_by_id[child.id]
          adjusted = index_after_removals(old_idx, removed_indices)
          update_ops.concat(diff_node(old_child, child, path + [adjusted]))
        else
          # Moved or new node: insert at the correct position
          insert_ops << {"op" => "insert_child", "path" => path, "index" => new_idx,
                         "node" => node_to_wire(child)}
        end
      end

      remove_ops + update_ops + insert_ops
    end
    private_class_method :diff_children

    # Compute the indices of the Longest Increasing Subsequence.
    # Returns a Set of indices into the input array.
    # O(n log n) using patience sorting.
    def self.lis_indices(arr)
      return Set.new if arr.empty?

      # tails[i] = smallest tail element for IS of length i+1
      # @type var tails: Array[Integer]
      tails = []
      # predecessors and positions for backtracking
      # @type var positions: Array[Integer]
      positions = []
      predecessors = Array.new(arr.length, -1)

      arr.each_with_index do |val, i|
        # Binary search for the leftmost tail >= val
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

      # Backtrack to recover the LIS indices
      result = Set.new
      k = positions[tails.length - 1]
      while k >= 0
        result.add(k)
        k = predecessors[k]
      end
      result
    end
    private_class_method :lis_indices

    # Count how many removed indices are below old_idx using binary search.
    # Assumes removed_indices is already sorted ascending (built from
    # ascending iteration over old_children).
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
  end
end
