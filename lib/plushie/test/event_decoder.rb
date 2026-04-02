# frozen_string_literal: true

module Plushie
  module Test
    # Simplified event decoder for test context.
    #
    # Converts raw wire event hashes (from interact_response / interact_step)
    # into Ruby Event structs. Handles the subset of event families commonly
    # seen in tests. Returns nil for unrecognized families.
    #
    # For production decoding, use Plushie::Protocol::Decode.decode_event.
    # This module exists as a lighter-weight alternative that test helpers
    # can use without pulling in the full protocol layer.
    module EventDecoder
      module_function

      # Decode a raw wire event hash into an Event struct.
      #
      # @param raw [Hash] wire event with string keys
      # @return [Event::Widget, Event::Key, nil]
      def decode(raw)
        return nil unless raw.is_a?(Hash)

        family = raw["family"]
        data = raw["data"] || {}

        case family

        # Standard widget events
        when "click", "input", "submit", "toggle", "select", "slide", "slide_release",
          "sort", "scrolled", "open", "close", "key_binding", "paste", "option_hovered"
          id, scope = split_scoped_id(raw["id"])
          Event::Widget.new(
            type: family.to_sym, id: id,
            value: raw["value"], window_id: raw["window_id"], scope: scope, data: raw["data"]
          )

        # Unified pointer events
        when "press", "release", "move", "scroll", "enter", "exit",
          "double_click", "resize"
          id, scope = split_scoped_id(raw["id"])
          Event::Widget.new(
            type: family.to_sym, id: id,
            window_id: raw["window_id"], scope: scope, data: atomize_data(data)
          )

        # Generic element events
        when "focused", "blurred", "drag", "drag_end"
          id, scope = split_scoped_id(raw["id"])
          Event::Widget.new(
            type: family.to_sym, id: id,
            window_id: raw["window_id"], scope: scope, data: atomize_data(data)
          )

        # Pane events
        when "pane_resized", "pane_dragged", "pane_clicked", "pane_focus_cycle"
          id, scope = split_scoped_id(raw["id"])
          Event::Widget.new(
            type: family.to_sym, id: id,
            window_id: raw["window_id"], scope: scope, data: atomize_data(data)
          )

        # Transition complete
        when "transition_complete"
          id, scope = split_scoped_id(raw["id"])
          Event::Widget.new(
            type: :transition_complete, id: id,
            window_id: raw["window_id"], scope: scope,
            data: {tag: data["tag"]&.to_sym, prop: data["prop"]}
          )

        # Global key events (no id)
        when "key_press"
          if raw["id"] && !raw["id"].empty?
            id, scope = split_scoped_id(raw["id"])
            Event::Widget.new(
              type: :key_press, id: id, window_id: raw["window_id"], scope: scope,
              data: {key: Protocol::Keys.parse_key(data["key"]), modifiers: parse_modifiers(data["modifiers"])}
            )
          else
            kd = data.empty? ? raw : data
            Event::Key.new(
              type: :press,
              key: Protocol::Keys.parse_key(kd["key"]),
              modifiers: parse_modifiers(raw["modifiers"] || kd["modifiers"] || {}),
              text: kd["text"],
              repeat: kd["repeat"] || false
            )
          end

        when "key_release"
          if raw["id"] && !raw["id"].empty?
            id, scope = split_scoped_id(raw["id"])
            Event::Widget.new(
              type: :key_release, id: id, window_id: raw["window_id"], scope: scope,
              data: {key: Protocol::Keys.parse_key(data["key"]), modifiers: parse_modifiers(data["modifiers"])}
            )
          else
            kd = data.empty? ? raw : data
            Event::Key.new(
              type: :release,
              key: Protocol::Keys.parse_key(kd["key"]),
              modifiers: parse_modifiers(raw["modifiers"] || kd["modifiers"] || {}),
              text: nil,
              repeat: false
            )
          end

        # Subscription pointer events
        when "cursor_moved"
          window_id = raw["window_id"]
          Event::Widget.new(
            type: :move, id: window_id || "__global__", scope: [], window_id: window_id,
            data: {x: data["x"], y: data["y"], pointer: :mouse}
          )

        when "button_pressed"
          window_id = raw["window_id"]
          Event::Widget.new(
            type: :press, id: window_id || "__global__", scope: [], window_id: window_id,
            data: {button: Protocol::Parsers.parse_mouse_button(raw["value"]), pointer: :mouse}
          )

        when "button_released"
          window_id = raw["window_id"]
          Event::Widget.new(
            type: :release, id: window_id || "__global__", scope: [], window_id: window_id,
            data: {button: Protocol::Parsers.parse_mouse_button(raw["value"]), pointer: :mouse}
          )

        end
      end

      # Split a scoped wire ID (same logic as Protocol::Decode).
      #
      # @param full_id [String, nil]
      # @return [Array(String, Array<String>)]
      def split_scoped_id(full_id)
        return [full_id.to_s, []] unless full_id&.include?("/")
        parts = full_id.split("/")
        id = parts.pop
        [id, parts.reverse]
      end

      # Parse a modifiers hash.
      #
      # @param mods [Hash, nil]
      # @return [Hash]
      def parse_modifiers(mods)
        return {shift: false, ctrl: false, alt: false, logo: false, command: false}.freeze if mods.nil? || mods.empty?
        {
          shift: mods["shift"] || false,
          ctrl: mods["ctrl"] || false,
          alt: mods["alt"] || false,
          logo: mods["logo"] || false,
          command: mods["command"] || false
        }.freeze
      end

      # Convert string-keyed wire data to symbol-keyed hash.
      def atomize_data(data)
        return nil unless data.is_a?(Hash)
        data.transform_keys(&:to_sym)
      end
    end
  end
end
