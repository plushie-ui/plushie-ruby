# frozen_string_literal: true

require_relative "tree/search"
require_relative "tree/diff"

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
      return [Node.new(id: "root", type: "container")] if tree.nil?

      trees = (tree.is_a?(Array) ? tree : [tree]).compact
      normalized = trees.map { |node| normalize_node(node, "", registry, nil, 0) }
      check_duplicate_ids!(normalized)
      normalized.map { |node| post_normalize(node) }
    end

    # Normalize a top-level app view and require explicit windows.
    #
    # A `nil` tree is treated as "no UI": returns a root container
    # with no child windows so the renderer still has a structurally
    # valid snapshot to diff. Useful for transition, loading, or
    # error states where the app has nothing to display yet.
    #
    # @param tree [Node, Array<Node>, nil]
    # @param registry [Hash, nil]
    # @return [Node] normalized synthetic root or window node
    def self.normalize_view(tree, registry: nil)
      return Node.new(id: "root", type: "root", children: []) if tree.nil?

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
    def self.diff(old_tree, new_tree) = Diff.diff(old_tree, new_tree)

    # Convert a Node to a plain wire-ready Hash (recursive).
    #
    # @param node [Node]
    # @return [Hash]
    def self.node_to_wire(node)
      {
        "id" => node.id,
        "type" => node.type,
        "props" => Encode.encode_props(node.props),
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

      warn "plushie: tree depth reached #{DEPTH_WARNING}, approaching limit of #{MAX_DEPTH}" if depth == DEPTH_WARNING

      # Handle memo nodes: check cache, evaluate block if miss
      return normalize_memo(node, scope, registry, window_id, depth) if node.type == "__memo__" && node.meta

      # Validate user-provided IDs (non-auto, non-prescoped).
      # IDs containing "#" are already scoped (from render_placeholder)
      # and should not be validated as user-provided IDs.
      validate_user_id!(node.id) unless node.id.start_with?("auto:") || node.id.include?("#")

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
          normalized = normalize_node(stripped, "", registry, current_window_id, depth + 1)
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

      # Expand table rows: prop to table_row/table_cell children.
      # If a table has a :rows prop (data shorthand) and no children,
      # convert each row map to a table_row node with text cell children.
      # Combining rows: prop with block children is an error.
      if node.type == "table"
        has_rows = node.props[:rows].is_a?(Array) && !node.props[:rows].empty?
        has_children = !node.children.empty?
        if has_rows && has_children
          raise ArgumentError,
            "table #{node.id.inspect}: cannot combine rows: prop with " \
            "block children (table_row). Use one or the other."
        end
      end

      table_children = if node.type == "table" && node.children.empty? && node.props[:rows].is_a?(Array) && !node.props[:rows].empty?
        expand_table_rows(node.props[:rows], node.props[:columns])
      else
        node.children
      end

      # Consume the :rows prop so it doesn't appear on the wire.
      if node.type == "table" && !table_children.equal?(node.children)
        props = props.except("rows", :rows)
      end

      children = table_children.map { |c| normalize_node(c, child_scope, registry, current_window_id, depth + 1) }
      check_duplicate_ids!(children)
      children = infer_radio_groups(children)
      Node.new(id: scoped_id, type: node.type, props: props, children: children)
    end
    private_class_method :normalize_node

    # -----------------------------------------------------------------
    # Post-normalize a11y pass
    # -----------------------------------------------------------------
    #
    # Mirrors the Rust SDK. After the main normalize pass produces a
    # fully scoped tree:
    #   - Auto-populate a11y.role from the widget type when unset.
    #   - Rewrite active_descendant and radio_group list refs through
    #     the same scope-prefix logic already applied to labelled_by,
    #     described_by, error_message.
    #   - Populate implicit a11y.radio_group when radios share a
    #     :group prop in the same enclosing scope.
    #   - Emit a11y_ref_unresolved warnings for dangling refs.
    #   - Emit missing_accessible_name warnings for interactive
    #     widgets carrying no accessible name source.

    WIDGET_ROLE_DEFAULTS = {
      "button" => "button", "checkbox" => "check_box", "toggler" => "switch",
      "radio" => "radio_button", "text_input" => "text_input",
      "text_editor" => "multiline_text_input", "text" => "label",
      "rich_text" => "label", "slider" => "slider", "vertical_slider" => "slider",
      "pick_list" => "combo_box", "combo_box" => "combo_box",
      "progress_bar" => "progress_indicator", "image" => "image", "svg" => "image",
      "qr_code" => "image", "scrollable" => "scroll_view",
      "container" => "generic_container", "column" => "generic_container",
      "row" => "generic_container", "stack" => "generic_container",
      "grid" => "generic_container", "pane_grid" => "generic_container",
      "table" => "table", "canvas" => "canvas", "rule" => "separator"
    }.freeze
    private_constant :WIDGET_ROLE_DEFAULTS

    A11Y_SINGLE_REF_KEYS = %w[labelled_by described_by error_message active_descendant].freeze
    private_constant :A11Y_SINGLE_REF_KEYS

    NAMED_INTERACTIVE_TYPES = %w[button toggler checkbox pointer_area].freeze
    private_constant :NAMED_INTERACTIVE_TYPES

    def self.post_normalize(tree)
      declared = Set.new
      collect_declared_ids(tree, declared)
      # @type var radio_groups: Hash[[String, String], Array[String]]
      radio_groups = {}
      collect_radio_groups(tree, "", radio_groups)
      rewritten = rewrite_a11y(tree, "", declared, radio_groups)
      check_missing_accessible_name(rewritten)
      rewritten
    end
    private_class_method :post_normalize

    def self.collect_declared_ids(node, out)
      id = node.id
      if id.is_a?(String) && !id.empty? && !id.start_with?("auto:")
        out.add(id)
      end
      node.children.each { |c| collect_declared_ids(c, out) }
    end
    private_class_method :collect_declared_ids

    def self.collect_radio_groups(node, scope, out)
      if node.type == "radio"
        group = node.props[:group] || node.props["group"]
        if group.is_a?(String) && !group.empty?
          (out[[scope, group]] ||= []) << node.id
        end
      end
      child_scope = child_scope_for(node, scope)
      node.children.each { |c| collect_radio_groups(c, child_scope, out) }
    end
    private_class_method :collect_radio_groups

    def self.child_scope_for(node, scope)
      if node.type == "window"
        "#{node.id}#"
      elsif node.id.is_a?(String) && (node.id.empty? || node.id.start_with?("auto:"))
        scope
      else
        node.id
      end
    end
    private_class_method :child_scope_for

    def self.rewrite_a11y(node, scope, declared, radio_groups, tooltip_parent_id = nil)
      new_props = apply_a11y_rewrites(node, scope, declared, radio_groups, tooltip_parent_id)
      child_scope = child_scope_for(node, scope)
      tooltip_for_children = (node.type == "tooltip") ? node.id : nil
      new_children = node.children.map do |c|
        rewrite_a11y(c, child_scope, declared, radio_groups, tooltip_for_children)
      end
      node.with(props: new_props, children: new_children)
    end
    private_class_method :rewrite_a11y

    PLACEHOLDER_DESCRIPTION_WIDGETS = %w[text_input text_editor combo_box pick_list].freeze
    VALIDATABLE_WIDGETS = %w[text_input text_editor checkbox pick_list combo_box].freeze
    private_constant :PLACEHOLDER_DESCRIPTION_WIDGETS, :VALIDATABLE_WIDGETS

    def self.placeholder_description(node_type, props)
      return nil unless PLACEHOLDER_DESCRIPTION_WIDGETS.include?(node_type)
      ph = props[:placeholder] || props["placeholder"]
      (ph.is_a?(String) && !ph.empty?) ? ph : nil
    end
    private_class_method :placeholder_description

    def self.required_from_props(node_type, props)
      return nil unless VALIDATABLE_WIDGETS.include?(node_type)
      req = props[:required]
      req = props["required"] if req.nil?
      (req == true || req == false) ? req : nil
    end
    private_class_method :required_from_props

    # Project :validation onto [invalid, error_message]. Accepts the
    # builder-idiomatic shapes (symbols, arrays, hashes) plus their
    # wire-encoded siblings (all-string shapes).
    def self.invalid_from_props(node_type, props)
      return [nil, nil] unless VALIDATABLE_WIDGETS.include?(node_type)
      v = props[:validation] || props["validation"]
      return [nil, nil] if v.nil?
      case v
      when :valid, "valid"
        [false, nil]
      when :pending, "pending"
        [nil, nil]
      when Array
        if v.length == 2 && (v[0] == :invalid || v[0] == "invalid")
          msg = v[1]
          [true, msg.is_a?(String) ? msg : nil]
        else
          [nil, nil]
        end
      when Hash
        state = v[:state] || v["state"]
        case state
        when :valid, "valid"
          [false, nil]
        when :pending, "pending"
          [nil, nil]
        when :invalid, "invalid"
          msg = v[:message] || v["message"]
          [true, msg.is_a?(String) ? msg : nil]
        else
          [nil, nil]
        end
      else
        [nil, nil]
      end
    end
    private_class_method :invalid_from_props

    def self.apply_a11y_rewrites(node, scope, declared, radio_groups, tooltip_parent_id = nil)
      props = node.props
      role_default = WIDGET_ROLE_DEFAULTS[node.type]

      radio_ids = nil
      if node.type == "radio"
        group = props[:group] || props["group"]
        if group.is_a?(String) && !group.empty?
          radio_ids = radio_groups[[scope, group]]
        end
      end

      placeholder_desc = placeholder_description(node.type, props)
      required_prop = required_from_props(node.type, props)
      invalid_prop, error_text = invalid_from_props(node.type, props)

      a11y_in = props[:a11y] || props["a11y"]
      a11y_hash = a11y_in.is_a?(Hash) ? a11y_in.dup : nil

      needs_update = (role_default && !(a11y_hash && has_role?(a11y_hash))) ||
        !radio_ids.nil? ||
        (a11y_hash && has_any_ref?(a11y_hash)) ||
        !placeholder_desc.nil? ||
        !required_prop.nil? ||
        !invalid_prop.nil? ||
        !error_text.nil? ||
        !tooltip_parent_id.nil?

      return props if a11y_hash.nil? && !needs_update

      a11y = a11y_hash || {}

      if role_default && !has_role?(a11y)
        a11y["role"] = role_default
      end

      A11Y_SINGLE_REF_KEYS.each do |key|
        ref = a11y[key] || a11y[key.to_sym]
        if ref.is_a?(String) && !ref.empty?
          rewritten = scope_ref(ref, scope)
          unless declared.include?(rewritten)
            warn_a11y_unresolved(key, ref, node.id)
          end
          a11y.delete(key.to_sym)
          a11y[key] = rewritten
        end
      end

      existing_group = a11y["radio_group"] || a11y[:radio_group]
      if existing_group.is_a?(Array)
        rewritten_group = existing_group.map do |item|
          if item.is_a?(String) && !item.empty?
            r = scope_ref(item, scope)
            unless declared.include?(r)
              warn_a11y_unresolved("radio_group", item, node.id)
            end
            r
          else
            item
          end
        end
        a11y.delete(:radio_group)
        a11y["radio_group"] = rewritten_group
      elsif radio_ids
        a11y["radio_group"] = radio_ids.dup
      end

      if placeholder_desc && !a11y.key?("description") && !a11y.key?(:description)
        a11y["description"] = placeholder_desc
      end

      if required_prop == true && !a11y.key?("required") && !a11y.key?(:required)
        a11y["required"] = true
      end

      if !invalid_prop.nil? && !a11y.key?("invalid") && !a11y.key?(:invalid)
        a11y["invalid"] = invalid_prop
      end

      if error_text && !a11y.key?("error_message") && !a11y.key?(:error_message)
        a11y["error_message"] = error_text
      end

      if tooltip_parent_id && !a11y.key?("described_by") && !a11y.key?(:described_by)
        a11y["described_by"] = tooltip_parent_id
      end

      props.merge(a11y: a11y)
    end
    private_class_method :apply_a11y_rewrites

    def self.has_role?(a11y)
      role = a11y["role"] || a11y[:role]
      !role.nil?
    end
    private_class_method :has_role?

    def self.has_any_ref?(a11y)
      A11Y_SINGLE_REF_KEYS.any? { |k| a11y.key?(k) || a11y.key?(k.to_sym) } ||
        a11y.key?("radio_group") || a11y.key?(:radio_group)
    end
    private_class_method :has_any_ref?

    def self.scope_ref(ref, scope)
      return ref if scope.empty? || ref.empty?
      return ref if ref.include?("/") || ref.include?("#")
      separator = scope.end_with?("#") ? "" : "/"
      "#{scope}#{separator}#{ref}"
    end
    private_class_method :scope_ref

    def self.warn_a11y_unresolved(key, ref, owner_id)
      warn "plushie a11y: a11y_ref_unresolved: a11y.#{key} #{ref.inspect} on #{owner_id.inspect} does not match any declared widget ID"
    end
    private_class_method :warn_a11y_unresolved

    def self.check_missing_accessible_name(node)
      if NAMED_INTERACTIVE_TYPES.include?(node.type) && !accessible_name?(node)
        warn "plushie a11y: missing_accessible_name: #{node.type} #{node.id.inspect} " \
             "has no label, text child, a11y.label, or a11y.labelled_by; screen readers " \
             "will announce no name"
      end
      node.children.each { |c| check_missing_accessible_name(c) }
    end
    private_class_method :check_missing_accessible_name

    def self.accessible_name?(node)
      label = node.props[:label] || node.props["label"]
      return true if label.is_a?(String) && !label.empty?

      a11y = node.props[:a11y] || node.props["a11y"]
      if a11y.is_a?(Hash)
        l = a11y["label"] || a11y[:label]
        return true if l.is_a?(String) && !l.empty?
        lb = a11y["labelled_by"] || a11y[:labelled_by]
        return true if lb.is_a?(String) && !lb.empty?
      end

      text_descendant?(node.children)
    end
    private_class_method :accessible_name?

    def self.text_descendant?(children)
      children.any? do |child|
        if child.type == "text"
          content = child.props[:content] || child.props["content"]
          (content.is_a?(String) && !content.empty?) || text_descendant?(child.children)
        else
          text_descendant?(child.children)
        end
      end
    end
    private_class_method :text_descendant?

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

          has_position = a11y["position_in_set"] || a11y[:position_in_set]
          has_size = a11y["size_of_set"] || a11y[:size_of_set]

          next if has_position && has_size

          # Use string keys to match encode_value output (which
          # stringifies inner hash keys during normalization).
          a11y["size_of_set"] = size unless has_size
          a11y["position_in_set"] = pos + 1 unless has_position
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
      # @type var col_keys: Array[String]
      col_keys = if columns.is_a?(Array)
        columns.map do |col|
          case col
          in Hash
            (col[:key] || col["key"]).to_s
          in String, Symbol
            col.to_s
          else
            col.to_s
          end
        end
      else
        []
      end

      rows.map do |row|
        row_id = (row[:id] || row["id"] || "").to_s

        cells = col_keys.map do |key|
          value = row[key.to_sym] || row[key] || ""
          text_node = Node.new(
            id: "#{row_id}/#{key}/text",
            type: "text",
            props: {content: value.to_s}
          )

          Node.new(
            id: key,
            type: "table_cell",
            props: {column: key},
            children: [text_node]
          )
        end

        Node.new(id: row_id, type: "table_row", props: {}, children: cells)
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
          '"#" is reserved for window-qualified paths (e.g., "window#widget")'
      end

      if id.bytesize > 1024
        raise ArgumentError,
          "widget ID #{id.inspect} exceeds maximum length of 1024 bytes"
      end

      return if VALID_ID_PATTERN.match?(id)

      raise ArgumentError,
        "widget ID #{id.inspect} contains invalid characters, " \
        "IDs must contain only printable ASCII (0x21-0x7E)"
    end
    private_class_method :validate_user_id!
  end
end
