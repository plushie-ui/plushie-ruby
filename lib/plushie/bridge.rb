# frozen_string_literal: true

require "logger"

module Plushie
  # Renderer lifecycle manager.
  #
  # Wraps a Connection with restart logic and state preservation.
  # When the renderer crashes, the Bridge reconnects with exponential
  # backoff and re-sends settings + the last snapshot.
  #
  # The Bridge pushes decoded events to the Runtime's event queue.
  # On disconnect, it pushes [:renderer_exited, reason].
  class Bridge
    # Exponential backoff parameters
    BACKOFF_BASE_MS = 100
    BACKOFF_MAX_MS = 1600
    MAX_RETRIES = 5

    # @return [:msgpack, :json] wire format
    attr_reader :format

    # @return [Hash, nil] hello response from the current connection
    attr_reader :hello

    # @param event_queue [Thread::Queue] queue for decoded events
    # @param format [:msgpack, :json] wire format
    # @param binary [String, nil] renderer binary path
    # @param transport [:spawn, :stdio, Array(:iostream, adapter)] transport mode
    # @param log_level [Symbol] renderer log level
    # @param token [String, nil] authentication token for the renderer
    def initialize(event_queue:, format: :msgpack, binary: nil,
      transport: :spawn, log_level: :error, token: nil)
      @event_queue = event_queue
      @format = format
      @binary = binary
      @transport = transport
      @log_level = log_level
      @token = token
      @connection = nil
      @retry_count = 0
      @settings = {}
      @last_snapshot = nil
      @logger = Logger.new($stderr, level: :warn, progname: "plushie")
    end

    # Start the connection and perform handshake.
    #
    # @param settings [Hash] application settings to send
    def start(settings: {})
      @settings = settings
      connect!
    end

    # Send pre-encoded wire bytes to the renderer. Thread-safe.
    #
    # @param data [String] encoded message bytes
    def send_encoded(data)
      @connection&.send_encoded(data)
    end

    # Store the last snapshot for re-sending after restart.
    #
    # @param snapshot_data [String] encoded snapshot message
    def remember_snapshot(snapshot_data)
      @last_snapshot = snapshot_data
    end

    # Stop the connection and clean up.
    def stop
      @connection&.close
      @connection = nil
    end

    private

    def connect!
      queue = Thread::Queue.new
      settings = @token ? @settings.merge(token: @token) : @settings

      @connection = case @transport
      when :spawn
        Connection.spawn(
          format: @format, binary: @binary,
          mode: nil, log_level: @log_level,
          settings: settings, queue: queue
        )
      when :stdio
        Connection.attach(
          stdin: $stdout, stdout: $stdin,
          format: @format, settings: settings, queue: queue
        )
      when Array
        kind, adapter = @transport
        raise ArgumentError, "unsupported transport tuple: #{@transport.inspect}" unless kind == :iostream
        Connection.iostream(
          adapter: adapter, format: @format,
          settings: settings, queue: queue
        )
      else
        raise ArgumentError, "unsupported transport: #{@transport.inspect}"
      end

      @hello = @connection.hello
      @retry_count = 0

      # Forward messages from connection queue to event queue
      start_forwarder(queue)
    rescue => e
      handle_connect_failure(e)
    end

    def start_forwarder(conn_queue)
      Thread.new do
        while (msg = conn_queue.pop)
          case msg
          in {type: :connection_closed} | {type: :connection_error}
            @event_queue.push([:renderer_exited, msg])
            attempt_restart
            break
          else
            @event_queue.push([:renderer_event, msg])
          end
        end
      rescue => e
        @event_queue.push([:renderer_exited, e])
      end.tap { |t| t.name = "plushie-bridge-forwarder" }
    end

    def attempt_restart
      return if @retry_count >= MAX_RETRIES

      @retry_count += 1
      delay_ms = [BACKOFF_BASE_MS * (2**(@retry_count - 1)), BACKOFF_MAX_MS].min
      @logger.warn("plushie: renderer exited, retry #{@retry_count}/#{MAX_RETRIES} in #{delay_ms}ms")

      sleep(delay_ms / 1000.0)
      @connection&.close

      connect!
      resend_state
    rescue => e
      @logger.error("plushie: restart failed: #{e.class}: #{e.message}")
      @event_queue.push([:renderer_exited, e]) if @retry_count >= MAX_RETRIES
    end

    def resend_state
      # Re-send the last snapshot so the renderer has the current tree
      if @last_snapshot
        @connection.send_encoded(@last_snapshot)
      end
    end

    def handle_connect_failure(error)
      @logger.error("plushie: connection failed: #{error.class}: #{error.message}")
      @event_queue.push([:renderer_exited, error])
    end
  end
end
