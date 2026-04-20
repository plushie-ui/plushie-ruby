# frozen_string_literal: true

module Plushie
  # Wire transport adapters for non-standard connections.
  module Transport
    # Raised when a wire frame exceeds the protocol's per-message
    # size cap (64 MiB). Carries both the offending size and the
    # configured cap so callers can respond without string parsing.
    class BufferOverflowError < StandardError
      # @return [Integer] offending frame size in bytes.
      attr_reader :size
      # @return [Integer] configured cap in bytes.
      attr_reader :limit

      def initialize(size:, limit:)
        super("wire frame of #{size} bytes exceeds #{limit} byte limit")
        @size = size
        @limit = limit
      end
    end

    # Frame encoding/decoding for raw byte stream transports.
    #
    # Used for IoStream adapters (SSH, TCP, WebSocket) where the
    # transport doesn't provide built-in message framing. Not needed
    # for Erlang Ports (which handle framing via `{:packet, 4}`) or
    # the Connection class (which handles framing internally).
    #
    # Two modes:
    # - MessagePack: 4-byte big-endian length prefix
    # - JSON: newline-delimited (JSONL)
    #
    # Both modes raise {BufferOverflowError} when a frame would
    # exceed {MAX_MESSAGE_SIZE}.
    module Framing
      # Per-message size cap in bytes (64 MiB). Matches the renderer's
      # cap so both ends reject the same threshold.
      MAX_MESSAGE_SIZE = 64 * 1024 * 1024

      module_function

      # Encode a message with a 4-byte big-endian length prefix.
      #
      # @param data [String] raw message bytes
      # @return [String] length-prefixed frame
      # @raise [BufferOverflowError] when data exceeds 64 MiB.
      def encode_packet(data)
        data = data.b if data.encoding != Encoding::BINARY
        raise BufferOverflowError.new(size: data.bytesize, limit: MAX_MESSAGE_SIZE) if data.bytesize > MAX_MESSAGE_SIZE

        [data.bytesize].pack("N") + data
      end

      # Extract complete length-prefixed frames from a buffer.
      # Returns an array of complete messages and the remaining
      # (incomplete) buffer.
      #
      # @param buffer [String] accumulated bytes
      # @return [Array(Array<String>, String)] [messages, remaining_buffer]
      # @raise [BufferOverflowError] when a length prefix declares an
      #   oversized frame.
      def decode_packets(buffer)
        buffer = buffer.b if buffer.encoding != Encoding::BINARY
        messages = []

        while buffer.bytesize >= 4
          length = buffer[0, 4].unpack1("N")
          raise BufferOverflowError.new(size: length, limit: MAX_MESSAGE_SIZE) if length > MAX_MESSAGE_SIZE
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
      # @raise [BufferOverflowError] when the encoded line exceeds 64 MiB.
      def encode_line(data)
        raise BufferOverflowError.new(size: data.bytesize, limit: MAX_MESSAGE_SIZE) if data.bytesize > MAX_MESSAGE_SIZE

        "#{data}\n"
      end

      # Extract complete newline-delimited lines from a buffer.
      # Returns an array of complete lines and the remaining
      # (incomplete) buffer.
      #
      # @param buffer [String] accumulated bytes
      # @return [Array(Array<String>, String)] [lines, remaining_buffer]
      # @raise [BufferOverflowError] when a completed line or the
      #   partial tail exceeds 64 MiB.
      def decode_lines(buffer)
        lines = []
        while (idx = buffer.index("\n"))
          line = buffer[0, idx]
          raise BufferOverflowError.new(size: line.bytesize, limit: MAX_MESSAGE_SIZE) if line.bytesize > MAX_MESSAGE_SIZE

          lines << line
          buffer = buffer[(idx + 1)..]
        end
        raise BufferOverflowError.new(size: buffer.bytesize, limit: MAX_MESSAGE_SIZE) if buffer.bytesize > MAX_MESSAGE_SIZE

        [lines, buffer]
      end
    end
  end
end
