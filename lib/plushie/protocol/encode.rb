# frozen_string_literal: true

module Plushie
  module Protocol
    # Outbound message encoding for the wire protocol.
    module Encode
      module_function

      def encode(map, format = :msgpack)
        case format
        when :json
          JSON.generate(stringify_keys(map)) + "\n"
        when :msgpack
          require "msgpack"
          MessagePack.pack(stringify_keys(map))
        end
      end

      def encode_settings(settings, format = :msgpack)
        encode({
          type: "settings",
          session: "",
          settings: settings.merge(protocol_version: Protocol::PROTOCOL_VERSION)
        }, format)
      end

      def encode_snapshot(tree, format = :msgpack)
        encode({type: "snapshot", session: "", tree:}, format)
      end

      def encode_patch(ops, format = :msgpack)
        encode({type: "patch", session: "", ops:}, format)
      end

      def encode_subscribe(kind, tag, format = :msgpack, max_rate: nil)
        msg = {type: "subscribe", session: "", kind: kind.to_s, tag: tag.to_s}
        msg[:max_rate] = max_rate if max_rate
        encode(msg, format)
      end

      def encode_unsubscribe(kind, format = :msgpack)
        encode({type: "unsubscribe", session: "", kind: kind.to_s}, format)
      end

      def encode_widget_op(op, payload, format = :msgpack)
        encode({type: "widget_op", session: "", op: op.to_s, payload:}, format)
      end

      def encode_effect(id, kind, payload, format = :msgpack)
        encode({type: "effect", session: "", id:, kind:, payload:}, format)
      end

      def encode_window_op(op, window_id, settings, format = :msgpack)
        encode({type: "window_op", session: "", op: op.to_s, window_id:, settings:}, format)
      end

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
    end
  end
end
