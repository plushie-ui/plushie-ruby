# frozen_string_literal: true

module Plushie
  class Runtime
    # Window lifecycle management for the Plushie runtime.
    #
    # Detects window nodes in the UI tree, opens/closes/updates windows
    # via the bridge, and tracks the set of active window IDs.
    module Windows
      # Window setting keys that can be specified as node props on window elements.
      WINDOW_PROP_KEYS = %i[
        title size width height position min_size max_size maximized fullscreen
        visible resizable closeable minimizable decorations transparent blur level
        exit_on_close_request scale_factor theme
      ].freeze

      # Detect window node IDs from the tree.
      #
      # @param tree [Node, nil]
      # @return [Set<String>]
      def self.detect_windows(tree)
        return Set.new unless tree

        ids = []
        collect_window_ids(tree, ids)
        Set.new(ids)
      end

      # Synchronize tracked windows with the current tree.
      #
      # Opens new windows (calling window_config for base settings),
      # closes removed windows, and sends update ops for windows
      # whose props changed.
      #
      # @param runtime [Runtime] the runtime instance
      # @param new_tree [Node, nil] the newly rendered tree
      # @param previous_tree [Node, nil] the previous tree (for prop diffing)
      # @param tracked_windows [Set<String>] currently tracked window IDs
      # @return [Set<String>] the new set of tracked window IDs
      def self.sync_windows(runtime, new_tree, previous_tree, tracked_windows)
        new_windows = detect_windows(new_tree)
        opened = new_windows - tracked_windows
        closed = tracked_windows - new_windows
        surviving = tracked_windows & new_windows

        opened.each do |window_id|
          base_settings = begin
            runtime.app.window_config(runtime.model)
          rescue => e
            runtime.logger.warn("plushie: window_config error: #{e.class}: #{e.message}")
            {}
          end

          per_window_props = extract_window_props(new_tree, window_id)
          settings = base_settings.merge(per_window_props)

          runtime.bridge_send_window_op("open", window_id, settings)
        end

        closed.each do |window_id|
          runtime.bridge_send_window_op("close", window_id)
        end

        surviving.each do |window_id|
          old_props = extract_window_props(previous_tree, window_id)
          new_props = extract_window_props(new_tree, window_id)
          runtime.bridge_send_window_op("update", window_id, new_props) if old_props != new_props
        end

        new_windows
      end

      # Extract window-related props from a window node in the tree.
      #
      # @param tree [Node, nil]
      # @param window_id [String]
      # @return [Hash]
      def self.extract_window_props(tree, window_id)
        return {} unless tree

        node = find_window_node(tree, window_id)
        return {} unless node

        props = node.props
          .select { |k, _| WINDOW_PROP_KEYS.include?(k.to_sym) }
          .to_h { |k, v| [k.to_sym, v] }

        decompose_size_tuples(props)
      end

      def self.collect_window_ids(node, ids)
        ids << node.id if node.type == "window"
        return unless node.respond_to?(:children) && node.children

        node.children.each { |child| collect_window_ids(child, ids) }
      end

      def self.find_window_node(node, window_id)
        return node if node.type == "window" && node.id == window_id

        if node.respond_to?(:children) && node.children
          node.children.each do |child|
            found = find_window_node(child, window_id)
            return found if found
          end
        end

        nil
      end

      def self.decompose_size_tuples(props)
        props = decompose_size(props)
        props = decompose_nested_size(props, :min_size)
        decompose_nested_size(props, :max_size)
      end

      def self.decompose_size(props)
        size = props[:size]
        return props unless size.is_a?(Array) && size.length == 2

        props = props.except(:size)
        props[:width] ||= size[0]
        props[:height] ||= size[1]
        props
      end

      def self.decompose_nested_size(props, key)
        val = props[key]
        return props unless val.is_a?(Array) && val.length == 2

        props.merge(key => {width: val[0], height: val[1]})
      end
    end
  end
end
