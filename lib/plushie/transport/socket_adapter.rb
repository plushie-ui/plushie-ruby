# frozen_string_literal: true

require "socket"
require_relative "tcp_adapter"

module Plushie
  module Transport
    # Convenience adapter for renderer-parent socket launches.
    #
    # Accepts the same address shapes the renderer prints for
    # +--listen+: Unix socket paths, +:PORT+ localhost TCP shorthand,
    # and +HOST:PORT+ TCP addresses.
    class SocketAdapter < TCPAdapter
      def self.connect(address)
        new(open_socket(address))
      end

      def self.open_socket(address)
        if address.start_with?("/")
          UNIXSocket.new(address)
        elsif address.start_with?(":")
          TCPSocket.new("127.0.0.1", Integer(address[1..]))
        else
          host, separator, port = address.rpartition(":")
          raise ArgumentError, "invalid socket address: #{address.inspect}" if separator.empty?

          TCPSocket.new(host, Integer(port))
        end
      end
      private_class_method :open_socket
    end
  end
end
