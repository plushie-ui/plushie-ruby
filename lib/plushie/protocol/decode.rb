# frozen_string_literal: true

require "json"

module Plushie
  module Protocol
    # Inbound message decoding from the wire protocol.
    #
    # Handles all response types and event families as defined in
    # the wire protocol (~/projects/plushie-renderer/docs/protocol.md).
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
        else
          raise ArgumentError, "unsupported protocol format: #{format.inspect}"
        end
      rescue JSON::ParserError, MessagePack::MalformedFormatError,
        MessagePack::UnpackError, MessagePack::TypeError => e
        {"error" => e.message}
      rescue ArgumentError => e
        # msgpack gem raises ArgumentError for some malformed inputs
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
        when "event" then decode_event(msg)
        when "hello" then decode_hello(msg)
        when "effect_response" then decode_effect_response(msg)
        when "query_response" then decode_query_response(msg)
        when "op_query_response" then decode_op_query_response(msg)
        when "interact_response" then decode_interact_response(msg)
        when "interact_step" then decode_interact_step(msg)
        when "tree_hash_response" then decode_tree_hash_response(msg)
        when "screenshot_response" then decode_screenshot_response(msg)
        when "reset_response" then decode_reset_response(msg)
        when "effect_stub_registered", "effect_stub_unregistered"
          {type: :effect_stub_ack, kind: msg["kind"]}
        else msg
        end
      end

      # -------------------------------------------------------------------
      # Event decoding: all 57 families
      # -------------------------------------------------------------------

      # Decode an event message into the appropriate Event struct.
      #
      # Events from the main protocol stream always include window_id.
      # Events embedded in interact_response/interact_step may omit it
      # (the mock renderer doesn't always include it). Pass
      # +require_window_id: false+ when decoding embedded events.
      #
      # @param msg [Hash] deserialized event message
      # @param require_window_id [Boolean] raise on missing window_id (default: true)
      # @return [Event::*, nil]
      def decode_event(msg, require_window_id: true)
        event = decode_event_inner(msg, require_window_id: require_window_id)

        # Append window_id to scope for widget events that came from a
        # scoped widget ID. Subscription pointer events (id = window_id,
        # scope = []) should NOT get window_id appended since they're
        # global events, not scoped to a widget path.
        if event.is_a?(Event::Widget) && event.window_id &&
            !(event.scope.empty? && (event.id == event.window_id || event.id == "__global__"))
          unless event.scope.include?(event.window_id)
            event = event.with(scope: event.scope + [event.window_id])
          end
        end

        event
      end

      def decode_event_inner(msg, require_window_id: true)
        family = msg["family"]
        data = msg["data"] || {}
        window_id_fn = require_window_id ? method(:require_window_id!) : method(:optional_window_id)

        case family

        # -- Widget events -> Event::Widget -----------------------------------

        when "click", "input", "submit", "toggle", "select",
          "slide", "slide_release", "paste", "option_hovered",
          "open", "close", "key_binding"
          id, scope = split_scoped_id(msg["id"])
          Event::Widget.new(
            type: family.to_sym, id: id,
            value: msg["value"], window_id: window_id_fn.call(msg, family),
            scope: scope, data: msg["data"]
          )

        when "sort"
          id, scope = split_scoped_id(msg["id"])
          Event::Widget.new(
            type: :sort, id: id, window_id: window_id_fn.call(msg, family),
            scope: scope, data: {column: data["column"]}
          )

        when "scrolled"
          id, scope = split_scoped_id(msg["id"])
          Event::Widget.new(
            type: :scrolled, id: id, window_id: window_id_fn.call(msg, family),
            scope: scope, data: {
              absolute_x: data["absolute_x"], absolute_y: data["absolute_y"],
              relative_x: data["relative_x"], relative_y: data["relative_y"],
              bounds: data["bounds"], content_bounds: data["content_bounds"]
            }
          )

        # -- Unified pointer events -> Event::Widget ----------------------------
        # All pointer interactions (canvas, mouse_area, subscription) use the
        # same event types with device awareness in the data map.

        when "press"
          id, scope = split_scoped_id(msg["id"])
          Event::Widget.new(
            type: :press, id: id, window_id: window_id_fn.call(msg, family), scope: scope,
            data: {
              x: data["x"], y: data["y"],
              button: Parsers.parse_mouse_button(data["button"] || "left"),
              pointer: (data["pointer"] || "mouse").to_sym,
              finger: data["finger"],
              modifiers: parse_modifiers(data["modifiers"]),
              captured: data["captured"] || msg["captured"] || false
            }
          )

        when "release"
          id, scope = split_scoped_id(msg["id"])
          Event::Widget.new(
            type: :release, id: id, window_id: window_id_fn.call(msg, family), scope: scope,
            data: {
              x: data["x"], y: data["y"],
              button: Parsers.parse_mouse_button(data["button"] || "left"),
              pointer: (data["pointer"] || "mouse").to_sym,
              finger: data["finger"],
              modifiers: parse_modifiers(data["modifiers"]),
              captured: data["captured"] || msg["captured"] || false
            }
          )

        when "move"
          id, scope = split_scoped_id(msg["id"])
          Event::Widget.new(
            type: :move, id: id, window_id: window_id_fn.call(msg, family), scope: scope,
            data: {
              x: data["x"], y: data["y"],
              pointer: (data["pointer"] || "mouse").to_sym,
              finger: data["finger"],
              modifiers: parse_modifiers(data["modifiers"]),
              captured: data["captured"] || msg["captured"] || false
            }
          )

        when "scroll"
          id, scope = split_scoped_id(msg["id"])
          Event::Widget.new(
            type: :scroll, id: id, window_id: window_id_fn.call(msg, family), scope: scope,
            data: {
              x: data["x"], y: data["y"],
              delta_x: data["delta_x"], delta_y: data["delta_y"],
              unit: data["unit"] ? Parsers.parse_scroll_unit(data["unit"]) : nil,
              pointer: (data["pointer"] || "mouse").to_sym,
              modifiers: parse_modifiers(data["modifiers"]),
              captured: data["captured"] || msg["captured"] || false
            }
          )

        when "enter"
          id, scope = split_scoped_id(msg["id"])
          Event::Widget.new(
            type: :enter, id: id, window_id: window_id_fn.call(msg, family), scope: scope,
            data: {captured: data["captured"] || msg["captured"] || false}
          )

        when "exit"
          id, scope = split_scoped_id(msg["id"])
          Event::Widget.new(
            type: :exit, id: id, window_id: window_id_fn.call(msg, family), scope: scope,
            data: {captured: data["captured"] || msg["captured"] || false}
          )

        when "double_click"
          id, scope = split_scoped_id(msg["id"])
          Event::Widget.new(
            type: :double_click, id: id, window_id: window_id_fn.call(msg, family), scope: scope,
            data: {
              x: data["x"], y: data["y"],
              pointer: (data["pointer"] || "mouse").to_sym,
              modifiers: parse_modifiers(data["modifiers"])
            }
          )

        when "resize"
          id, scope = split_scoped_id(msg["id"])
          Event::Widget.new(
            type: :resize, id: id, window_id: window_id_fn.call(msg, family), scope: scope,
            data: {width: data["width"], height: data["height"]}
          )

        # -- Generic element events -> Event::Widget ----------------------------

        when "focused"
          id, scope = split_scoped_id(msg["id"])
          Event::Widget.new(
            type: :focused, id: id, window_id: window_id_fn.call(msg, family), scope: scope
          )

        when "blurred"
          id, scope = split_scoped_id(msg["id"])
          Event::Widget.new(
            type: :blurred, id: id, window_id: window_id_fn.call(msg, family), scope: scope
          )

        when "drag"
          id, scope = split_scoped_id(msg["id"])
          Event::Widget.new(
            type: :drag, id: id, window_id: window_id_fn.call(msg, family), scope: scope,
            data: {x: data["x"], y: data["y"], delta_x: data["delta_x"], delta_y: data["delta_y"]}
          )

        when "drag_end"
          id, scope = split_scoped_id(msg["id"])
          Event::Widget.new(
            type: :drag_end, id: id, window_id: window_id_fn.call(msg, family), scope: scope,
            data: atomize_data(data)
          )

        # -- Pane events -> Event::Widget --------------------------------------

        when "pane_resized"
          id, scope = split_scoped_id(msg["id"])
          Event::Widget.new(
            type: :pane_resized, id: id, window_id: window_id_fn.call(msg, family), scope: scope,
            data: {split: data["split"], ratio: data["ratio"]}
          )

        when "pane_dragged"
          id, scope = split_scoped_id(msg["id"])
          Event::Widget.new(
            type: :pane_dragged, id: id, window_id: window_id_fn.call(msg, family), scope: scope,
            data: {
              pane: data["pane"], target: data["target"],
              action: Parsers.parse_pane_action(data["action"]),
              region: Parsers.parse_pane_region(data["region"]),
              edge: Parsers.parse_pane_region(data["edge"])
            }
          )

        when "pane_clicked"
          id, scope = split_scoped_id(msg["id"])
          Event::Widget.new(
            type: :pane_clicked, id: id, window_id: window_id_fn.call(msg, family), scope: scope,
            data: {pane: data["pane"]}
          )

        when "pane_focus_cycle"
          id, scope = split_scoped_id(msg["id"])
          Event::Widget.new(
            type: :pane_focus_cycle, id: id, window_id: window_id_fn.call(msg, family), scope: scope,
            data: {pane: data["pane"]}
          )

        # -- Animation events -> Event::Widget ----------------------------------

        when "transition_complete"
          id, scope = split_scoped_id(msg["id"])
          tag = data["tag"]&.to_sym
          Event::Widget.new(
            type: :transition_complete, id: id,
            window_id: window_id_fn.call(msg, family),
            scope: scope, data: {tag: tag, prop: data["prop"]}
          )

        # -- Keyboard events -----------------------------------------------------
        # Global key events (no id or empty id) -> Event::Key.
        # Widget-scoped key events (non-empty id) -> Event::Widget with
        # type :key_press/:key_release.

        when "key_press"
          if msg["id"] && !msg["id"].empty?
            id, scope = split_scoped_id(msg["id"])
            Event::Widget.new(
              type: :key_press, id: id, window_id: window_id_fn.call(msg, family), scope: scope,
              data: {
                key: Keys.parse_key(data["key"]),
                modifiers: parse_modifiers(data["modifiers"])
              }
            )
          else
            kd = data.empty? ? msg : data
            Event::Key.new(
              type: :press,
              key: Keys.parse_key(kd["key"]),
              modified_key: Keys.parse_key(kd["modified_key"] || kd["key"]),
              physical_key: Keys.parse_physical_key(kd["physical_key"]),
              location: Keys.parse_location(kd["location"]),
              modifiers: parse_modifiers(msg["modifiers"] || kd["modifiers"] || {}),
              text: kd["text"],
              repeat: kd["repeat"] || false,
              captured: msg["captured"] || false,
              window_id: msg["window_id"]
            )
          end

        when "key_release"
          if msg["id"] && !msg["id"].empty?
            id, scope = split_scoped_id(msg["id"])
            Event::Widget.new(
              type: :key_release, id: id, window_id: window_id_fn.call(msg, family), scope: scope,
              data: {
                key: Keys.parse_key(data["key"]),
                modifiers: parse_modifiers(data["modifiers"])
              }
            )
          else
            kd = data.empty? ? msg : data
            Event::Key.new(
              type: :release,
              key: Keys.parse_key(kd["key"]),
              modified_key: Keys.parse_key(kd["modified_key"] || kd["key"]),
              physical_key: Keys.parse_physical_key(kd["physical_key"]),
              location: Keys.parse_location(kd["location"]),
              modifiers: parse_modifiers(msg["modifiers"] || kd["modifiers"] || {}),
              text: nil,
              repeat: false,
              captured: msg["captured"] || false,
              window_id: msg["window_id"]
            )
          end

        # -- Modifier events -> Event::Modifiers ------------------------------

        when "modifiers_changed"
          Event::Modifiers.new(
            modifiers: parse_modifiers(msg["modifiers"] || data["modifiers"] || {}),
            captured: msg["captured"] || false,
            window_id: msg["window_id"]
          )

        # -- Subscription pointer events -> Event::Widget ----------------------
        # Delivered as WidgetEvents with id = window_id and scope = [].

        when "cursor_moved"
          window_id = msg["window_id"]
          Event::Widget.new(
            type: :move,
            id: window_id || "__global__", scope: [], window_id: window_id,
            data: {
              x: data["x"], y: data["y"],
              pointer: :mouse,
              captured: msg["captured"] || false,
              modifiers: parse_modifiers(msg["modifiers"])
            }
          )

        when "cursor_entered"
          window_id = msg["window_id"]
          Event::Widget.new(
            type: :enter,
            id: window_id || "__global__", scope: [], window_id: window_id,
            data: {captured: msg["captured"] || false}
          )

        when "cursor_left"
          window_id = msg["window_id"]
          Event::Widget.new(
            type: :exit,
            id: window_id || "__global__", scope: [], window_id: window_id,
            data: {captured: msg["captured"] || false}
          )

        when "button_pressed"
          window_id = msg["window_id"]
          Event::Widget.new(
            type: :press,
            id: window_id || "__global__", scope: [], window_id: window_id,
            data: {
              button: Parsers.parse_mouse_button(msg["value"]),
              pointer: :mouse, x: nil, y: nil,
              captured: msg["captured"] || false,
              modifiers: parse_modifiers(msg["modifiers"])
            }
          )

        when "button_released"
          window_id = msg["window_id"]
          Event::Widget.new(
            type: :release,
            id: window_id || "__global__", scope: [], window_id: window_id,
            data: {
              button: Parsers.parse_mouse_button(msg["value"]),
              pointer: :mouse, x: nil, y: nil,
              captured: msg["captured"] || false,
              modifiers: parse_modifiers(msg["modifiers"])
            }
          )

        when "wheel_scrolled"
          window_id = msg["window_id"]
          Event::Widget.new(
            type: :scroll,
            id: window_id || "__global__", scope: [], window_id: window_id,
            data: {
              delta_x: data["delta_x"], delta_y: data["delta_y"],
              unit: Parsers.parse_scroll_unit(data["unit"]),
              pointer: :mouse,
              captured: msg["captured"] || false,
              modifiers: parse_modifiers(msg["modifiers"])
            }
          )

        # -- Touch subscription events -> Event::Widget ----------------------

        when "finger_pressed"
          window_id = msg["window_id"]
          Event::Widget.new(
            type: :press,
            id: window_id || "__global__", scope: [], window_id: window_id,
            data: {
              pointer: :touch, finger: data["id"],
              x: data["x"], y: data["y"], button: :left,
              captured: msg["captured"] || false,
              modifiers: parse_modifiers(msg["modifiers"])
            }
          )

        when "finger_moved"
          window_id = msg["window_id"]
          Event::Widget.new(
            type: :move,
            id: window_id || "__global__", scope: [], window_id: window_id,
            data: {
              pointer: :touch, finger: data["id"],
              x: data["x"], y: data["y"],
              captured: msg["captured"] || false,
              modifiers: parse_modifiers(msg["modifiers"])
            }
          )

        when "finger_lifted"
          window_id = msg["window_id"]
          Event::Widget.new(
            type: :release,
            id: window_id || "__global__", scope: [], window_id: window_id,
            data: {
              pointer: :touch, finger: data["id"],
              x: data["x"], y: data["y"],
              captured: msg["captured"] || false,
              modifiers: parse_modifiers(msg["modifiers"])
            }
          )

        when "finger_lost"
          window_id = msg["window_id"]
          Event::Widget.new(
            type: :release,
            id: window_id || "__global__", scope: [], window_id: window_id,
            data: {
              pointer: :touch, finger: data["id"],
              x: data["x"], y: data["y"], lost: true,
              captured: msg["captured"] || false,
              modifiers: parse_modifiers(msg["modifiers"])
            }
          )

        # -- IME events -> Event::Ime -----------------------------------------

        when "ime_opened"
          id, scope = split_scoped_id(msg["id"])
          Event::Ime.new(type: :opened, id: id, scope: scope,
            captured: msg["captured"] || false, window_id: msg["window_id"])

        when "ime_preedit"
          id, scope = split_scoped_id(msg["id"])
          Event::Ime.new(
            type: :preedit, id: id, scope: scope,
            text: data["text"],
            cursor: parse_ime_cursor(data["cursor"]),
            captured: msg["captured"] || false,
            window_id: msg["window_id"]
          )

        when "ime_commit"
          id, scope = split_scoped_id(msg["id"])
          Event::Ime.new(
            type: :commit, id: id, scope: scope,
            text: data["text"],
            captured: msg["captured"] || false,
            window_id: msg["window_id"]
          )

        when "ime_closed"
          id, scope = split_scoped_id(msg["id"])
          Event::Ime.new(type: :closed, id: id, scope: scope,
            captured: msg["captured"] || false, window_id: msg["window_id"])

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
          if msg["id"] == "extension_command"
            Event::WidgetCommandError.new(
              reason: data["reason"] || "",
              node_id: data["node_id"],
              op: data["op"],
              widget_type: data["extension"],
              message: data["message"]
            )
          else
            error_data =
              if data.is_a?(Hash)
                data.merge("id" => msg["id"])
              else
                {"id" => msg["id"], "details" => data}
              end
            Event::System.new(type: :error, data: error_data)
          end

        when "announce"
          Event::System.new(type: :announce, data: data["text"])

        when "session_error"
          Event::System.new(
            type: :session_error,
            tag: msg["session"],
            data: data["error"] || data
          )

        when "session_closed"
          Event::System.new(
            type: :session_closed,
            tag: msg["session"],
            data: data["reason"] || data
          )

        # -- Diagnostic events -> Event::System ---------------------------------

        when "diagnostic"
          Event::System.new(type: :diagnostic, data: data)

        # -- Fallback: extension/unknown events -> Event::Widget --------------

        else
          if msg["id"]
            id, scope = split_scoped_id(msg["id"])
            Event::Widget.new(
              type: family&.to_sym, id: id,
              value: msg["value"], window_id: window_id_fn.call(msg, family),
              scope: scope, data: msg["data"]
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
          session: msg["session"],
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
      # Returns a hash with the wire ID. The runtime resolves the tag
      # from its effect_ids mapping before delivering to the app.
      #
      # @param msg [Hash]
      # @return [Hash] with :type, :wire_id, :result
      def decode_effect_response(msg)
        result = case msg["status"]
        when "ok" then [:ok, msg["result"]]
        when "cancelled" then :cancelled
        when "error" then [:error, msg["error"]]
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
        {type: :effect_response, wire_id: msg["id"], result: result}
      end

      # Decode a query response (find, tree).
      #
      # @param msg [Hash]
      # @return [Hash] with :type, :id, :target, :data
      def decode_query_response(msg)
        {
          type: :query_response,
          session: msg["session"],
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
          session: msg["session"],
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
        events = (msg["events"] || []).filter_map { |e| decode_event(e, require_window_id: false) }
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
        events = (msg["events"] || []).filter_map { |e| decode_event(e, require_window_id: false) }
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
          session: msg["session"],
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
          session: msg["session"],
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
          session: msg["session"],
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
        id = parts.pop.to_s
        [id, parts.reverse]
      end

      # Split scoped ID and append window_id to the scope chain
      # (outermost ancestor, at the end of the reversed list).
      #
      # @param full_id [String, nil]
      # @param window_id [String, nil]
      # @return [Array(String, Array<String>)]
      def split_scoped_id_with_window(full_id, window_id)
        id, scope = split_scoped_id(full_id)
        scope += [window_id] if window_id && !window_id.empty?
        [id, scope]
      end

      def require_window_id!(msg, family)
        window_id = msg["window_id"]
        return window_id if window_id.is_a?(String) && !window_id.empty?

        raise ArgumentError, "event family #{family.inspect} is missing required window_id"
      end

      # Lenient window_id extraction for events embedded in interact
      # responses where the mock renderer may omit window_id.
      #
      # @param msg [Hash]
      # @param _family [String]
      # @return [String, nil]
      def optional_window_id(msg, _family)
        window_id = msg["window_id"]
        (window_id.is_a?(String) && !window_id.empty?) ? window_id : nil
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

      # Parse a canvas button string to a symbol.
      # @param button [String, nil]
      # @return [Symbol]
      def parse_canvas_button(button)
        case button
        when "left", nil then :left
        when "right" then :right
        when "middle" then :middle
        else button.to_sym
        end
      end

      # Convert string-keyed wire data to symbol-keyed hash.
      # @param data [Hash, nil]
      # @return [Hash, nil]
      def atomize_data(data)
        return nil unless data.is_a?(Hash)
        data.transform_keys(&:to_sym)
      end

      # Parse canvas element key event data with proper key and modifier types.
      # @param data [Hash] raw wire data
      # @param type [:press, :release]
      # @return [Hash] parsed data with symbol keys
      def parse_canvas_key_data(data, type)
        {
          type: type,
          element_id: data["element_id"],
          key: Keys.parse_key(data["key"]),
          modifiers: parse_modifiers(data["modifiers"])
        }
      end

      # Parse an IME cursor position from the wire format.
      # @param cursor [Hash, Array, nil] cursor data from the renderer
      # @return [Array(Integer, Integer), nil] [start, end] or nil
      def parse_ime_cursor(cursor)
        case cursor
        when Hash then [cursor["start"], cursor["end"]]
        when Array then [cursor[0], cursor[1]] if cursor.length == 2
        end
      end
    end
  end
end
