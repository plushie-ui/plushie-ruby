# frozen_string_literal: true

module Plushie
  module Protocol
    # Inbound message decoding from the wire protocol.
    module Decode
      module_function

      def decode(data, format = :msgpack)
        case format
        when :json
          JSON.parse(data)
        when :msgpack
          require "msgpack"
          MessagePack.unpack(data)
        end
      rescue => e
        {"error" => e.message}
      end

      def decode_message(data, format = :msgpack)
        msg = decode(data, format)
        return nil if msg.key?("error")

        case msg["type"]
        when "event"
          decode_event(msg)
        when "hello"
          decode_hello(msg)
        when "effect_response"
          decode_effect_response(msg)
        when "query_response"
          decode_query_response(msg)
        else
          msg
        end
      end

      def decode_event(msg)
        family = msg["family"]

        case family
        when "click", "input", "submit", "toggle", "select",
          "slide", "slide_release", "paste", "open", "close",
          "option_hovered", "key_binding", "sort", "scroll",
          "canvas_shape_enter", "canvas_shape_leave",
          "canvas_shape_click", "canvas_shape_drag",
          "canvas_shape_drag_end", "canvas_shape_focused"
          id, scope = split_scoped_id(msg["id"])
          Event::Widget.new(
            type: family.to_sym,
            id:,
            value: msg["value"],
            scope:,
            data: msg["data"]
          )
        when "key_press", "key_release"
          Event::Key.new(
            type: (family == "key_press") ? :press : :release,
            key: parse_key(msg["key"]),
            modified_key: msg["modified_key"],
            physical_key: msg["physical_key"]&.to_sym,
            modifiers: parse_modifiers(msg["modifiers"] || {}),
            text: msg["text"],
            repeat: msg["repeat"] || false,
            captured: msg["captured"] || false
          )
        when "close_requested", "opened", "closed", "moved",
          "resized", "focused", "unfocused", "rescaled",
          "file_hovered", "file_dropped", "files_hovered_left"
          Event::Window.new(
            type: family.to_sym,
            window_id: msg["window_id"],
            x: msg["x"],
            y: msg["y"],
            width: msg["width"],
            height: msg["height"],
            scale_factor: msg["scale_factor"],
            path: msg["path"]
          )
        when "timer"
          Event::Timer.new(tag: msg["tag"]&.to_sym, timestamp: msg["timestamp"])
        when "theme_changed", "animation_frame"
          Event::System.new(type: family.to_sym, data: msg["data"])
        when "system_theme", "system_info"
          Event::System.new(type: family.to_sym, tag: msg["tag"], data: msg["data"])
        else
          msg
        end
      end

      def decode_hello(msg)
        {
          type: :hello,
          protocol: msg["protocol"],
          version: msg["version"],
          name: msg["name"],
          backend: msg["backend"],
          extensions: msg["extensions"] || [],
          transport: msg["transport"]
        }
      end

      def decode_effect_response(msg)
        result = if msg["error"]
          [:error, msg["error"]]
        elsif msg["cancelled"]
          :cancelled
        else
          [:ok, msg["data"]]
        end
        Event::Effect.new(request_id: msg["id"], result:)
      end

      def decode_query_response(msg)
        Event::System.new(
          type: msg["kind"]&.to_sym,
          tag: msg["tag"],
          data: msg["data"]
        )
      end

      def split_scoped_id(full_id)
        return [full_id, []] unless full_id&.include?("/")
        parts = full_id.split("/")
        id = parts.pop
        [id, parts.reverse]
      end

      def parse_key(key)
        return nil if key.nil?
        return key if key.length == 1
        key.downcase.gsub(" ", "_").to_sym
      end

      def parse_modifiers(mods)
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
