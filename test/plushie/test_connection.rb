# frozen_string_literal: true

require "test_helper"
require "json"

class TestConnection < Minitest::Test
  # -- msgpack write framing (4-byte length prefix) -------------------------

  def test_msgpack_write_framing
    rd, wr = IO.pipe
    wr.binmode
    rd.binmode

    # Build a Connection-like object manually to test send_encoded
    conn = Plushie::Connection.allocate
    conn.instance_variable_set(:@format, :msgpack)
    conn.instance_variable_set(:@write_mutex, Mutex.new)
    conn.instance_variable_set(:@stdin, wr)
    conn.instance_variable_set(:@iostream_adapter, nil)
    conn.instance_variable_set(:@closed, false)

    payload = "hello"
    conn.send_encoded(payload)

    # Read 4-byte length header
    header = rd.read(4)
    length = header.unpack1("N")
    assert_equal 5, length

    # Read payload
    data = rd.read(length)
    assert_equal "hello", data

    wr.close
    rd.close
  end

  # -- JSON write framing (newline-terminated) ------------------------------

  def test_json_write_framing
    rd, wr = IO.pipe
    wr.binmode
    rd.binmode

    conn = Plushie::Connection.allocate
    conn.instance_variable_set(:@format, :json)
    conn.instance_variable_set(:@write_mutex, Mutex.new)
    conn.instance_variable_set(:@stdin, wr)
    conn.instance_variable_set(:@iostream_adapter, nil)
    conn.instance_variable_set(:@closed, false)

    # Protocol::Encode adds the trailing newline, so include it here
    payload = "{\"type\":\"snapshot\"}\n"
    conn.send_encoded(payload)
    wr.close

    data = rd.read
    assert_equal payload, data

    rd.close
  end

  # -- Thread-safe writes don't interleave ---------------------------------

  def test_thread_safe_writes_do_not_interleave
    rd, wr = IO.pipe
    wr.binmode
    rd.binmode

    conn = Plushie::Connection.allocate
    conn.instance_variable_set(:@format, :msgpack)
    conn.instance_variable_set(:@write_mutex, Mutex.new)
    conn.instance_variable_set(:@stdin, wr)
    conn.instance_variable_set(:@iostream_adapter, nil)
    conn.instance_variable_set(:@closed, false)

    total_per_thread = 20
    thread_count = 4
    total = total_per_thread * thread_count

    # Start a reader thread that drains the pipe concurrently to avoid
    # blocking writers when the pipe buffer fills.
    messages = []
    reader = Thread.new do
      loop do
        header = rd.read(4)
        break unless header && header.bytesize == 4
        length = header.unpack1("N")
        data = rd.read(length)
        break unless data && data.bytesize == length
        messages << data
      end
    end

    threads = thread_count.times.map do |t|
      Thread.new do
        total_per_thread.times do |i|
          conn.send_encoded("t#{t}i#{i}")
        end
      end
    end
    threads.each(&:join)
    wr.close
    reader.join
    rd.close

    assert_equal total, messages.length

    # Verify each message is a complete, non-interleaved string
    messages.each do |msg|
      assert_match(/\At\d+i\d+\z/, msg, "Interleaved message detected: #{msg.inspect}")
    end
  end
end
