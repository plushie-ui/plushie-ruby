# frozen_string_literal: true

module Plushie
  # Canvas widget extension system.
  #
  # Canvas widgets are pure Ruby widgets that render via canvas shapes
  # with runtime-managed internal state and event transformation. They
  # sit between the renderer and the app, intercepting events in the
  # scope chain and emitting semantic events.
  #
  # ## Defining a canvas widget
  #
  #   class StarRating
  #     include Plushie::CanvasWidget
  #
  #     canvas_widget :star_rating
  #
  #     def self.init = {hover: nil}
  #     def self.render(id, props, state) = ...
  #     def self.handle_event(event, state) = [:ignored, state]
  #     def self.subscribe(props, state) = []
  #   end
  #
  # ## How it works
  #
  # `build` creates a placeholder canvas node tagged with metadata.
  # During tree normalization, the runtime detects the tag, looks up
  # the widget's state from the registry, calls `render`, and
  # recursively normalizes the output. The normalized tree carries
  # metadata for registry derivation after each render cycle.
  #
  # Events flow through the scope chain before reaching `app.update`.
  # Each canvas widget in the chain gets a chance to handle the event:
  # `:ignored` passes through, `:consumed` stops the chain, and
  # `[:emit, kind, data]` replaces the event with a Widget event and
  # continues. The runtime fills in `id`, `scope`, and `window_id`
  # automatically from the widget's position in the tree.
  module CanvasWidget
    # Metadata keys used internally. Stored in Node#meta, never on the wire.
    META_KEY = :__canvas_widget__
    PROPS_KEY = :__canvas_widget_props__
    STATE_KEY = :__canvas_widget_state__

    # Subscription tag namespace prefix for canvas widgets.
    CW_TAG_PREFIX = "__cw:"

    def self.widget_key(window_id, widget_id)
      "#{window_id}\0#{widget_id}"
    end

    # Methods added to classes that include Plushie::CanvasWidget.
    module ClassMethods
      # Declares the canvas widget type name.
      #
      # @param type_name [Symbol] the widget type name
      def canvas_widget(type_name)
        @_canvas_widget_type = type_name
      end

      # @return [Symbol, nil] the declared widget type name
      def canvas_widget_type
        @_canvas_widget_type
      end
    end

    def self.included(base)
      base.extend(ClassMethods)

      # Provide default implementations for optional callbacks
      unless base.respond_to?(:subscribe)
        base.define_singleton_method(:subscribe) { |_props, _state| [] }
      end
    end

    # Build a placeholder node for a canvas widget.
    #
    # The returned node has type "canvas" and carries metadata that
    # the runtime uses during normalization to render the real canvas
    # tree with the widget's current state.
    #
    # @param widget_module [Module] the canvas widget module
    # @param id [String] widget identifier
    # @param props [Hash] widget input props
    # @return [Node]
    def self.build(widget_module, id, props = {})
      meta = {
        META_KEY => widget_module,
        PROPS_KEY => props
      }.freeze
      Node.new(id: id, type: "canvas", props: {}, meta: meta)
    end

    # Check if a node is a canvas widget placeholder.
    #
    # @param node [Node] the node to check
    # @return [Boolean]
    def self.placeholder?(node)
      node.meta.key?(META_KEY)
    end

    # -- Registry --------------------------------------------------------------

    # A registry entry for a canvas widget instance.
    RegistryEntry = Data.define(:widget_module, :state, :props) do
      def initialize(widget_module:, state:, props:)
        super
      end
    end

    # Derive the registry from a normalized tree.
    #
    # Walks the tree and extracts canvas widget metadata from nodes.
    # Returns a hash mapping window-aware widget keys to RegistryEntry values.
    #
    # @param tree [Node, nil]
    # @return [Hash{String => RegistryEntry}]
    def self.derive_registry(tree)
      return {} if tree.nil?
      registry = {}
      collect_entries(tree, registry, nil)
      registry
    end

    # -- Event dispatch --------------------------------------------------------

    # Route an event through canvas widget handlers in the scope chain.
    #
    # Returns [event_or_nil, updated_registry]. If no handler captures,
    # returns the original event. If a handler consumes, returns nil.
    #
    # @param registry [Hash{String => RegistryEntry}]
    # @param event [Object] the event to dispatch
    # @return [Array(Object, Hash)]
    def self.dispatch_through_widgets(registry, event)
      scope = extract_scope(event)
      event_id = extract_id(event)
      window_id = extract_window_id(event)
      chain = build_handler_chain(registry, window_id, scope, event_id)

      return [event, registry] if chain.empty?
      walk_chain(registry, event, chain)
    end

    # -- Widget-scoped subscriptions -------------------------------------------

    # Collect subscriptions from all canvas widgets in the registry.
    #
    # Each subscription's tag is namespaced with the widget's scoped ID
    # so the runtime can route timer events back to the correct widget.
    #
    # @param registry [Hash{String => RegistryEntry}]
    # @return [Array<Subscription::Sub>]
    def self.collect_subscriptions(registry)
      registry.flat_map do |widget_key, entry|
        subs = entry.widget_module.subscribe(entry.props, entry.state)
        Array(subs).map { |sub| namespace_tag(sub, widget_key) }
      end
    end

    # Check if a subscription tag is namespaced for a canvas widget.
    #
    # @param tag [String, Symbol]
    # @return [Boolean]
    def self.widget_tag?(tag)
      tag.to_s.start_with?(CW_TAG_PREFIX)
    end

    # Parse a namespaced tag into [widget_key, inner_tag].
    # Returns nil if the tag isn't namespaced.
    #
    # @param tag [String, Symbol]
    # @return [Array(String, String), nil]
    def self.parse_widget_tag(tag)
      tag_str = tag.to_s
      return nil unless tag_str.start_with?(CW_TAG_PREFIX)

      rest = tag_str[CW_TAG_PREFIX.length..]
      return nil if rest.nil? || rest.empty?
      first = rest.index(":")
      return nil unless first
      second = rest.index(":", first + 1)
      return nil unless second

      window_id = rest[0...first].to_s
      widget_id = rest[(first + 1)...second].to_s
      inner_tag = rest[(second + 1)..].to_s
      [widget_key(window_id, widget_id), inner_tag]
    end

    # Route a timer event to the correct canvas widget.
    #
    # If the timer tag is namespaced, look up the widget, create a
    # Timer event with the inner tag, dispatch through the widget's
    # handler. Returns [event_or_nil, registry] for widget timers,
    # or nil for non-widget timers (caller handles those).
    #
    # @param registry [Hash{String => RegistryEntry}]
    # @param tag [String, Symbol]
    # @return [Array(Object, Hash), nil]
    def self.handle_widget_timer(registry, tag)
      parsed = parse_widget_tag(tag)
      return nil unless parsed

      widget_key, inner_tag = parsed
      entry = registry[widget_key]
      return [nil, registry] unless entry

      timer_event = Event::Timer.new(
        tag: inner_tag.to_sym,
        timestamp: Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
      )

      action, new_state = safe_handle_event(entry, timer_event, widget_key)
      new_entry = RegistryEntry.new(widget_module: entry.widget_module, state: new_state, props: entry.props)
      registry = registry.merge(widget_key => new_entry)

      case action
      in :ignored | :consumed | :update_state
        [nil, registry]
      in [:emit, kind, data]
        window_id, id, scope = resolve_emit_identity(timer_event, widget_key)
        emitted = Event::Widget.new(
          type: kind.to_sym,
          id: id,
          window_id: window_id,
          scope: scope,
          data: normalize_emit_data(data)
        )
        dispatch_through_widgets(registry, emitted)
      end
    end

    # -- Normalization support -------------------------------------------------

    # Render a canvas widget placeholder during normalization.
    #
    # Looks up existing state from the registry, calls render, and
    # returns the rendered node with widget metadata attached.
    #
    # @param node [Node] the placeholder node
    # @param window_id [String, nil] containing window ID
    # @param scoped_id [String] the normalized scoped ID
    # @param local_id [String] the pre-scoped local ID
    # @param registry [Hash{String => RegistryEntry}]
    # @return [Array(Node, RegistryEntry), nil]
    def self.render_placeholder(node, window_id, scoped_id, local_id, registry)
      widget_module = node.meta[META_KEY]
      widget_props = node.meta[PROPS_KEY] || {}
      return nil unless widget_module
      raise ArgumentError, "canvas widget #{local_id.inspect} must be rendered inside a window" if window_id.nil? || window_id.empty?

      # Look up existing state or create initial
      key = widget_key(window_id, scoped_id)
      existing = registry[key]
      state = if existing
        existing.state
      else
        widget_module.init
      end

      entry = RegistryEntry.new(widget_module: widget_module, state: state, props: widget_props)

      # Render with local ID -- scoping applied by caller
      rendered = widget_module.render(local_id, widget_props, state)

      # Attach metadata for registry derivation
      widget_meta = {
        META_KEY => widget_module,
        PROPS_KEY => widget_props,
        STATE_KEY => state
      }.freeze

      final_node = rendered.with(id: scoped_id, meta: widget_meta)
      [final_node, entry]
    end

    class << self
      private

      def collect_entries(node, acc, current_window_id)
        current_window_id = node.id if node.type == "window"
        meta = node.meta
        if meta.key?(META_KEY) && meta.key?(STATE_KEY)
          raise ArgumentError, "canvas widget #{node.id.inspect} must be rendered inside a window" if current_window_id.nil? || current_window_id.empty?

          widget_module = meta[META_KEY]
          state = meta[STATE_KEY]
          props = meta[PROPS_KEY] || {}
          key = widget_key(current_window_id, node.id)
          acc[key] = RegistryEntry.new(widget_module: widget_module, state: state, props: props)
        end

        node.children.each { |child| collect_entries(child, acc, current_window_id) }
      end

      def build_handler_chain(registry, window_id, scope, event_id)
        chain = scope_to_widget_ids(scope).filter_map do |id|
          key = widget_key(window_id, id)
          entry = registry[key]
          entry ? [key, entry] : nil
        end

        if chain.empty?
          target_id = scope_to_id(scope, event_id)
          key = widget_key(window_id, target_id)
          entry = registry[key]
          chain = [[key, entry]] if entry
        end

        chain
      end

      def walk_chain(registry, event, chain)
        return [event, registry] if chain.empty?

        widget_id, entry = chain.first
        rest = chain[1..]

        action, new_state = safe_handle_event(entry, event, widget_id)
        new_entry = RegistryEntry.new(widget_module: entry.widget_module, state: new_state, props: entry.props)
        registry = registry.merge(widget_id => new_entry)

        case action
        in :ignored
          walk_chain(registry, event, rest)
        in :consumed | :update_state
          [nil, registry]
        in [:emit, kind, data]
          window_id, id, scope = resolve_emit_identity(event, widget_id)
          emitted = Event::Widget.new(
            type: kind.to_sym,
            id: id,
            window_id: window_id,
            scope: scope,
            data: normalize_emit_data(data)
          )
          walk_chain(registry, emitted, rest)
        end
      end

      def safe_handle_event(entry, event, widget_id)
        result = entry.widget_module.handle_event(event, entry.state)
        case result
        in [:ignored, new_state]
          [:ignored, new_state]
        in [:consumed, new_state]
          [:consumed, new_state]
        in [:update_state, new_state]
          [:update_state, new_state]
        in [:emit, kind, data, new_state]
          [[:emit, kind, data], new_state]
        in [:emit, kind, data]
          [[:emit, kind, data], entry.state]
        end
      rescue => e
        warn "plushie: canvas_widget \"#{widget_id}\" raised in handle_event: #{e.class}: #{e.message}"
        [:ignored, entry.state]
      end

      def resolve_emit_identity(event, widget_id)
        window_id, full_widget_id = split_widget_key(widget_id)
        scope = extract_scope(event)
        case scope
        in [canvas_id, *parent_scope] if extract_window_id(event) == window_id
          [window_id, canvas_id, parent_scope]
        in []
          id = extract_id(event)
          if id.empty?
            id, widget_scope = split_widget_id(full_widget_id)
            [window_id, id, widget_scope]
          else
            [window_id, id, []]
          end
        end
      end

      def split_widget_id(widget_id)
        parts = widget_id.split("/")
        if parts.length > 1
          [parts.last.to_s, Array(parts[0...-1]).reverse]
        else
          [widget_id, []]
        end
      end

      def normalize_emit_data(data)
        if data.is_a?(Hash)
          data.transform_keys(&:to_s)
        else
          {"value" => data}
        end
      end

      # Convert a reversed scope list to forward-order scoped IDs,
      # from innermost to outermost.
      #
      # scope = ["child", "parent"] produces ["parent/child", "parent"]
      def scope_to_widget_ids(scope)
        forward = scope.reverse
        result = []
        forward.length.downto(1) do |n|
          result << Array(forward[0...n]).join("/")
        end
        result
      end

      # Reconstruct a full scoped ID from a reversed scope list and a local ID.
      def scope_to_id(scope, id)
        return id if scope.empty?
        (scope.reverse + [id]).join("/")
      end

      def namespace_tag(sub, widget_id)
        window_id, full_widget_id = split_widget_key(widget_id)
        old_tag = sub.tag
        new_tag = "#{CW_TAG_PREFIX}#{window_id}:#{full_widget_id}:#{old_tag}"
        sub.with(tag: new_tag)
      end

      def extract_scope(event)
        event.respond_to?(:scope) ? (event.scope || []) : []
      end

      def extract_id(event)
        event.respond_to?(:id) ? (event.id || "").to_s : ""
      end

      def extract_window_id(event)
        event.respond_to?(:window_id) ? event.window_id.to_s : ""
      end

      def split_widget_key(widget_key)
        widget_key.split("\0", 2)
      end
    end
  end
end
