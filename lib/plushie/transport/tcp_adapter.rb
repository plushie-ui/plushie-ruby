# frozen_string_literal: true

module Plushie
  module Transport
    # Example iostream adapter for TCP sockets.
    #
    # Reads from a TCP socket in a background thread, decodes
    # length-prefixed frames, and forwards complete messages to the
    # Connection. Outbound data is framed and written to the socket.
    #
    # Usage:
    #   socket = TCPSocket.new("localhost", 4000)
    #   adapter = Transport::TCPAdapter.new(socket)
    #   conn = Connection.iostream(adapter: adapter, format: :msgpack)
    #
    class TCPAdapter
      # @param socket [TCPSocket, IO] a connected TCP socket
      def initialize(socket)
        @socket = socket
        @connection = nil
        @reader = nil
      end

      # Called by the Connection during iostream setup.
      # Stores the connection reference and starts the reader thread.
      #
      # @param connection [Connection] the connection to forward data to
      def on_bridge(connection)
        @connection = connection
        @reader = Thread.new { read_loop }
        @reader.name = "plushie-tcp-reader"
      end

      # Called by the Connection to write data to the transport.
      # Wraps data in a length-prefixed frame before writing.
      #
      # @param data [String] raw protocol message bytes
      def send_data(data)
        framed = Framing.encode_packet(data)
        @socket.write(framed)
        @socket.flush
      end

      # Stop the adapter and close the socket.
      def stop
        @reader&.kill
        begin
          @socket&.close
        rescue IOError
          nil
        end
      end

      private

      def read_loop
        buffer = "".b
        while (chunk = @socket.readpartial(65536))
          buffer << chunk
          messages, buffer = Framing.decode_packets(buffer)
          messages.each { |msg| @connection.receive_data(msg) }
        end
      rescue IOError
        @connection&.transport_closed(:tcp_closed)
      end
    end
  end
end
