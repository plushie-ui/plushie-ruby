# frozen_string_literal: true

require "json"

module Plushie
  module Protocol
    # Inbound message decoding from the wire protocol.
    #
    # Handles all response types and all 57 event families as defined
    # in protocol.md. The canonical reference is:
    # ~/projects/toddy-elixir/lib/plushie/protocol/decode.ex
    #
    # @see ~/projects/plushie/docs/protocol.md "Outgoing messages"
    module Decode
      module_function

      # Deserialize raw wire bytes into a Ruby hash.
      #
      # @param data [String] raw wire bytes
      # @param format [:msgpack, :json]
      # @return [Hash]
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

      # Decode a wire message into a typed Ruby struct or hash.
      #
      # Dispatches on the "type" field to the appropriate decoder.
      # Returns nil for decode errors.
      #
      # @param data [String] raw wire bytes
      # @param format [:msgpack, :json]
      # @return [Event::*, Hash, nil]
      def decode_message(data, format = :msgpack)
        msg = decode(data, format)
        return nil if msg.key?("error")
        dispatch_message(msg)
      end

      # Dispatch an already-deserialized message hash.
      #
      # @param msg [Hash] deserialized message with string keys
      # @return [Event::*, Hash, nil]
      def dispatch_message(msg)
        case msg["type"]
        when "event"              then decode_event(msg)
        when "hello"              then decode_hello(msg)
        when "effect_response"    then decode_effect_response(msg)
        when "query_response"     then decode_query_response(msg)
        when "op_query_response"  then decode_op_query_response(msg)
        when "interact_response"  then decode_interact_response(msg)
        when "interact_step"      then decode_interact_step(msg)
        when "tree_hash_response" then decode_tree_hash_response(msg)
        when "screenshot_response" then decode_screenshot_response(msg)
        when "reset_response"     then decode_reset_response(msg)
        else msg
        end
      end

      # -------------------------------------------------------------------
      # Event decoding -- all 57 families
      # -------------------------------------------------------------------

      # Decode an event message into the appropriate Event struct.
      #
      # @param msg [Hash] deserialized event message
      # @return [Event::*, nil]
      def decode_event(msg)
        family = msg["family"]
        data = msg["data"] || {}

        case family

        # -- Widget events -> Event::Widget -----------------------------------

        when "click", "input", "submit", "toggle", "select",
          "slide", "slide_release", "paste", "option_hovered",
          "open", "close", "key_binding", "sort", "scroll",
          "canvas_shape_enter", "canvas_shape_leave",
          "canvas_shape_click", "canvas_shape_drag",
          "canvas_shape_drag_end", "canvas_shape_focused"
          id, scope = split_scoped_id(msg["id"])
          Event::Widget.new(
            type: family.to_sym, id: id,
            value: msg["value"], scope: scope, data: msg["data"]
          )

        # -- Mouse area events -> Event::MouseArea ----------------------------

        when "mouse_right_press", "mouse_right_release",
          "mouse_middle_press", "mouse_middle_release",
          "mouse_double_click", "mouse_enter", "mouse_exit"
          id, scope = split_scoped_id(msg["id"])
          type = family.delete_prefix("mouse_").to_sym
          Event::MouseArea.new(type: type, id: id, scope: scope)

        when "mouse_move"
          id, scope = split_scoped_id(msg["id"])
          Event::MouseArea.new(
            type: :move, id: id, scope: scope,
            x: data["x"], y: data["y"]
          )

        when "mouse_scroll"
          id, scope = split_scoped_id(msg["id"])
          Event::MouseArea.new(
            type: :scroll, id: id, scope: scope,
            delta_x: data["delta_x"], delta_y: data["delta_y"]
          )

        # -- Canvas events -> Event::Canvas -----------------------------------

        when "canvas_press", "canvas_release"
          id, scope = split_scoped_id(msg["id"])
          type = (family == "canvas_press") ? :press : :release
          Event::Canvas.new(
            type: type, id: id, scope: scope,
            x: data["x"], y: data["y"],
            button: data["button"]
          )

        when "canvas_move"
          id, scope = split_scoped_id(msg["id"])
          Event::Canvas.new(
            type: :move, id: id, scope: scope,
            x: data["x"], y: data["y"]
          )

        when "canvas_scroll"
          id, scope = split_scoped_id(msg["id"])
          Event::Canvas.new(
            type: :scroll, id: id, scope: scope,
            x: data["x"], y: data["y"],
            delta_x: data["delta_x"], delta_y: data["delta_y"]
          )

        # -- Pane events -> Event::Pane ---------------------------------------

        when "pane_resized"
          id, scope = split_scoped_id(msg["id"])
          Event::Pane.new(
            type: :resized, id: id, scope: scope,
            split: data["split"], ratio: data["ratio"]
          )

        when "pane_dragged"
          id, scope = split_scoped_id(msg["id"])
          Event::Pane.new(
            type: :dragged, id: id, scope: scope,
            pane: data["pane"], target: data["target"]
          )

        when "pane_clicked"
          id, scope = split_scoped_id(msg["id"])
          Event::Pane.new(
            type: :clicked, id: id, scope: scope,
            pane: data["pane"]
          )

        when "pane_focus_cycle"
          id, scope = split_scoped_id(msg["id"])
          Event::Pane.new(
            type: :focus_cycle, id: id, scope: scope,
            pane: data["pane"]
          )

        # -- Sensor events -> Event::Sensor -----------------------------------

        when "sensor_resize"
          id, scope = split_scoped_id(msg["id"])
          Event::Sensor.new(
            type: :resize, id: id, scope: scope,
            width: data["width"], height: data["height"]
          )

        # -- Keyboard events -> Event::Key ------------------------------------

        when "key_press", "key_release"
          type = (family == "key_press") ? :press : :release
          key_data = data.empty? ? msg : data
          Event::Key.new(
            type: type,
            key: Keys.parse_key(key_data["key"] || msg["key"]),
            modified_key: key_data["modified_key"] || msg["modified_key"],
            physical_key: Keys.parse_physical_key(key_data["physical_key"] || msg["physical_key"]),
            location: Keys.parse_location(key_data["location"] || msg["location"]),
            modifiers: parse_modifiers(msg["modifiers"] || key_data["modifiers"] || {}),
            text: key_data["text"] || msg["text"],
            repeat: key_data["repeat"] || msg["repeat"] || false,
            captured: msg["captured"] || false
          )

        # -- Modifier events -> Event::Modifiers ------------------------------

        when "modifiers_changed"
          Event::Modifiers.new(
            modifiers: parse_modifiers(msg["modifiers"] || data["modifiers"] || {}),
            captured: msg["captured"] || false
          )

        # -- Mouse subscription events -> Event::Mouse -----------------------

        when "cursor_moved"
          Event::Mouse.new(
            type: :moved,
            x: data["x"], y: data["y"],
            captured: msg["captured"] || false
          )

        when "cursor_entered"
          Event::Mouse.new(type: :entered, captured: msg["captured"] || false)

        when "cursor_left"
          Event::Mouse.new(type: :left, captured: msg["captured"] || false)

        when "button_pressed"
          Event::Mouse.new(
            type: :button_pressed,
            button: Parsers.parse_mouse_button(msg["value"]),
            captured: msg["captured"] || false
          )

        when "button_released"
          Event::Mouse.new(
            type: :button_released,
            button: Parsers.parse_mouse_button(msg["value"]),
            captured: msg["captured"] || false
          )

        when "wheel_scrolled"
          Event::Mouse.new(
            type: :wheel_scrolled,
            delta_x: data["delta_x"], delta_y: data["delta_y"],
            unit: Parsers.parse_scroll_unit(data["unit"]),
            captured: msg["captured"] || false
          )

        # -- Touch events -> Event::Touch -------------------------------------

        when "finger_pressed", "finger_moved", "finger_lifted", "finger_lost"
          type = family.delete_prefix("finger_").to_sym
          Event::Touch.new(
            type: type,
            finger_id: data["id"],
            x: data["x"], y: data["y"],
            captured: msg["captured"] || false
          )

        # -- IME events -> Event::Ime -----------------------------------------

        when "ime_opened"
          Event::Ime.new(type: :opened, captured: msg["captured"] || false)

        when "ime_preedit"
          Event::Ime.new(
            type: :preedit,
            text: data["text"],
            cursor: data["cursor"],
            captured: msg["captured"] || false
          )

        when "ime_commit"
          Event::Ime.new(
            type: :commit,
            text: data["text"],
            captured: msg["captured"] || false
          )

        when "ime_closed"
          Event::Ime.new(type: :closed, captured: msg["captured"] || false)

        # -- Window subscription events -> Event::Window ----------------------

        when "window_opened"
          pos = data["position"] || {}
          Event::Window.new(
            type: :opened, window_id: data["window_id"],
            x: pos["x"], y: pos["y"],
            width: data["width"], height: data["height"],
            scale_factor: data["scale_factor"]
          )

        when "window_closed"
          Event::Window.new(type: :closed, window_id: data["window_id"])

        when "window_close_requested"
          Event::Window.new(type: :close_requested, window_id: data["window_id"])

        when "window_moved"
          Event::Window.new(
            type: :moved, window_id: data["window_id"],
            x: data["x"], y: data["y"]
          )

        when "window_resized"
          Event::Window.new(
            type: :resized, window_id: data["window_id"],
            width: data["width"], height: data["height"]
          )

        when "window_focused"
          Event::Window.new(type: :focused, window_id: data["window_id"])

        when "window_unfocused"
          Event::Window.new(type: :unfocused, window_id: data["window_id"])

        when "window_rescaled"
          Event::Window.new(
            type: :rescaled, window_id: data["window_id"],
            scale_factor: data["scale_factor"]
          )

        when "file_hovered"
          Event::Window.new(
            type: :file_hovered, window_id: data["window_id"],
            path: data["path"]
          )

        when "file_dropped"
          Event::Window.new(
            type: :file_dropped, window_id: data["window_id"],
            path: data["path"]
          )

        when "files_hovered_left"
          Event::Window.new(type: :files_hovered_left, window_id: data["window_id"])

        # -- System events -> Event::System -----------------------------------

        when "animation_frame"
          Event::System.new(type: :animation_frame, data: data["timestamp"] || msg["value"])

        when "theme_changed"
          Event::System.new(type: :theme_changed, data: msg["value"] || data["mode"])

        when "all_windows_closed"
          Event::System.new(type: :all_windows_closed)

        when "error"
          Event::System.new(type: :error, data: data)

        when "announce"
          Event::System.new(type: :announce, data: data["text"])

        when "session_error"
          Event::System.new(type: :session_error, data: data)

        when "session_closed"
          Event::System.new(type: :session_closed, data: data)

        # -- Fallback: extension/unknown events -> Event::Widget --------------

        else
          if msg["id"]
            id, scope = split_scoped_id(msg["id"])
            Event::Widget.new(
              type: family&.to_sym, id: id,
              value: msg["value"], scope: scope, data: msg["data"]
            )
          end
        end
      end

      # -------------------------------------------------------------------
      # Response decoders
      # -------------------------------------------------------------------

      # Decode the hello handshake message.
      #
      # @param msg [Hash]
      # @return [Hash] with :type, :protocol, :version, :name, :mode, :backend, :extensions, :transport
      def decode_hello(msg)
        {
          type: :hello,
          protocol: msg["protocol"],
          version: msg["version"],
          name: msg["name"],
          mode: msg["mode"]&.to_sym,
          backend: msg["backend"],
          extensions: msg["extensions"] || [],
          transport: msg["transport"]
        }
      end

      # Decode an effect response (file dialog result, clipboard, etc.).
      # Uses the status field per protocol.md: "ok", "cancelled", "error".
      #
      # @param msg [Hash]
      # @return [Event::Effect]
      def decode_effect_response(msg)
        result = case msg["status"]
        when "ok"        then [:ok, msg["result"]]
        when "cancelled" then :cancelled
        when "error"     then [:error, msg["error"]]
        else
          # Legacy fallback for older renderers
          if msg["error"]
            [:error, msg["error"]]
          elsif msg["cancelled"]
            :cancelled
          else
            [:ok, msg["result"] || msg["data"]]
          end
        end
        Event::Effect.new(request_id: msg["id"], result: result)
      end

      # Decode a query response (find, tree).
      #
      # @param msg [Hash]
      # @return [Hash] with :type, :id, :target, :data
      def decode_query_response(msg)
        {
          type: :query_response,
          id: msg["id"],
          target: msg["target"],
          data: msg["data"]
        }
      end

      # Decode an op query response (tree_hash, find_focused, system_theme, etc.).
      #
      # @param msg [Hash]
      # @return [Hash] with :type, :kind, :tag, :data
      def decode_op_query_response(msg)
        {
          type: :op_query_response,
          kind: msg["kind"]&.to_sym,
          tag: msg["tag"],
          data: msg["data"]
        }
      end

      # Decode an interact response (final response after all steps).
      # Embedded events are decoded recursively.
      #
      # @param msg [Hash]
      # @return [Hash] with :type, :id, :session, :events
      def decode_interact_response(msg)
        events = (msg["events"] || []).filter_map { |e| decode_event(e) }
        {
          type: :interact_response,
          id: msg["id"],
          session: msg["session"],
          events: events
        }
      end

      # Decode an interact step (intermediate events from headless mode).
      # Embedded events are decoded recursively.
      #
      # @param msg [Hash]
      # @return [Hash] with :type, :id, :session, :events
      def decode_interact_step(msg)
        events = (msg["events"] || []).filter_map { |e| decode_event(e) }
        {
          type: :interact_step,
          id: msg["id"],
          session: msg["session"],
          events: events
        }
      end

      # Decode a tree hash response.
      #
      # @param msg [Hash]
      # @return [Hash] with :type, :id, :name, :hash
      def decode_tree_hash_response(msg)
        {
          type: :tree_hash_response,
          id: msg["id"],
          name: msg["name"],
          hash: msg["hash"]
        }
      end

      # Decode a screenshot response.
      #
      # @param msg [Hash]
      # @return [Hash] with :type, :id, :name, :hash, :width, :height, :rgba
      def decode_screenshot_response(msg)
        {
          type: :screenshot_response,
          id: msg["id"],
          name: msg["name"],
          hash: msg["hash"],
          width: msg["width"],
          height: msg["height"],
          rgba: msg["rgba"]
        }
      end

      # Decode a reset response.
      #
      # @param msg [Hash]
      # @return [Hash] with :type, :id, :status
      def decode_reset_response(msg)
        {
          type: :reset_response,
          id: msg["id"],
          status: msg["status"]
        }
      end

      # -------------------------------------------------------------------
      # Helpers
      # -------------------------------------------------------------------

      # Split a scoped wire ID into local ID and scope array.
      # Wire sends "sidebar/form/save"; we split to id: "save",
      # scope: ["form", "sidebar"] (reversed, immediate parent first).
      #
      # @param full_id [String, nil]
      # @return [Array(String, Array<String>)]
      def split_scoped_id(full_id)
        return [full_id.to_s, []] unless full_id&.include?("/")
        parts = full_id.split("/")
        id = parts.pop
        [id, parts.reverse]
      end

      # Parse a modifiers hash from the wire format.
      #
      # @param mods [Hash] wire modifiers (string keys)
      # @return [Hash] frozen hash with symbol keys
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
