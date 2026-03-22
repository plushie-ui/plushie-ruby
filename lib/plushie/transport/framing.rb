# frozen_string_literal: true

module Plushie
  module Transport
    # Frame encoding/decoding for raw byte stream transports.
    #
    # Used for IoStream adapters (SSH, TCP, WebSocket) where the
    # transport doesn't provide built-in message framing. Not needed
    # for Erlang Ports (which handle framing via {:packet, 4}) or
    # the Connection class (which handles framing internally).
    #
    # Two modes:
    # - MessagePack: 4-byte big-endian length prefix
    # - JSON: newline-delimited (JSONL)
    module Framing
      module_function

      # Encode a message with a 4-byte big-endian length prefix.
      #
      # @param data [String] raw message bytes
      # @return [String] length-prefixed frame
      def encode_packet(data)
        data = data.b if data.encoding != Encoding::BINARY
        [data.bytesize].pack("N") + data
      end

      # Extract complete length-prefixed frames from a buffer.
      # Returns an array of complete messages and the remaining
      # (incomplete) buffer.
      #
      # @param buffer [String] accumulated bytes
      # @return [Array(Array<String>, String)] [messages, remaining_buffer]
      def decode_packets(buffer)
        buffer = buffer.b if buffer.encoding != Encoding::BINARY
        messages = []

        while buffer.bytesize >= 4
          length = buffer[0, 4].unpack1("N")
          break if buffer.bytesize < 4 + length

          messages << buffer[4, length]
          buffer = buffer[(4 + length)..]
        end

        [messages, buffer]
      end

      # Encode a message as a newline-terminated line (JSONL).
      #
      # @param data [String] message content (should not contain newlines)
      # @return [String] newline-terminated line
      def encode_line(data)
        "#{data}\n"
      end

      # Extract complete newline-delimited lines from a buffer.
      # Returns an array of complete lines and the remaining
      # (incomplete) buffer.
      #
      # @param buffer [String] accumulated bytes
      # @return [Array(Array<String>, String)] [lines, remaining_buffer]
      def decode_lines(buffer)
        lines = []
        while (idx = buffer.index("\n"))
          lines << buffer[0, idx]
          buffer = buffer[(idx + 1)..]
        end
        [lines, buffer]
      end
    end
  end
end
