# frozen_string_literal: true

require "timeout"

module Plushie
  module Test
    # Shared renderer process for concurrent test sessions.
    #
    # Owns a single `plushie --mock --max-sessions N` process and
    # multiplexes messages from multiple test sessions over it.
    # Each session gets a unique session ID; responses are demuxed
    # by the `session` field and forwarded to the owning queue.
    #
    # @see ~/projects/toddy-elixir/lib/plushie/test/session_pool.ex
    class SessionPool
      # @return [:msgpack, :json]
      attr_reader :format

      # @param mode [:mock, :headless, :windowed] renderer mode
      # @param format [:msgpack, :json] wire format
      # @param max_sessions [Integer] max concurrent sessions
      # @param binary [String, nil] path to renderer binary
      def initialize(mode: :mock, format: :msgpack, max_sessions: 8, binary: nil)
        @mode = mode
        @format = format
        @max_sessions = max_sessions
        @binary = binary
        @connection = nil
        @sessions = {}  # session_id -> Thread::Queue
        @counter = 0
        @mutex = Mutex.new
        @started = false
      end

      # Start the renderer process.
      def start
        @connection = Connection.spawn(
          format: @format,
          binary: @binary,
          mode: @mode,
          max_sessions: @max_sessions,
          settings: {},
          on_message: method(:dispatch_message)
        )
        @started = true
      end

      # Register a new session. Returns a unique session ID.
      #
      # @return [String] session ID
      # @raise [RuntimeError] if pool is full
      def register
        @mutex.synchronize do
          if @sessions.size >= @max_sessions
            raise "Session pool full (#{@max_sessions} sessions). " \
              "Increase max_sessions or check for leaked sessions."
          end
          @counter += 1
          session_id = "test_#{@counter}"
          @sessions[session_id] = Thread::Queue.new
          session_id
        end
      end

      # Unregister a session. Sends Reset to the renderer.
      #
      # @param session_id [String]
      def unregister(session_id)
        send_message({type: "reset", id: "reset_#{session_id}"}, session_id)
        # Wait for reset_response (with timeout)
        begin
          wait_for_response(session_id, :reset_response, timeout: 5)
        rescue Timeout::Error
          # Timeout on reset is not fatal -- the session is still removed
        end
        @mutex.synchronize { @sessions.delete(session_id) }
      end

      # Send a message for a session (fire-and-forget).
      # Injects the session field automatically.
      #
      # @param msg [Hash] message to send
      # @param session_id [String]
      def send_message(msg, session_id)
        encoded = Protocol::Encode.encode(msg.merge(session: session_id), @format)
        @connection.send_encoded(encoded)
      end

      # Send a message and wait for a specific response type.
      #
      # @param msg [Hash]
      # @param session_id [String]
      # @param response_type [Symbol] expected response type
      # @param timeout [Numeric] max wait time in seconds
      # @return [Hash] the response
      def send_and_wait(msg, session_id, response_type, timeout: 10)
        send_message(msg, session_id)
        wait_for_response(session_id, response_type, timeout: timeout)
      end

      # Read the next message for a session (blocking).
      #
      # @param session_id [String]
      # @param timeout [Numeric] max wait time in seconds
      # @return [Object] the decoded message
      def read_message(session_id, timeout: 10)
        queue = @mutex.synchronize { @sessions[session_id] }
        raise "Unknown session: #{session_id}" unless queue

        msg = nil
        Timeout.timeout(timeout) { msg = queue.pop }
        msg
      end

      # Stop the pool and close the renderer.
      def stop
        @connection&.close
        @mutex.synchronize { @sessions.clear }
        @started = false
      end

      # @return [Boolean] true if the pool is started
      def started?
        @started
      end

      private

      # Dispatch a decoded message to the correct session queue.
      def dispatch_message(msg)
        session_id = extract_session(msg)
        return if session_id.nil? || session_id.empty?

        queue = @mutex.synchronize { @sessions[session_id] }
        queue&.push(msg)
      end

      # Extract session ID from a message (handles both Hash and event structs).
      def extract_session(msg)
        case msg
        when Hash
          msg[:session] || msg["session"]
        end
      end

      # Wait for a specific response type, re-queuing other messages.
      def wait_for_response(session_id, response_type, timeout: 10)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        stash = []

        loop do
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          raise Timeout::Error, "waiting for #{response_type}" if remaining <= 0

          msg = read_message(session_id, timeout: remaining)
          msg_type = extract_type(msg)

          if msg_type == response_type
            # Re-queue stashed messages
            queue = @mutex.synchronize { @sessions[session_id] }
            stash.each { |m| queue&.push(m) } if queue
            return msg
          else
            stash << msg
          end
        end
      end

      # Extract message type from various formats.
      def extract_type(msg)
        case msg
        when Hash
          (msg[:type] || msg["type"])&.to_sym
        end
      end
    end
  end
end
