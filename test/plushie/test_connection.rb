# frozen_string_literal: true

require "test_helper"
require "json"
require "stringio"

class TestConnection < Minitest::Test
  class ThreadDouble
    attr_reader :killed, :joined

    def kill
      @killed = true
    end

    def join(timeout = nil)
      @joined = timeout
    end
  end

  class AdapterDouble
    attr_reader :stopped

    def stop
      @stopped = true
    end
  end

  class PrefixOnlyIO
    attr_reader :reads

    def initialize(length)
      @length = length
      @reads = []
    end

    def read(bytes)
      @reads << bytes
      raise "payload body should not be read" if @reads.length > 1

      [@length].pack("N")
    end
  end

  class GetsLimitIO
    attr_reader :args

    def initialize(line)
      @line = line
      @read = false
    end

    def gets(separator = nil, limit = nil)
      @args = [separator, limit]
      return nil if @read

      @read = true
      @line
    end
  end

  def with_message_limit(limit)
    framing = Plushie::Transport::Framing
    original = framing.const_get(:MAX_MESSAGE_SIZE)
    framing.send(:remove_const, :MAX_MESSAGE_SIZE)
    framing.const_set(:MAX_MESSAGE_SIZE, limit)
    yield
  ensure
    framing.send(:remove_const, :MAX_MESSAGE_SIZE)
    framing.const_set(:MAX_MESSAGE_SIZE, original)
  end

  def test_validate_required_extensions_rejects_missing_native_extension
    ext = Class.new do
      def self.native? = true
      def self.type_names = [:gauge]
    end

    original = Plushie.configuration.widgets
    Plushie.configuration.widgets = [ext]

    conn = Plushie::Connection.allocate
    error =
      assert_raises(Plushie::Error) do
        conn.send(:validate_required_widgets!, {type: :hello, extensions: []})
      end

    assert_match(/missing required widgets/, error.message)
  ensure
    Plushie.configuration.widgets = original
  end

  def test_validate_required_extensions_accepts_native_widget_in_hello
    ext = Class.new do
      def self.native? = true
      def self.type_names = [:gauge]
    end

    original = Plushie.configuration.widgets
    Plushie.configuration.widgets = [ext]

    conn = Plushie::Connection.allocate
    # Renderer reports the widget under native_widgets; validator
    # must recognize it and return without raising.
    conn.send(:validate_required_widgets!, {type: :hello, native_widgets: ["gauge"]})
  ensure
    Plushie.configuration.widgets = original
  end

  def test_validate_required_extensions_is_noop_without_native_widgets
    non_native = Class.new do
      def self.native? = false
      def self.type_names = [:composite]
    end

    original = Plushie.configuration.widgets
    Plushie.configuration.widgets = [non_native]

    conn = Plushie::Connection.allocate
    # Non-native widgets aren't checked against the hello reply, so
    # even an empty extensions list is fine.
    conn.send(:validate_required_widgets!, {type: :hello, extensions: []})
  ensure
    Plushie.configuration.widgets = original
  end

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

  def test_msgpack_hello_rejects_oversized_prefix_without_reading_body
    with_message_limit(16) do
      stdout = PrefixOnlyIO.new(17)
      conn = Plushie::Connection.allocate
      conn.instance_variable_set(:@format, :msgpack)
      conn.instance_variable_set(:@stdout, stdout)

      err = assert_raises(Plushie::Transport::BufferOverflowError) do
        conn.send(:read_one_message)
      end

      assert_equal 17, err.size
      assert_equal 16, err.limit
      assert_equal [4], stdout.reads
    end
  end

  def test_json_hello_rejects_oversized_line_before_parsing
    with_message_limit(8) do
      stdout = GetsLimitIO.new("x" * 10)
      conn = Plushie::Connection.allocate
      conn.instance_variable_set(:@format, :json)
      conn.instance_variable_set(:@stdout, stdout)

      err = assert_raises(Plushie::Transport::BufferOverflowError) do
        conn.send(:read_one_message)
      end

      assert_equal 10, err.size
      assert_equal 8, err.limit
      assert_equal ["\n", 10], stdout.args
    end
  end

  def test_reader_dispatches_connection_error_for_oversized_json_line
    with_message_limit(8) do
      queue = Thread::Queue.new
      conn = Plushie::Connection.allocate
      conn.instance_variable_set(:@format, :json)
      conn.instance_variable_set(:@stdout, StringIO.new("x" * 10))
      conn.instance_variable_set(:@queue, queue)

      conn.send(:reader_loop)

      error = queue.pop
      closed = queue.pop
      assert_equal :connection_error, error[:type]
      assert_kind_of Plushie::Transport::BufferOverflowError, error[:error]
      assert_equal :connection_closed, closed[:type]
    end
  end

  def test_reader_dispatches_connection_error_for_oversized_msgpack_prefix
    with_message_limit(8) do
      queue = Thread::Queue.new
      stdout = PrefixOnlyIO.new(9)
      conn = Plushie::Connection.allocate
      conn.instance_variable_set(:@format, :msgpack)
      conn.instance_variable_set(:@stdout, stdout)
      conn.instance_variable_set(:@queue, queue)

      conn.send(:reader_loop)

      error = queue.pop
      closed = queue.pop
      assert_equal :connection_error, error[:type]
      assert_kind_of Plushie::Transport::BufferOverflowError, error[:error]
      assert_equal :connection_closed, closed[:type]
      assert_equal [4], stdout.reads
    end
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

  def test_close_waits_for_reader_thread_cleanup
    conn = Plushie::Connection.allocate
    reader = ThreadDouble.new
    adapter = AdapterDouble.new
    conn.instance_variable_set(:@closed, false)
    conn.instance_variable_set(:@reader_thread, reader)
    conn.instance_variable_set(:@iostream_adapter, adapter)

    conn.close

    assert reader.killed
    assert_equal 1, reader.joined
    assert adapter.stopped
  end
end
