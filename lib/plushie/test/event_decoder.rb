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
      # @return [Event::Widget, Event::Key, Event::Mouse, nil]
      def decode(raw)
        return nil unless raw.is_a?(Hash)

        family = raw["family"]
        data = raw["data"] || {}

        case family

        # Widget interactions (the most common in tests)
        when "click", "input", "submit", "toggle", "select", "slide", "slide_release"
          id, scope = split_scoped_id(raw["id"])
          Event::Widget.new(
            type: family.to_sym, id: id,
            value: raw["value"], scope: scope, data: raw["data"]
          )

        # Key events
        when "key_press"
          kd = data.empty? ? raw : data
          Event::Key.new(
            type: :press,
            key: Protocol::Keys.parse_key(kd["key"]),
            modifiers: parse_modifiers(raw["modifiers"] || kd["modifiers"] || {}),
            text: kd["text"],
            repeat: kd["repeat"] || false
          )

        when "key_release"
          kd = data.empty? ? raw : data
          Event::Key.new(
            type: :release,
            key: Protocol::Keys.parse_key(kd["key"]),
            modifiers: parse_modifiers(raw["modifiers"] || kd["modifiers"] || {}),
            text: nil,
            repeat: false
          )

        # Mouse subscription events
        when "cursor_moved"
          Event::Mouse.new(type: :moved, x: data["x"], y: data["y"])

        when "button_pressed"
          Event::Mouse.new(
            type: :button_pressed,
            button: Protocol::Parsers.parse_mouse_button(raw["value"])
          )

        when "button_released"
          Event::Mouse.new(
            type: :button_released,
            button: Protocol::Parsers.parse_mouse_button(raw["value"])
          )

        else
          # Unrecognized family
          nil
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
    end
  end
end
