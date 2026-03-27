# frozen_string_literal: true

require "test_helper"

class TestIoStream < Minitest::Test
  F = Plushie::Transport::Framing

  # A mock iostream adapter backed by IO.pipe. Simulates an external
  # transport (TCP, SSH, etc.) without network dependencies.
  class PipeAdapter
    attr_reader :connection, :sent_frames

    def initialize(read_io, write_io)
      @read_io = read_io
      @write_io = write_io
      @connection = nil
      @reader = nil
      @sent_frames = []
    end

    def on_bridge(connection)
      @connection = connection
      @reader = Thread.new { read_loop }
      @reader.name = "test-pipe-reader"
    end

    def send_data(data)
      @sent_frames << data
      framed = F.encode_packet(data)
      @write_io.write(framed)
      @write_io.flush
    end

    def stop
      @reader&.kill
      begin
        @read_io&.close
      rescue IOError
        nil
      end
      begin
        @write_io&.close
      rescue IOError
        nil
      end
    end

    private

    def read_loop
      buffer = "".b
      while (chunk = @read_io.readpartial(65536))
        buffer << chunk
        messages, buffer = F.decode_packets(buffer)
        messages.each { |msg| @connection.receive_data(msg) }
      end
    rescue IOError
      @connection&.transport_closed(:pipe_closed)
    end
  end

  def setup
    # Two pairs of pipes: one for each direction.
    # "renderer_to_host" = adapter reads from this (simulated renderer output)
    # "host_to_renderer" = adapter writes to this (we read to verify)
    @renderer_out_r, @renderer_out_w = IO.pipe
    @host_out_r, @host_out_w = IO.pipe
    @renderer_out_r.binmode
    @renderer_out_w.binmode
    @host_out_r.binmode
    @host_out_w.binmode
  end

  def teardown
    [@renderer_out_r, @renderer_out_w, @host_out_r, @host_out_w].each do |io|
      io&.close
    rescue IOError
      nil
    end
  end

  def test_iostream_adapter_receives_on_bridge
    adapter = PipeAdapter.new(@renderer_out_r, @host_out_w)
    # Simulate what Connection.iostream does: call on_bridge
    mock_conn = Object.new
    adapter.on_bridge(mock_conn)
    assert_equal mock_conn, adapter.connection
    adapter.stop
  end

  def test_iostream_adapter_send_data_writes_framed
    adapter = PipeAdapter.new(@renderer_out_r, @host_out_w)
    adapter.on_bridge(Object.new)

    adapter.send_data("hello")
    assert_equal ["hello"], adapter.sent_frames

    # Read the framed data from the pipe
    header = @host_out_r.read(4)
    length = header.unpack1("N")
    payload = @host_out_r.read(length)
    assert_equal "hello", payload

    adapter.stop
  end

  def test_iostream_adapter_forwards_received_data
    received = []
    mock_conn = Object.new
    mock_conn.define_singleton_method(:receive_data) { |data| received << data }

    adapter = PipeAdapter.new(@renderer_out_r, @host_out_w)
    adapter.on_bridge(mock_conn)

    # Write a framed message to the "renderer output" pipe
    @renderer_out_w.write(F.encode_packet("test_msg"))
    @renderer_out_w.flush

    # Give the reader thread a moment to process
    sleep 0.05
    assert_equal ["test_msg"], received

    adapter.stop
  end

  def test_iostream_adapter_reports_transport_closed
    closed_reason = nil
    mock_conn = Object.new
    mock_conn.define_singleton_method(:receive_data) { |_| }
    mock_conn.define_singleton_method(:transport_closed) { |reason| closed_reason = reason }

    adapter = PipeAdapter.new(@renderer_out_r, @host_out_w)
    adapter.on_bridge(mock_conn)

    # Close the write end so the reader gets EOF
    @renderer_out_w.close
    sleep 0.05

    assert_equal :pipe_closed, closed_reason
    adapter.stop
  end

  def test_iostream_connection_full_handshake
    queue = Thread::Queue.new

    # Create adapter that reads from renderer_out and writes to host_out
    adapter = PipeAdapter.new(@renderer_out_r, @host_out_w)

    # Start iostream connection in a thread (it blocks waiting for hello)
    conn_thread = Thread.new do
      Plushie::Connection.iostream(
        adapter: adapter,
        format: :json,
        settings: {title: "Test"},
        queue: queue
      )
    end

    # Read the settings message the connection sends via adapter
    sleep 0.05
    header = @host_out_r.read(4)
    length = header.unpack1("N")
    settings_data = @host_out_r.read(length)
    settings_msg = JSON.parse(settings_data)
    assert_equal "settings", settings_msg["type"]
    assert_equal "Test", settings_msg["settings"]["title"]

    # Send a hello response back through the "renderer" pipe
    hello = {
      "type" => "hello",
      "protocol" => Plushie::Protocol::PROTOCOL_VERSION,
      "name" => "plushie",
      "version" => "0.1.0",
      "mode" => "mock",
      "backend" => "none",
      "transport" => "stdio",
      "extensions" => []
    }
    hello_json = JSON.generate(hello)
    @renderer_out_w.write(F.encode_packet(hello_json))
    @renderer_out_w.flush

    conn = conn_thread.value
    assert_equal :hello, conn.hello[:type]
    assert_equal Plushie::Protocol::PROTOCOL_VERSION, conn.hello[:protocol]

    # Send a widget event through the "renderer" pipe
    event = {
      "type" => "event",
      "family" => "click",
      "id" => "btn",
      "window_id" => "main"
    }
    @renderer_out_w.write(F.encode_packet(JSON.generate(event)))
    @renderer_out_w.flush

    # The event should arrive on the queue
    msg = queue.pop
    assert msg

    conn.close
    adapter.stop
  end

  def test_iostream_connection_transport_closed
    queue = Thread::Queue.new
    adapter = PipeAdapter.new(@renderer_out_r, @host_out_w)

    conn_thread = Thread.new do
      Plushie::Connection.iostream(
        adapter: adapter, format: :json, settings: {}, queue: queue
      )
    end

    # Drain the settings message
    sleep 0.05
    header = @host_out_r.read(4)
    length = header.unpack1("N")
    @host_out_r.read(length)

    # Send hello
    hello = {
      "type" => "hello",
      "protocol" => Plushie::Protocol::PROTOCOL_VERSION,
      "name" => "plushie", "version" => "0.1.0",
      "mode" => "mock", "backend" => "none",
      "transport" => "stdio", "extensions" => []
    }
    @renderer_out_w.write(F.encode_packet(JSON.generate(hello)))
    @renderer_out_w.flush

    conn = conn_thread.value

    # Close the renderer pipe to trigger transport_closed
    @renderer_out_w.close
    sleep 0.05

    msg = queue.pop
    assert_equal :connection_closed, msg[:type]
    assert_equal :pipe_closed, msg[:reason]

    conn.close
    adapter.stop
  end

  def test_iostream_connection_receive_data_before_hello_ignored
    queue = Thread::Queue.new
    adapter = PipeAdapter.new(@renderer_out_r, @host_out_w)

    conn_thread = Thread.new do
      Plushie::Connection.iostream(
        adapter: adapter, format: :json, settings: {}, queue: queue
      )
    end

    # Drain settings
    sleep 0.05
    header = @host_out_r.read(4)
    length = header.unpack1("N")
    @host_out_r.read(length)

    # Send a non-hello message first -- it should be dispatched,
    # but hello should still be nil until we send hello
    # Actually, the connection blocks until hello arrives via
    # handshake_queue, so this event will be dispatched normally
    # once the hello unblocks.

    # Send hello to unblock
    hello = {
      "type" => "hello",
      "protocol" => Plushie::Protocol::PROTOCOL_VERSION,
      "name" => "plushie", "version" => "0.1.0",
      "mode" => "mock", "backend" => "none",
      "transport" => "stdio", "extensions" => []
    }
    @renderer_out_w.write(F.encode_packet(JSON.generate(hello)))
    @renderer_out_w.flush

    conn = conn_thread.value
    assert_equal :hello, conn.hello[:type]

    conn.close
    adapter.stop
  end

  def test_iostream_connection_settings_include_token_when_provided
    queue = Thread::Queue.new
    adapter = PipeAdapter.new(@renderer_out_r, @host_out_w)

    conn_thread = Thread.new do
      Plushie::Connection.iostream(
        adapter: adapter, format: :json,
        settings: {title: "Test", token: "secret-123"},
        queue: queue
      )
    end

    # Read settings message
    sleep 0.05
    header = @host_out_r.read(4)
    length = header.unpack1("N")
    settings_data = @host_out_r.read(length)
    settings_msg = JSON.parse(settings_data)
    assert_equal "secret-123", settings_msg["settings"]["token"]

    # Send hello to unblock
    hello = {
      "type" => "hello",
      "protocol" => Plushie::Protocol::PROTOCOL_VERSION,
      "name" => "plushie", "version" => "0.1.0",
      "mode" => "mock", "backend" => "none",
      "transport" => "stdio", "extensions" => []
    }
    @renderer_out_w.write(F.encode_packet(JSON.generate(hello)))
    @renderer_out_w.flush

    conn = conn_thread.value
    conn.close
    adapter.stop
  end
end
