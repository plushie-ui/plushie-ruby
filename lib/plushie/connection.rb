# frozen_string_literal: true

require "open3"

module Plushie
  # Low-level protocol client for the plushie renderer.
  #
  # Manages a bidirectional pipe to the renderer binary, handles wire
  # framing, and provides thread-safe message sending. Decoded messages
  # are pushed to a Thread::Queue or dispatched via a callback proc.
  #
  # This layer is usable standalone for scripting and REPL exploration
  # without the full Elm architecture:
  #
  #   conn = Plushie::Connection.spawn(format: :json)
  #   # hello is available after spawn
  #   puts conn.hello[:version]
  #   conn.send_encoded(Protocol::Encode.encode_snapshot(tree, :json))
  #   conn.close
  #
  class Connection
    # @return [:msgpack, :json] wire format
    attr_reader :format

    # @return [Hash, nil] hello handshake response from renderer
    attr_reader :hello

    # Spawn a renderer process and perform the hello handshake.
    #
    # @param format [:msgpack, :json] wire format
    # @param binary [String, nil] path to renderer binary (nil = auto-resolve)
    # @param mode [:windowed, :headless, :mock, nil] execution mode
    # @param max_sessions [Integer, nil] max concurrent sessions
    # @param log_level [Symbol, nil] renderer log level
    # @param settings [Hash] initial settings to send
    # @param queue [Thread::Queue, nil] queue to push decoded messages to
    # @param on_message [Proc, nil] callback for decoded messages (alternative to queue)
    # @return [Connection]
    def self.spawn(format: :msgpack, binary: nil, mode: nil, max_sessions: nil,
      log_level: nil, settings: {}, queue: nil, on_message: nil)
      conn = new(format: format, queue: queue, on_message: on_message)
      conn.send(:spawn_process, binary, mode, max_sessions, log_level)
      conn.send(:perform_handshake, settings)
      conn.send(:start_reader)
      conn
    end

    # Attach to existing IO streams (for :stdio transport).
    #
    # @param stdin [IO] writable stream to renderer
    # @param stdout [IO] readable stream from renderer
    # @param format [:msgpack, :json] wire format
    # @param settings [Hash] initial settings to send
    # @param queue [Thread::Queue, nil]
    # @param on_message [Proc, nil]
    # @return [Connection]
    def self.attach(stdin:, stdout:, format: :msgpack, settings: {},
      queue: nil, on_message: nil)
      conn = new(format: format, queue: queue, on_message: on_message)
      conn.instance_variable_set(:@stdin, stdin)
      conn.instance_variable_set(:@stdout, stdout)
      stdin.binmode
      stdout.binmode
      conn.send(:perform_handshake, settings)
      conn.send(:start_reader)
      conn
    end

    # Create a connection backed by an iostream adapter.
    #
    # The adapter mediates between the Connection and an external I/O
    # source (SSH channel, TCP socket, WebSocket, etc.). Instead of
    # reading/writing pipes, the connection exchanges data with the
    # adapter via method calls.
    #
    # The adapter must respond to:
    # - +on_bridge(connection)+ -- called during init, adapter stores connection ref
    # - +send_data(data)+ -- called by Connection to write encoded bytes
    #
    # The adapter calls back:
    # - +connection.receive_data(data)+ -- when data arrives from the transport
    # - +connection.transport_closed(reason)+ -- when the transport closes
    #
    # @param adapter [#on_bridge, #send_data] iostream adapter object
    # @param format [:msgpack, :json] wire format
    # @param settings [Hash] initial settings to send
    # @param queue [Thread::Queue, nil]
    # @param on_message [Proc, nil]
    # @return [Connection]
    def self.iostream(adapter:, format: :msgpack, settings: {},
      queue: nil, on_message: nil)
      conn = new(format: format, queue: queue, on_message: on_message)
      conn.send(:setup_iostream, adapter, settings)
      conn
    end

    # Send pre-encoded wire bytes to the renderer. Thread-safe.
    #
    # @param data [String] encoded message bytes
    def send_encoded(data)
      @write_mutex.synchronize do
        if @iostream_adapter
          @iostream_adapter.send_data(data)
        else
          case @format
          when :msgpack
            @stdin.write([data.bytesize].pack("N"))
            @stdin.write(data)
          when :json
            @stdin.write(data)
          end
          @stdin.flush
        end
      end
    rescue IOError, Errno::EPIPE => e
      @closed = true
      dispatch_message({type: :connection_error, error: e})
    end

    # Called by the iostream adapter when data arrives from the transport.
    # The adapter is responsible for framing -- each call should deliver
    # one complete protocol message.
    #
    # @param data [String] a complete protocol message (decoded from framing)
    def receive_data(data)
      return if @closed

      msg = Protocol::Decode.decode(data, @format)
      decoded = Protocol::Decode.dispatch_message(msg)

      if !@hello && decoded.is_a?(Hash) && decoded[:type] == :hello
        @hello = decoded
        @handshake_queue&.push(decoded)
      elsif decoded
        dispatch_message(decoded)
      end
    end

    # Called by the iostream adapter when the transport closes.
    #
    # @param reason [Symbol, String] reason for closure
    def transport_closed(reason)
      return if @closed
      @closed = true
      dispatch_message({type: :connection_closed, reason: reason})
    end

    # Encode a hash and send it. Injects session field if missing.
    #
    # @param msg [Hash] message to encode and send
    def send_message(msg)
      send_encoded(Protocol::Encode.encode(msg, @format))
    end

    # Send a message with a specific session ID injected.
    #
    # @param msg [Hash] message hash
    # @param session_id [String] session identifier
    def send_message_for_session(msg, session_id)
      send_message(msg.merge(session: session_id))
    end

    # Close the connection and clean up resources.
    def close
      return if @closed
      @closed = true
      @reader_thread&.kill
      if @iostream_adapter
        @iostream_adapter.stop if @iostream_adapter.respond_to?(:stop)
      else
        @stdin&.close rescue nil
        @stdout&.close rescue nil
        @process_thread&.value rescue nil
      end
    end

    # @return [Boolean] true if the connection is closed
    def closed?
      @closed
    end

    private

    def initialize(format:, queue: nil, on_message: nil)
      @format = format
      @queue = queue
      @on_message = on_message
      @write_mutex = Mutex.new
      @stdin = nil
      @stdout = nil
      @process_thread = nil
      @reader_thread = nil
      @hello = nil
      @closed = false
      @iostream_adapter = nil
      @handshake_queue = nil
    end

    def setup_iostream(adapter, settings)
      @iostream_adapter = adapter
      @handshake_queue = Thread::Queue.new

      # Notify the adapter so it can store our reference and start I/O.
      adapter.on_bridge(self)

      # Send settings as the first message (adapter handles framing).
      send_encoded(Protocol::Encode.encode_settings(settings, @format))

      # Wait for the hello response to arrive via receive_data.
      @hello = @handshake_queue.pop
      @handshake_queue = nil

      if @hello.is_a?(Hash) && @hello[:type] == :hello
        if @hello[:protocol] != Protocol::PROTOCOL_VERSION
          raise Error, "protocol version mismatch: expected #{Protocol::PROTOCOL_VERSION}, got #{@hello[:protocol]}"
        end
      end
    end

    def spawn_process(binary, mode, max_sessions, log_level)
      path = binary || Binary.path!
      args = [path]
      args.push("--mock") if mode == :mock
      args.push("--headless") if mode == :headless
      args.push("--max-sessions", max_sessions.to_s) if max_sessions
      args.push("--msgpack") if @format == :msgpack
      args.push("--json") if @format == :json

      @stdin, @stdout, @process_thread = Open3.popen2(*args)
      @stdin.binmode
      @stdout.binmode
    end

    def perform_handshake(settings)
      # Send settings as the first message
      send_encoded(Protocol::Encode.encode_settings(settings, @format))

      # Read the hello response
      data = read_one_message
      @hello = Protocol::Decode.dispatch_message(
        data.is_a?(String) ? Protocol::Decode.decode(data, @format) : data
      )

      if @hello.is_a?(Hash) && @hello[:type] == :hello
        if @hello[:protocol] != Protocol::PROTOCOL_VERSION
          raise Error, "protocol version mismatch: expected #{Protocol::PROTOCOL_VERSION}, got #{@hello[:protocol]}"
        end
      end
    end

    def start_reader
      @reader_thread = Thread.new { reader_loop }
      @reader_thread.name = "plushie-connection-reader"
    end

    def reader_loop
      case @format
      when :msgpack then read_msgpack_loop
      when :json then read_json_loop
      end
    rescue IOError, Errno::EPIPE
      # Pipe closed -- expected on shutdown
    ensure
      dispatch_message({type: :connection_closed}) unless @closed
    end

    def read_msgpack_loop
      while (header = @stdout.read(4))
        length = header.unpack1("N")
        data = @stdout.read(length)
        break if data.nil? || data.bytesize != length

        msg = Protocol::Decode.decode(data, :msgpack)
        decoded = Protocol::Decode.dispatch_message(msg)
        dispatch_message(decoded) if decoded
      end
    end

    def read_json_loop
      @stdout.each_line do |line|
        line = line.chomp
        next if line.empty?

        msg = Protocol::Decode.decode(line, :json)
        decoded = Protocol::Decode.dispatch_message(msg)
        dispatch_message(decoded) if decoded
      end
    end

    def read_one_message
      case @format
      when :msgpack
        header = @stdout.read(4)
        raise Error, "renderer closed before hello" unless header
        length = header.unpack1("N")
        data = @stdout.read(length)
        raise Error, "incomplete hello message" unless data&.bytesize == length
        data
      when :json
        line = @stdout.gets
        raise Error, "renderer closed before hello" unless line
        line.chomp
      end
    end

    def dispatch_message(msg)
      if @queue
        @queue.push(msg)
      elsif @on_message
        @on_message.call(msg)
      end
    end
  end
end
