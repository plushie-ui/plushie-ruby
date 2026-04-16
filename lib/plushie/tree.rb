# frozen_string_literal: true

require_relative 'tree/search'
require_relative 'tree/diff'

module Plushie
  # Utilities for working with UI trees.
  #
  # Provides normalization (Tree), search (Tree::Search), and diffing
  # (Tree::Diff) for Node trees. Search and diff are also available
  # directly on Tree via delegation.
  #
  # @see ~/projects/plushie-rust/docs/protocol.md "Patch"
  module Tree
    # -------------------------------------------------------------------
    # Search (delegated to Tree::Search)
    # -------------------------------------------------------------------

    # @see Tree::Search#find
    def self.find(tree, id) = Search.find(tree, id)
    # @see Tree::Search#exists?
    def self.exists?(tree, id) = Search.exists?(tree, id)
    # @see Tree::Search#ids
    def self.ids(tree) = Search.ids(tree)
    # @see Tree::Search#find_first
    def self.find_first(tree, &predicate) = Search.find_first(tree, &predicate)
    # @see Tree::Search#find_all
    def self.find_all(tree, &predicate) = Search.find_all(tree, &predicate)

    # -------------------------------------------------------------------
    # Normalization
    # -------------------------------------------------------------------

    # Maximum tree depth before raising. Protects against infinite
    # recursion from circular widget compositions.
    MAX_DEPTH = 256
    # Depth at which a warning is emitted (approaching MAX_DEPTH).
    DEPTH_WARNING = 200

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
      return [Node.new(id: 'root', type: 'container')] if tree.nil?

      trees = (tree.is_a?(Array) ? tree : [tree]).compact
      normalized = trees.map { |node| normalize_node(node, '', registry, nil, 0) }
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

      if windows.empty? || !windows.all? { |node| node.type == 'window' }
        raise ArgumentError, 'view must return a window node or an array of window nodes'
      end

      Node.new(id: 'root', type: 'root', children: windows)
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
    def self.diff(old_tree, new_tree) = Diff.diff(old_tree, new_tree)

    # Convert a Node to a plain wire-ready Hash (recursive).
    #
    # @param node [Node]
    # @return [Hash]
    def self.node_to_wire(node)
      {
        'id' => node.id,
        'type' => node.type,
        'props' => Encode.encode_props(node.props),
        'children' => node.children.map { |c| node_to_wire(c) }
      }
    end

    # -------------------------------------------------------------------
    # Private implementation
    # -------------------------------------------------------------------

    def self.normalize_node(node, scope, registry, window_id, depth = 0)
      if depth >= MAX_DEPTH
        raise ArgumentError,
              "tree depth exceeds #{MAX_DEPTH}. This usually means a widget " \
              'is composing itself recursively. Check widget view methods for cycles.'
      end

      warn "plushie: tree depth reached #{DEPTH_WARNING}, approaching limit of #{MAX_DEPTH}" if depth == DEPTH_WARNING

      # Handle memo nodes: check cache, evaluate block if miss
      return normalize_memo(node, scope, registry, window_id, depth) if node.type == '__memo__' && node.meta

      # Validate user-provided IDs (non-auto, non-prescoped).
      # IDs containing "#" are already scoped (from render_placeholder)
      # and should not be validated as user-provided IDs.
      validate_user_id!(node.id) unless node.id.start_with?('auto:') || node.id.include?('#')

      # Compute scoped ID. Window nodes keep bare IDs. Children of windows
      # get "window#id". Deeper descendants get "window#parent/id".
      # The # only appears at the window boundary; / separates deeper scope.
      scoped_id = if node.id.start_with?('auto:')
                    node.id
                  elsif scope.empty?
                    node.id
                  elsif scope.end_with?('#')
                    "#{scope}#{node.id}"
                  else
                    "#{scope}/#{node.id}"
                  end
      current_window_id = node.type == 'window' ? node.id : window_id

      # Canvas widget rendering: if this node is a canvas_widget placeholder
      # (tagged in meta), render it with the best available state and
      # normalize the output. The rendered canvas node does NOT have the
      # placeholder meta, so normalization of the output won't re-trigger
      # rendering (no recursion possible).
      if registry && current_window_id && defined?(Plushie::CanvasWidget) && Plushie::CanvasWidget.placeholder?(node)
        # Check widget cache_key before rendering. If the key matches
        # the previous render, skip view entirely and reuse the cached
        # normalized output.
        widget_module = node.meta[Plushie::CanvasWidget::META_KEY]
        # @type var cache_key_fn: Proc?
        cache_key_fn = widget_module.respond_to?(:cache_key_fn) ? widget_module.cache_key_fn : nil
        if cache_key_fn
          # @type var ck_fn: Proc
          ck_fn = cache_key_fn
          widget_props = node.meta[Plushie::CanvasWidget::PROPS_KEY] || {}
          widget_state = registry[scoped_id]&.state
          current_key = ck_fn.call(widget_props, widget_state || {})
          wck = [:widget_cache, scoped_id, current_key]
          cached = UI::MemoCache.prev[wck]
          if cached
            UI::MemoCache.store(wck, cached)
            return cached
          end
        end

        result = Plushie::CanvasWidget.render_placeholder(
          node, current_window_id, scoped_id, node.id, registry
        )
        if result
          rendered_node, entry = result
          # Strip the placeholder meta before normalizing so the
          # recursive normalize_node call doesn't re-trigger rendering.
          # Re-attach the meta after normalization for registry derivation.
          stripped = rendered_node.with(meta: nil)
          normalized = normalize_node(stripped, '', registry, current_window_id, depth + 1)
          final = normalized.with(meta: rendered_node.meta)

          # Store in widget cache if cache_key is declared
          if ck_fn
            widget_props = node.meta[Plushie::CanvasWidget::PROPS_KEY] || {}
            widget_state = entry&.state || {}
            current_key = ck_fn.call(widget_props, widget_state)
            UI::MemoCache.store([:widget_cache, scoped_id, current_key], final)
          end

          return final
        end
      end

      props = node.props.transform_values { |v| Encode.encode_value(v) }

      # Determine scope for children: window nodes set "window#" as the
      # child scope. Named non-window nodes propagate their scoped ID.
      # Auto-ID nodes are transparent (don't create scope boundaries).
      child_scope = if node.type == 'window'
                      "#{scoped_id}#"
                    elsif node.id.start_with?('auto:')
                      scope
                    else
                      scoped_id
                    end

      # Resolve a11y ID references relative to current scope.
      # Uses the same separator logic as scoped_id: "#" at window
      # boundary, "/" for deeper scope.
      if props.key?('a11y') || props.key?(:a11y)
        a11y = props['a11y'] || props[:a11y]
        if a11y.is_a?(Hash)
          %w[labelled_by described_by error_message].each do |ref_key|
            ref = a11y[ref_key] || a11y[ref_key.to_sym]
            if ref.is_a?(String) && !ref.include?('/') && !ref.include?('#') && !scope.empty?
              separator = scope.end_with?('#') ? '' : '/'
              a11y = a11y.merge(ref_key => "#{scope}#{separator}#{ref}")
            end
          end
          props = props.merge('a11y' => a11y)
        end
      end

      # Detect canvas shape structs leaked into the widget tree
      node.children.each do |child|
        if child.respond_to?(:to_wire) && !child.is_a?(Plushie::Node)
          raise ArgumentError, "Canvas shape #{child.class} found in widget tree. " \
            'Shapes belong inside canvas/layer/group blocks, not as widget children.'
        end
      end

      # Expand table rows: prop to table_row/table_cell children.
      # If a table has a :rows prop (data shorthand) and no children,
      # convert each row map to a table_row node with text cell children.
      table_children = if node.type == 'table' && node.children.empty? && node.props[:rows].is_a?(Array) && !node.props[:rows].empty?
                         expand_table_rows(node.props[:rows], node.props[:columns])
                       else
                         node.children
                       end

      # Consume the :rows prop so it doesn't appear on the wire.
      props = props.reject { |k, _| k == 'rows' } if node.type == 'table' && !table_children.equal?(node.children)

      children = table_children.map { |c| normalize_node(c, child_scope, registry, current_window_id, depth + 1) }
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
        next unless node.type == 'radio'

        group = node.props[:group] || node.props['group']
        next unless group.is_a?(String)

        (groups[group] ||= []) << [node, idx]
      end

      return children if groups.empty?

      # @type var patches: Hash[Integer, Hash[String, untyped]]
      patches = {}
      groups.each_value do |members|
        size = members.length
        members.each_with_index do |(node, child_idx), pos|
          a11y = node.props[:a11y] || node.props['a11y'] || {}
          a11y = a11y.dup if a11y.frozen?

          has_position = a11y['position_in_set'] || a11y[:position_in_set]
          has_size = a11y['size_of_set'] || a11y[:size_of_set]

          next if has_position && has_size

          # Use string keys to match encode_value output (which
          # stringifies inner hash keys during normalization).
          a11y['size_of_set'] = size unless has_size
          a11y['position_in_set'] = pos + 1 unless has_position
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

    # Expand data-based table rows to table_row/table_cell child nodes.
    # Each row map becomes a table_row with text cell children, one per column.
    # Requires an :id key in each row for stable row identity.
    def self.expand_table_rows(rows, columns)
      col_keys = if columns.is_a?(Array)
                   columns.map { |col| (col[:key] || col['key']).to_s }
                 else
                   []
                 end

      rows.map do |row|
        row_id = (row[:id] || row['id']).to_s

        cells = col_keys.map do |key|
          value = row[key.to_sym] || row[key] || ''
          text_node = Node.new(
            id: "#{row_id}/#{key}/text",
            type: 'text',
            props: { content: value.to_s }
          )

          Node.new(
            id: key,
            type: 'table_cell',
            props: { column: key },
            children: [text_node]
          )
        end

        Node.new(id: row_id, type: 'table_row', props: {}, children: cells)
      end
    end
    private_class_method :expand_table_rows

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

      msg = "duplicate sibling IDs detected during normalize: #{duplicates.uniq.map(&:inspect).join(', ')}"
      if duplicates.any? { |id| id.start_with?('auto:') }
        msg += '. For items in dynamic lists, provide explicit IDs instead of relying on auto-generated ones'
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
                   wrapper = Node.new(id: wrapper_id, type: 'container', children: children)
                   normalize_node(wrapper, scope, registry, window_id, depth + 1)
                 else
                   Node.new(id: 'auto:memo_empty', type: 'container')
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

      if id.include?('/')
        raise ArgumentError,
              "widget ID #{id.inspect} cannot contain \"/\", " \
              'scoped paths are built automatically by named containers'
      end

      if id.include?('#')
        raise ArgumentError,
              "widget ID #{id.inspect} cannot contain \"#\", " \
              '"#" is reserved for window-qualified paths (e.g., "window#widget")'
      end

      if id.bytesize > 1024
        raise ArgumentError,
              "widget ID #{id.inspect} exceeds maximum length of 1024 bytes"
      end

      return if VALID_ID_PATTERN.match?(id)

      raise ArgumentError,
            "widget ID #{id.inspect} contains invalid characters, " \
            'IDs must contain only printable ASCII (0x21-0x7E)'
    end
    private_class_method :validate_user_id!
  end
end
