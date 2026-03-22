# frozen_string_literal: true

require "test_helper"

class TestFraming < Minitest::Test
  F = Plushie::Transport::Framing

  # -- MessagePack framing (4-byte length prefix) ---------------------------

  def test_encode_packet
    data = "hello"
    frame = F.encode_packet(data)
    # 4-byte header + 5-byte payload
    assert_equal 9, frame.bytesize
    assert_equal [5].pack("N"), frame[0, 4]
    assert_equal "hello", frame[4, 5]
  end

  def test_decode_single_packet
    frame = F.encode_packet("hello")
    messages, remaining = F.decode_packets(frame)
    assert_equal ["hello"], messages
    assert_equal "", remaining
  end

  def test_decode_multiple_packets
    buffer = F.encode_packet("one") + F.encode_packet("two")
    messages, remaining = F.decode_packets(buffer)
    assert_equal ["one", "two"], messages
    assert_equal "", remaining
  end

  def test_decode_partial_header
    messages, remaining = F.decode_packets("\x00\x00")
    assert_empty messages
    assert_equal 2, remaining.bytesize
  end

  def test_decode_partial_payload
    # Header says 10 bytes but only 5 available
    buffer = [10].pack("N") + "hello"
    messages, remaining = F.decode_packets(buffer)
    assert_empty messages
    assert_equal 9, remaining.bytesize
  end

  def test_decode_empty_buffer
    messages, remaining = F.decode_packets("")
    assert_empty messages
    assert_equal "", remaining
  end

  def test_round_trip_msgpack
    original = "binary\x00data\xff"
    frame = F.encode_packet(original)
    messages, remaining = F.decode_packets(frame)
    assert_equal [original.b], messages
    assert_equal "", remaining
  end

  # -- JSON framing (newline-delimited) ------------------------------------

  def test_encode_line
    assert_equal "hello\n", F.encode_line("hello")
  end

  def test_decode_single_line
    lines, remaining = F.decode_lines("hello\n")
    assert_equal ["hello"], lines
    assert_equal "", remaining
  end

  def test_decode_multiple_lines
    lines, remaining = F.decode_lines("one\ntwo\nthree\n")
    assert_equal ["one", "two", "three"], lines
    assert_equal "", remaining
  end

  def test_decode_partial_line
    lines, remaining = F.decode_lines("hello\npartial")
    assert_equal ["hello"], lines
    assert_equal "partial", remaining
  end

  def test_decode_no_newline
    lines, remaining = F.decode_lines("incomplete")
    assert_empty lines
    assert_equal "incomplete", remaining
  end
end
