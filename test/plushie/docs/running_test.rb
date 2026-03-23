# frozen_string_literal: true

require "test_helper"

class DocsRunningTest < Minitest::Test
  # Minimal app for verifying Plushie.run and Plushie.start signatures.
  class DummyApp
    include Plushie::App

    Model = Plushie::Model.define(:count)

    def init(_opts) = Model.new(count: 0)
    def update(model, _event) = model

    def view(model)
      window("main", title: "Dummy") do
        text("count", model.count.to_s)
      end
    end
  end

  # -- Plushie.run accepts app class and transport options --

  def test_run_method_exists
    assert_respond_to Plushie, :run
  end

  def test_start_method_exists
    assert_respond_to Plushie, :start
  end

  # -- Runtime accepts daemon option (from running.md) --

  def test_runtime_accepts_daemon_option
    runtime = Plushie::Runtime.new(app: DummyApp.new, daemon: true)
    refute_nil runtime
  end

  # -- Runtime accepts stdio transport (from running.md) --

  def test_runtime_accepts_stdio_transport
    runtime = Plushie::Runtime.new(app: DummyApp.new, transport: :stdio)
    refute_nil runtime
  end

  # -- Runtime accepts iostream transport (from running.md) --

  def test_runtime_accepts_iostream_transport
    # The iostream transport takes a tuple of [:iostream, adapter_instance].
    # We just verify the runtime constructor doesn't reject it.
    adapter = Object.new
    runtime = Plushie::Runtime.new(app: DummyApp.new, transport: [:iostream, adapter])
    refute_nil runtime
  end

  # -- TCP adapter pattern compiles (from running.md) --

  class TCPAdapter
    def initialize(socket)
      @socket = socket
      @bridge = nil
      @buffer = "".b
    end

    def handle_message(msg)
      case msg
      in [:iostream_bridge, bridge]
        @bridge = bridge

      in [:iostream_send, data]
        @socket.write(Plushie::Transport::Framing.encode_packet(data))

      in [:tcp_data, data]
        messages, @buffer = Plushie::Transport::Framing.decode_packets(@buffer + data)
        messages.each { |m| @bridge.push([:iostream_data, m]) }

      in [:tcp_closed]
        @bridge&.push([:iostream_closed, :tcp_closed])
      end
    end
  end

  def test_tcp_adapter_class_defined
    assert_instance_of Class, TCPAdapter
  end

  def test_tcp_adapter_handles_bridge_init
    socket = StringIO.new("".b)
    adapter = TCPAdapter.new(socket)
    bridge = Queue.new
    adapter.handle_message([:iostream_bridge, bridge])
    # No error means the pattern match succeeded.
    pass
  end

  def test_tcp_adapter_encodes_and_sends
    socket = StringIO.new("".b)
    adapter = TCPAdapter.new(socket)
    bridge = Queue.new
    adapter.handle_message([:iostream_bridge, bridge])
    adapter.handle_message([:iostream_send, "hello"])
    socket.rewind
    data = socket.read
    # 4-byte length prefix + "hello"
    assert_equal 4 + 5, data.bytesize
  end

  # -- Framing module from running.md --

  def test_framing_encode_decode_packet
    payload = "test message".b
    encoded = Plushie::Transport::Framing.encode_packet(payload)
    messages, remaining = Plushie::Transport::Framing.decode_packets(encoded)
    assert_equal [payload], messages
    assert_equal "".b, remaining
  end

  def test_framing_encode_decode_line
    payload = '{"type":"snapshot"}'
    encoded = Plushie::Transport::Framing.encode_line(payload)
    assert encoded.end_with?("\n")
    lines, remaining = Plushie::Transport::Framing.decode_lines(encoded)
    assert_equal [payload], lines
    assert_equal "", remaining
  end

  # -- Settings with default_event_rate (from running.md) --

  class RateLimitApp
    include Plushie::App

    Model = Plushie::Model.define(:x)

    def init(_opts) = Model.new(x: 0)
    def update(model, _event) = model
    def view(_model) = nil

    def settings
      {default_event_rate: 60}
    end
  end

  def test_settings_default_event_rate
    app = RateLimitApp.new
    assert_equal({default_event_rate: 60}, app.settings)
  end

  # -- Subscription with max_rate (from running.md) --

  def test_subscription_max_rate
    sub = Plushie::Subscription.on_mouse_move(:mouse, max_rate: 30)
    assert_equal :on_mouse_move, sub.type
    assert_equal :mouse, sub.tag
    assert_equal 30, sub.max_rate
  end

  def test_subscription_animation_frame_max_rate
    sub = Plushie::Subscription.on_animation_frame(:frame, max_rate: 60)
    assert_equal :on_animation_frame, sub.type
    assert_equal 60, sub.max_rate
  end

  def test_subscription_capture_only
    sub = Plushie::Subscription.on_mouse_move(:capture, max_rate: 0)
    assert_equal 0, sub.max_rate
  end
end
