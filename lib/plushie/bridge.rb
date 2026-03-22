# frozen_string_literal: true

module Plushie
  # Bridge to the plushie renderer process.
  #
  # Manages the subprocess, reads events from stdout, writes commands
  # to stdin. Runs in a dedicated thread and pushes decoded events
  # onto the runtime's event queue.
  class Bridge
    attr_reader :format

    def initialize(event_queue:, format: :msgpack, renderer_path: nil, transport: :spawn, log_level: :error)
      @event_queue = event_queue
      @format = format
      @renderer_path = renderer_path
      @transport = transport
      @log_level = log_level
      @write_mutex = Mutex.new
      @process = nil
      @stdin = nil
      @stdout = nil
      @reader_thread = nil
    end

    def start
      case @transport
      when :spawn
        spawn_renderer
      when :stdio
        @stdin = $stdout
        @stdout = $stdin
      end

      start_reader_thread
    end

    def stop
      @reader_thread&.kill
      @stdin&.close rescue nil
      @process&.close rescue nil
    end

    def send_message(data)
      @write_mutex.synchronize do
        case @format
        when :msgpack
          @stdin.write([data.bytesize].pack("N"))
          @stdin.write(data)
        when :json
          @stdin.write(data)
        end
        @stdin.flush
      end
    rescue IOError, Errno::EPIPE => e
      @event_queue.push([:renderer_exited, e])
    end

    private

    def spawn_renderer
      path = @renderer_path || Binary.path!
      args = [path, "--format", @format.to_s, "--log-level", @log_level.to_s]
      @stdin, @stdout, @process = Open3.popen2(*args)
      @stdin.binmode
      @stdout.binmode
    end

    def start_reader_thread
      @reader_thread = Thread.new do
        read_loop
      rescue => e
        @event_queue.push([:renderer_exited, e])
      end
      @reader_thread.name = "plushie-bridge"
    end

    def read_loop
      case @format
      when :msgpack
        read_msgpack_loop
      when :json
        read_json_loop
      end
    end

    def read_msgpack_loop
      while (header = @stdout.read(4))
        length = header.unpack1("N")
        data = @stdout.read(length)
        break if data.nil? || data.bytesize != length

        event = Protocol::Decode.decode_message(data, :msgpack)
        @event_queue.push([:renderer_event, event]) if event
      end
      @event_queue.push([:renderer_exited, :eof])
    end

    def read_json_loop
      @stdout.each_line do |line|
        line = line.chomp
        next if line.empty?

        event = Protocol::Decode.decode_message(line, :json)
        @event_queue.push([:renderer_event, event]) if event
      end
      @event_queue.push([:renderer_exited, :eof])
    end
  end
end

require "open3"
