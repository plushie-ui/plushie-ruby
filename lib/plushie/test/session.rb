# frozen_string_literal: true

require "securerandom"

module Plushie
  module Test
    # Test session driving the Elm loop against a pooled renderer.
    # Each test gets its own Session with isolated model state.
    #
    # Interactions (click, type_text, toggle, etc.) are sent via the
    # renderer's interact protocol; resulting events are fed through
    # the app's update cycle so the model stays in sync.
    #
    # See the Elixir SDK's mock renderer backend for reference.
    class Session
      # @return [Object] current app model
      attr_reader :model

      # @param app_class [Class] the app class (includes Plushie::App)
      # @param pool [SessionPool]
      # @param session_id [String]
      def initialize(app_class, pool:, session_id:)
        @app = app_class.new
        @pool = pool
        @session_id = session_id
        @format = pool.format
        @model = nil
        @tree = nil
        @diagnostics = []
        init_app
      end

      # -- Interactions (simulate user actions) --------------------------------

      # Click a button widget.
      # @param selector [String] "#id" or "text content"
      def click(selector)
        interact("click", selector)
      end

      # Type text into a text_input or text_editor.
      # @param selector [String]
      # @param text [String]
      def type_text(selector, text)
        interact("type_text", selector, text: text)
      end

      # Submit a text_input (press Enter).
      # @param selector [String]
      def submit(selector)
        # Read current value from local tree
        node = find_in_local_tree(selector)
        value = node_prop(node, "value") || ""
        interact("submit", selector, value: value)
      end

      # Toggle a checkbox or toggler.
      # @param selector [String]
      def toggle(selector)
        node = find_in_local_tree(selector)
        current = node_prop(node, "checked") || node_prop(node, "active") || false
        interact("toggle", selector, value: !current)
      end

      # Select a value from pick_list, combo_box, or radio.
      # @param selector [String]
      # @param value [String]
      def select(selector, value)
        interact("select", selector, value: value)
      end

      # Slide a slider to a value.
      # @param selector [String]
      # @param value [Numeric]
      def slide(selector, value)
        interact("slide", selector, value: value)
      end

      # Press a key (key down).
      # @param key [String] key name, supports modifiers: "ctrl+s"
      def press(key)
        interact("press", nil, key: normalize_key(key))
      end

      # Release a key (key up).
      # @param key [String]
      def release(key)
        interact("release", nil, key: normalize_key(key))
      end

      # Type a key (press + release).
      # @param key [String]
      def type_key(key)
        interact("type_key", nil, key: normalize_key(key))
      end

      # Move cursor to coordinates.
      # @param x [Numeric]
      # @param y [Numeric]
      def move_to(x, y)
        interact("move_to", nil, x: x, y: y)
      end

      # -- Queries (inspect the tree) ------------------------------------------

      # Find a widget by selector. Returns the node hash or nil.
      # @param selector [String] "#id" or "text content"
      # @return [Hash, nil]
      def find(selector)
        id = SecureRandom.hex(4)
        response = @pool.send_and_wait(
          {type: "query", id: id, target: "find", selector: build_selector(selector)},
          @session_id, :query_response
        )
        data = response[:data] || response["data"]
        (data.nil? || data.empty?) ? nil : data
      end

      # Find a widget by selector. Raises with a helpful error if not found,
      # including the current tree IDs and similar ID suggestions.
      #
      # @param selector [String]
      # @return [Hash]
      # @raise [Plushie::Error] if widget not found
      def find!(selector)
        result = find(selector)
        unless result
          all_ids = Tree.ids(@tree)
          target = selector.start_with?("#") ? selector[1..] : selector
          suggestions = find_similar_ids(target, all_ids)

          msg = "Widget not found: #{selector}\n"
          msg << "\n  Did you mean: #{suggestions.map { "##{_1}" }.join(", ")}\n" if suggestions.any?
          msg << "\n  Current tree IDs: #{all_ids.join(", ")}"
          raise Plushie::Error, msg
        end
        result
      end

      # Get the full tree from the renderer.
      # @return [Hash]
      def tree
        id = SecureRandom.hex(4)
        response = @pool.send_and_wait(
          {type: "query", id: id, target: "tree", selector: {}},
          @session_id, :query_response
        )
        response[:data] || response["data"]
      end

      # Capture a structural tree hash.
      # @param name [String]
      # @return [Hash]
      def tree_hash(name)
        id = SecureRandom.hex(4)
        @pool.send_and_wait(
          {type: "tree_hash", id: id, name: name},
          @session_id, :tree_hash_response
        )
      end

      # Capture a screenshot.
      # @param name [String]
      # @param width [Integer]
      # @param height [Integer]
      # @return [Hash]
      def screenshot(name, width: 1024, height: 768)
        id = SecureRandom.hex(4)
        @pool.send_and_wait(
          {type: "screenshot", id: id, name: name, width: width, height: height},
          @session_id, :screenshot_response
        )
      end

      # Reset the session to initial state.
      def reset
        @model = nil
        @tree = nil
        init_app
      end

      # Register an effect stub with the renderer for this session.
      #
      # @param kind [String] effect kind
      # @param response [Object] canned response
      def register_effect_stub(kind, response)
        @pool.send_message(
          {type: "register_effect_stub", kind: kind.to_s, response: response},
          @session_id
        )
        @pool.read_message(@session_id, timeout: 5)
      end

      # Remove a previously registered effect stub.
      #
      # @param kind [String] effect kind
      def unregister_effect_stub(kind)
        @pool.send_message(
          {type: "unregister_effect_stub", kind: kind.to_s},
          @session_id
        )
        @pool.read_message(@session_id, timeout: 5)
      end

      # Returns and clears accumulated prop validation diagnostics.
      #
      # @return [Array<Event::System>]
      def get_diagnostics
        result = @diagnostics.dup
        @diagnostics.clear
        result
      end

      # Stop the session and release the renderer session.
      def stop
        @pool.unregister(@session_id)
      rescue => e
        # Swallow errors during cleanup
        warn "plushie test: error during session cleanup: #{e.message}" if $DEBUG
      end

      # Extract text content from an element hash.
      # Checks content, label, value, placeholder in order.
      # @param element [Hash]
      # @return [String, nil]
      def element_text(element)
        return nil unless element
        props = element["props"] || element[:props] || {}
        props["content"] || props["label"] || props["value"] || props["placeholder"]
      end

      private

      # -- Initialization ------------------------------------------------------

      def init_app
        result = @app.init({})
        @model, commands = unwrap_result(result)
        process_commands_sync(commands)

        # Send settings + initial snapshot
        settings = @app.settings
        @pool.send_message(
          {type: "settings", settings: settings.merge(protocol_version: Protocol::PROTOCOL_VERSION)},
          @session_id
        )

        render_and_snapshot
      end

      # -- Interaction protocol ------------------------------------------------

      def interact(action, selector, **payload)
        # For ID selectors, validate the selector resolves in the local tree
        # before sending the interact request. Fail fast with a clear error
        # instead of silently producing no events. Non-ID selectors (text
        # content, role, label) are resolved by the renderer during the
        # interact step and cannot be validated client-side.
        if selector&.start_with?("#") && !find_in_local_tree(selector)
          all_ids = @tree ? Tree.ids(@tree) : []
          err = "Widget not found: #{selector.inspect}. The #{action} action requires a valid widget selector."
          err << "\n  Current tree IDs: #{all_ids.join(", ")}" if all_ids.any?
          raise Plushie::Error, err
        end

        id = SecureRandom.hex(4)
        msg = {type: "interact", id: id, action: action, payload: payload}
        msg[:selector] = build_selector(selector) if selector
        @pool.send_message(msg, @session_id)

        # Read responses -- handle interact_step (headless) or interact_response (mock)
        loop do
          response = @pool.read_message(@session_id, timeout: 30)
          response_type = (response[:type] || response["type"])&.to_sym

          case response_type
          when :interact_step
            events = extract_events(response)
            process_events_batch(events)
            send_snapshot
          when :interact_response
            events = extract_events(response)
            process_events_individually(events)
            break
          else
            # Subscription events or other messages that arrive during interact
            # are silently consumed -- test sessions don't fire subscriptions
            # in mock mode, and headless mode delivers them via interact_step.
          end
        end
      end

      # Process events from an interact_step: all in one batch, one snapshot at the end.
      def process_events_batch(events)
        events.each do |event|
          next if intercept_diagnostic(event)
          saved = @model
          result = @app.update(@model, event)
          @model, commands = unwrap_result(result)
          process_commands_sync(commands)
        rescue => e
          @model = saved
          warn "plushie test: error processing event: #{e.class}: #{e.message}" if $DEBUG
        end
        @tree = normalize_view
      end

      # Process events individually: each triggers update + render + snapshot.
      def process_events_individually(events)
        events.each do |event|
          next if intercept_diagnostic(event)
          saved = @model
          result = @app.update(@model, event)
          @model, commands = unwrap_result(result)
          process_commands_sync(commands)
          render_and_snapshot
        rescue => e
          @model = saved
          warn "plushie test: error processing event: #{e.class}: #{e.message}" if $DEBUG
        end
      end

      # -- Rendering -----------------------------------------------------------

      def render_and_snapshot
        @tree = normalize_view
        send_snapshot
      end

      def normalize_view
        tree_list = Tree.normalize(@app.view(@model))
        tree_list.is_a?(Array) ? tree_list.first : tree_list
      end

      def send_snapshot
        wire = Tree.node_to_wire(@tree)
        @pool.send_message({type: "snapshot", tree: wire}, @session_id)
      end

      # -- Command processing (synchronous for tests) -------------------------

      def process_commands_sync(cmd)
        return if cmd.nil?

        case cmd.type
        when :none then nil
        when :batch then cmd.payload[:commands]&.each { |c| process_commands_sync(c) }
        when :async
          # Execute synchronously in tests
          result = cmd.payload[:callable].call
          event = Event::Async.new(tag: cmd.payload[:tag], result: result)
          saved = @model
          begin
            r = @app.update(@model, event)
            @model, sub_cmds = unwrap_result(r)
            process_commands_sync(sub_cmds)
          rescue
            @model = saved
          end
        when :stream
          # Execute synchronously, collecting emitted values
          tag = cmd.payload[:tag]
          emit = ->(value) {
            event = Event::Stream.new(tag: tag, value: value)
            saved = @model
            begin
              r = @app.update(@model, event)
              @model, sub_cmds = unwrap_result(r)
              process_commands_sync(sub_cmds)
            rescue
              @model = saved
            end
          }
          result = cmd.payload[:callable].call(emit)
          final_event = Event::Async.new(tag: tag, result: result)
          saved = @model
          begin
            r = @app.update(@model, final_event)
            @model, sub_cmds = unwrap_result(r)
            process_commands_sync(sub_cmds)
          rescue
            @model = saved
          end
        when :done
          event = cmd.payload[:mapper].call(cmd.payload[:value])
          saved = @model
          begin
            r = @app.update(@model, event)
            @model, sub_cmds = unwrap_result(r)
            process_commands_sync(sub_cmds)
          rescue
            @model = saved
          end
        else
          # Widget ops, window ops, effects, etc. are no-ops in test mode
          nil
        end
      end

      # -- Helpers -------------------------------------------------------------

      def unwrap_result(result)
        case result
        in [model, Command::Cmd => cmd]
          [model, cmd]
        in [model, Array => cmds] if cmds.all? { |c| c.is_a?(Command::Cmd) }
          [model, Command.batch(cmds)]
        else
          [result, Command.none]
        end
      end

      def build_selector(selector)
        case selector
        when String
          if selector.start_with?("#")
            resolve_id_selector(selector)
          else
            {by: "text", value: selector}
          end
        when Hash then selector
        when :focused then {by: "focused"}
        else {by: "text", value: selector.to_s}
        end
      end

      def resolve_id_selector(selector)
        window_id, widget_id = parse_id_selector(selector)
        return {by: "id", value: widget_id, window_id: window_id} unless @tree

        exact_matches = find_exact_id_targets(@tree, widget_id)
        exact_matches.select! { |match| match[:window_id] == window_id } if window_id

        if exact_matches.length == 1
          match = exact_matches.first
          return {by: "id", value: match[:id], window_id: match[:window_id]}
        end

        if widget_id.include?("/")
          if exact_matches.length > 1
            raise Plushie::Error, "Selector #{selector.inspect} matches multiple windows. Prefix it with \"#<window_id>::\"."
          end

          return window_id ? {by: "id", value: widget_id, window_id: window_id} : {by: "id", value: widget_id}
        end

        local_matches = find_local_id_targets(@tree, widget_id)
        local_matches.select! { |match| match[:window_id] == window_id } if window_id

        if local_matches.length == 1
          match = local_matches.first
          return {by: "id", value: match[:id], window_id: match[:window_id]}
        end

        if local_matches.length > 1
          raise Plushie::Error,
            "Selector #{selector.inspect} is ambiguous across windows. Prefix it with \"#<window_id>::\" or use the full scoped id."
        end

        window_id ? {by: "id", value: widget_id, window_id: window_id} : {by: "id", value: widget_id}
      end

      def parse_id_selector(selector)
        raw = selector[1..]
        if raw.include?("::")
          raw.split("::", 2)
        else
          [nil, raw]
        end
      end

      def find_exact_id_targets(node, target_id, current_window_id = nil, matches = [])
        node_window_id = if node.type == "window"
          node.id
        else
          current_window_id
        end
        matches << {id: node.id, window_id: node_window_id} if node_window_id && node.id == target_id

        node.children.each do |child|
          find_exact_id_targets(child, target_id, node_window_id, matches)
        end

        matches
      end

      def find_local_id_targets(node, local_id, current_window_id = nil, matches = [])
        node_window_id = if node.type == "window"
          node.id
        else
          current_window_id
        end
        matches << {id: node.id, window_id: node_window_id} if node_window_id && node.id.split("/").last == local_id

        node.children.each do |child|
          find_local_id_targets(child, local_id, node_window_id, matches)
        end

        matches
      end

      def find_in_local_tree(selector)
        return nil unless @tree
        _window_id, id = parse_id_selector(selector.start_with?("#") ? selector : "##{selector}")
        Tree.find(@tree, id) || begin
          matches = find_local_id_targets(@tree, id)
          match = matches.one? ? matches.first : nil
          match ? Tree.find(@tree, match[:id]) : nil
        end
      end

      def node_prop(node, key)
        return nil unless node
        props = node.is_a?(Hash) ? (node[:props] || node["props"] || {}) : node.props
        props[key.to_sym] || props[key.to_s]
      end

      # Valid modifier prefixes for key combos (case-insensitive).
      VALID_MODIFIERS = {
        "shift" => "Shift",
        "ctrl" => "Ctrl",
        "alt" => "Alt",
        "logo" => "Logo",
        "command" => "Command"
      }.freeze

      # Case-insensitive lookup for named keys. Maps downcased input
      # to PascalCase wire format (matching what the renderer sends in events).
      NAMED_KEY_LOOKUP = Protocol::Keys::NAMED_KEYS.keys
        .each_with_object({}) { |name, h| h[name.downcase] = name }
        .freeze

      # Parse and validate a key string. Handles modifier prefixes
      # (e.g. "ctrl+s", "Shift+ArrowRight") and resolves key names
      # case-insensitively.
      #
      # @param key [String] raw key input
      # @return [String] normalized key string for the interact protocol
      # @raise [ArgumentError] on unknown modifier or key name
      def normalize_key(key)
        parts = key.split("+")
        key_name = parts.pop
        mod_parts = parts

        normalized_mods = mod_parts.map do |mod|
          wire = VALID_MODIFIERS[mod.downcase]
          unless wire
            raise ArgumentError,
              "unknown modifier #{mod.inspect} in key #{key.inspect}. " \
              "Valid: Shift, Ctrl, Alt, Logo, Command"
          end
          wire
        end

        # Single characters pass through (lowercased for iced).
        # Named keys are resolved case-insensitively to PascalCase.
        normalized_key = if key_name.length == 1
          key_name.downcase
        elsif (resolved = NAMED_KEY_LOOKUP[key_name.downcase])
          resolved
        else
          raise ArgumentError,
            "unknown key #{key_name.inspect} in #{key.inspect}. " \
            "Examples: Tab, ArrowRight, PageUp, Escape, Enter. " \
            "See Plushie::Protocol::Keys::NAMED_KEYS for the full list"
        end

        if normalized_mods.empty?
          normalized_key
        else
          (normalized_mods + [normalized_key]).join("+")
        end
      end

      # Intercept diagnostic events, accumulate them instead of dispatching.
      # Returns true if the event was intercepted.
      def intercept_diagnostic(event)
        return false unless event.is_a?(Event::System) && event.type == :diagnostic
        @diagnostics << event
        true
      end

      def extract_events(response)
        raw = response[:events] || response["events"] || []
        raw.filter_map do |e|
          if e.is_a?(Hash)
            Protocol::Decode.decode_event(e.transform_keys(&:to_s))
          else
            e
          end
        end
      end

      # Find IDs similar to the target using substring matching and
      # Levenshtein-like distance. Returns up to 3 suggestions.
      #
      # @param target [String] the ID we searched for
      # @param all_ids [Array<String>] all IDs in the tree
      # @return [Array<String>] similar IDs, closest first
      def find_similar_ids(target, all_ids, max: 3)
        return [] if target.nil? || target.empty?

        scored = all_ids.filter_map do |id|
          local = id.split("/").last
          # Exact substring match scores highest
          if local.include?(target) || target.include?(local)
            [id, 0]
          else
            dist = levenshtein(target.downcase, local.downcase)
            (dist <= [target.length / 2, 3].max) ? [id, dist] : nil
          end
        end

        scored.sort_by(&:last).first(max).map(&:first)
      end

      # Simple Levenshtein distance for "did you mean" suggestions.
      # @param a [String]
      # @param b [String]
      # @return [Integer]
      def levenshtein(a, b)
        return b.length if a.empty?
        return a.length if b.empty?

        matrix = Array.new(a.length + 1) { |i|
          Array.new(b.length + 1) { |j|
            (if i.zero?
               j
             else
               (j.zero? ? i : 0)
             end)
          }
        }

        (1..a.length).each do |i|
          (1..b.length).each do |j|
            cost = (a[i - 1] == b[j - 1]) ? 0 : 1
            matrix[i][j] = [
              matrix[i - 1][j] + 1,     # deletion
              matrix[i][j - 1] + 1,     # insertion
              matrix[i - 1][j - 1] + cost # substitution
            ].min
          end
        end

        matrix[a.length][b.length]
      end
    end
  end
end
