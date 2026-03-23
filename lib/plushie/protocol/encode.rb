# frozen_string_literal: true

require "json"
require "base64"

module Plushie
  module Protocol
    # Outbound message encoding for the wire protocol.
    #
    # Every method produces wire-ready bytes (iodata for msgpack, JSONL
    # string for json). The session field defaults to "" and is injected
    # by the Connection or SessionPool when multiplexing.
    #
    # @see ~/projects/plushie/docs/protocol.md "Incoming messages"
    module Encode
      module_function

      # Encode an arbitrary hash as wire-format bytes.
      #
      # @param map [Hash] the message hash (symbol keys)
      # @param format [:msgpack, :json] wire format
      # @return [String] encoded bytes
      def encode(map, format = :msgpack)
        case format
        when :json
          JSON.generate(stringify_keys(map)) + "\n"
        when :msgpack
          require "msgpack"
          MessagePack.pack(stringify_keys(map))
        else
          raise ArgumentError, "unknown format: #{format.inspect}"
        end
      end

      # ---------------------------------------------------------------
      # Settings
      # ---------------------------------------------------------------

      # Encode application-level settings. Sent as the first message.
      #
      # All fields inside settings are optional. See protocol.md for
      # the full list: protocol_version, default_text_size, default_font,
      # antialiasing, vsync, fonts, scale_factor, validate_props,
      # extension_config, default_event_rate.
      #
      # @param settings [Hash] settings key-value pairs
      # @param format [:msgpack, :json]
      # @return [String]
      def encode_settings(settings, format = :msgpack)
        encode({
          type: "settings",
          session: "",
          settings: {protocol_version: Protocol::PROTOCOL_VERSION}.merge(settings)
        }, format)
      end

      # ---------------------------------------------------------------
      # Tree updates
      # ---------------------------------------------------------------

      # Replace the entire UI tree.
      #
      # @param tree [Hash] the tree node (id, type, props, children)
      # @param format [:msgpack, :json]
      # @return [String]
      def encode_snapshot(tree, format = :msgpack)
        encode({type: "snapshot", session: "", tree: tree}, format)
      end

      # Incrementally patch the existing tree.
      #
      # @param ops [Array<Hash>] patch operations
      # @param format [:msgpack, :json]
      # @return [String]
      def encode_patch(ops, format = :msgpack)
        encode({type: "patch", session: "", ops: ops}, format)
      end

      # ---------------------------------------------------------------
      # Subscriptions
      # ---------------------------------------------------------------

      # Subscribe to an event category.
      #
      # @param kind [String, Symbol] event category (e.g. "on_key_press")
      # @param tag [String, Symbol] routing tag
      # @param format [:msgpack, :json]
      # @param max_rate [Integer, nil] max events per second (nil = unlimited)
      # @return [String]
      def encode_subscribe(kind, tag, format = :msgpack, max_rate: nil)
        msg = {type: "subscribe", session: "", kind: kind.to_s, tag: tag.to_s}
        msg[:max_rate] = max_rate if max_rate
        encode(msg, format)
      end

      # Unsubscribe from an event category.
      #
      # @param kind [String, Symbol] event category
      # @param format [:msgpack, :json]
      # @return [String]
      def encode_unsubscribe(kind, format = :msgpack)
        encode({type: "unsubscribe", session: "", kind: kind.to_s}, format)
      end

      # ---------------------------------------------------------------
      # Widget operations
      # ---------------------------------------------------------------

      # Perform an operation on a widget (focus, scroll, etc.).
      #
      # Binary fields (e.g. :data for load_font) are automatically
      # base64-encoded for JSON and passed as raw binary for msgpack.
      #
      # @param op [String, Symbol] operation name
      # @param payload [Hash] operation-specific parameters
      # @param format [:msgpack, :json]
      # @return [String]
      def encode_widget_op(op, payload, format = :msgpack)
        # Encode binary fields if present (load_font sends raw TTF/OTF data)
        payload = encode_binary_field(payload, :data, format)
        encode({type: "widget_op", session: "", op: op.to_s, payload: payload}, format)
      end

      # ---------------------------------------------------------------
      # Window operations
      # ---------------------------------------------------------------

      # Manage a window (open, close, resize, etc.).
      #
      # @param op [String, Symbol] operation name
      # @param window_id [String] target window ID
      # @param settings [Hash] operation-specific parameters
      # @param format [:msgpack, :json]
      # @return [String]
      def encode_window_op(op, window_id, settings, format = :msgpack)
        encode({
          type: "window_op", session: "",
          op: op.to_s, window_id: window_id, settings: settings
        }, format)
      end

      # ---------------------------------------------------------------
      # Effects
      # ---------------------------------------------------------------

      # Request a platform effect (file dialog, clipboard, notification).
      #
      # @param id [String] unique request ID for correlation
      # @param kind [String] effect kind (e.g. "file_open", "clipboard_read")
      # @param payload [Hash] effect-specific parameters
      # @param format [:msgpack, :json]
      # @return [String]
      def encode_effect(id, kind, payload, format = :msgpack)
        encode({
          type: "effect", session: "",
          id: id, kind: kind.to_s, payload: payload
        }, format)
      end

      # ---------------------------------------------------------------
      # Image operations
      # ---------------------------------------------------------------

      # Manage in-memory image handles (create, update, delete).
      #
      # Binary fields (data, pixels) are base64-encoded for JSON and
      # passed as raw binary for MessagePack.
      #
      # @param op [String] "create_image", "update_image", or "delete_image"
      # @param payload [Hash] includes :handle, and optionally :data or :pixels/:width/:height
      # @param format [:msgpack, :json]
      # @return [String]
      def encode_image_op(op, payload, format = :msgpack)
        msg = {type: "image_op", session: "", op: op.to_s}
        msg[:handle] = payload[:handle] if payload[:handle]

        if payload[:data]
          msg[:data] = encode_binary(payload[:data], format)
        end

        if payload[:pixels]
          msg[:pixels] = encode_binary(payload[:pixels], format)
          msg[:width] = payload[:width]
          msg[:height] = payload[:height]
        end

        encode(msg, format)
      end

      # ---------------------------------------------------------------
      # Extension commands
      # ---------------------------------------------------------------

      # Send a command directly to a native widget extension.
      #
      # @param node_id [String] target extension widget ID
      # @param op [String] command name
      # @param payload [Hash] command data
      # @param format [:msgpack, :json]
      # @return [String]
      def encode_extension_command(node_id, op, payload, format = :msgpack)
        encode({
          type: "extension_command", session: "",
          node_id: node_id, op: op.to_s, payload: payload
        }, format)
      end

      # Send multiple extension commands in a single message.
      #
      # @param commands [Array<Hash>] each with :node_id, :op, :payload
      # @param format [:msgpack, :json]
      # @return [String]
      def encode_extension_commands(commands, format = :msgpack)
        encode({
          type: "extension_commands", session: "",
          commands: commands.map { |c|
            {node_id: c[:node_id], op: c[:op].to_s, payload: c[:payload] || {}}
          }
        }, format)
      end

      # ---------------------------------------------------------------
      # Queries
      # ---------------------------------------------------------------

      # Query the renderer's tree (find widget, get full tree).
      #
      # @param id [String] request ID for response correlation
      # @param target [String] "find" or "tree"
      # @param selector [Hash] selector (e.g. `{by: "id", value: "btn1"}`)
      # @param format [:msgpack, :json]
      # @return [String]
      def encode_query(id, target, selector = {}, format = :msgpack)
        encode({
          type: "query", session: "",
          id: id, target: target, selector: selector
        }, format)
      end

      # ---------------------------------------------------------------
      # Interactions (test protocol)
      # ---------------------------------------------------------------

      # Simulate a user interaction (click, type, toggle, etc.).
      #
      # @param id [String] request ID for response correlation
      # @param action [String] action name (click, type_text, toggle, etc.)
      # @param selector [Hash, nil] target widget selector
      # @param payload [Hash] action-specific parameters
      # @param format [:msgpack, :json]
      # @return [String]
      def encode_interact(id, action, selector = nil, payload = {}, format = :msgpack)
        msg = {
          type: "interact", session: "",
          id: id, action: action.to_s, payload: payload
        }
        msg[:selector] = selector if selector
        encode(msg, format)
      end

      # ---------------------------------------------------------------
      # Structural testing
      # ---------------------------------------------------------------

      # Compute a SHA-256 hash of the renderer's current tree.
      #
      # @param id [String] request ID
      # @param name [String] label for this hash capture
      # @param format [:msgpack, :json]
      # @return [String]
      def encode_tree_hash(id, name, format = :msgpack)
        encode({type: "tree_hash", session: "", id: id, name: name}, format)
      end

      # Capture rendered pixels.
      #
      # @param id [String] request ID
      # @param name [String] label for this capture
      # @param width [Integer] viewport width (default 1024)
      # @param height [Integer] viewport height (default 768)
      # @param format [:msgpack, :json]
      # @return [String]
      def encode_screenshot(id, name, width = 1024, height = 768, format = :msgpack)
        encode({
          type: "screenshot", session: "",
          id: id, name: name, width: width, height: height
        }, format)
      end

      # ---------------------------------------------------------------
      # Session management
      # ---------------------------------------------------------------

      # Reset all session state.
      #
      # @param id [String] request ID
      # @param format [:msgpack, :json]
      # @return [String]
      def encode_reset(id, format = :msgpack)
        encode({type: "reset", session: "", id: id}, format)
      end

      # ---------------------------------------------------------------
      # Animation
      # ---------------------------------------------------------------

      # Advance the animation clock by one frame.
      #
      # @param timestamp [Integer] frame timestamp in milliseconds
      # @param format [:msgpack, :json]
      # @return [String]
      def encode_advance_frame(timestamp, format = :msgpack)
        encode({type: "advance_frame", session: "", timestamp: timestamp}, format)
      end

      # ---------------------------------------------------------------
      # Helpers
      # ---------------------------------------------------------------

      # Recursively convert all symbol keys to strings.
      #
      # @param obj [Object] value to stringify
      # @return [Object] value with string keys
      def stringify_keys(obj)
        case obj
        when Hash
          obj.each_with_object({}) { |(k, v), h| h[k.to_s] = stringify_keys(v) }
        when Array
          obj.map { |v| stringify_keys(v) }
        else
          obj
        end
      end

      # Encode binary data for the wire format.
      # JSON: base64-encoded string. MessagePack: raw binary pass-through.
      #
      # @param data [String] binary data
      # @param format [:msgpack, :json]
      # @return [String]
      def encode_binary(data, format)
        case format
        when :json then Base64.strict_encode64(data)
        when :msgpack then data
        end
      end

      # Encode a binary field in a payload hash if present.
      # Returns a new hash with the field encoded for the wire format,
      # or the original hash if the field is absent or nil.
      #
      # @param payload [Hash] the payload hash
      # @param key [Symbol] the field key to encode
      # @param format [:msgpack, :json]
      # @return [Hash]
      def encode_binary_field(payload, key, format)
        return payload unless payload.is_a?(Hash) && payload.key?(key) && payload[key].is_a?(String)
        payload.merge(key => encode_binary(payload[key], format))
      end
    end
  end
end
