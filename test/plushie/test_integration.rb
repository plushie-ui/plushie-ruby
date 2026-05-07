# frozen_string_literal: true

# Integration tests that require the plushie renderer binary.
#
# These tests exercise the full stack: spawn renderer, send settings,
# interact via the wire protocol, query the tree, and verify results.
#
# Skipped automatically if the binary is not available.
# Run explicitly with: PLUSHIE_BINARY_PATH=/path/to/plushie bundle exec rake test
#
# To run only integration tests:
#   bundle exec ruby -Ilib:test test/plushie/test_integration.rb

require "test_helper"
require_relative "../../examples/counter"

class TestIntegration < Minitest::Test
  def self.binary_available?
    Plushie::Binary.path
  rescue
    nil
  end

  if binary_available?
    require "plushie/test"

    def test_counter_click_via_mock_renderer
      pool = Plushie::Test::SessionPool.new(
        mode: :mock,
        format: :msgpack,
        max_sessions: 2,
        binary: Plushie::Binary.path!
      )
      pool.start

      session_id = pool.register
      session = Plushie::Test::Session.new(Counter, pool: pool, session_id: session_id)

      # Verify initial state
      assert_equal 0, session.model.count

      # Click increment
      session.click("#inc")
      assert_equal 1, session.model.count

      # Click increment again
      session.click("#inc")
      assert_equal 2, session.model.count

      # Click decrement
      session.click("#dec")
      assert_equal 1, session.model.count

      # Query the tree via renderer
      count_node = session.find("#main#count")
      refute_nil count_node, "count node should be found via renderer query"

      session.stop
      pool.stop
    end

    def test_counter_tree_hash_via_mock_renderer
      pool = Plushie::Test::SessionPool.new(
        mode: :mock,
        format: :msgpack,
        max_sessions: 2,
        binary: Plushie::Binary.path!
      )
      pool.start

      session_id = pool.register
      session = Plushie::Test::Session.new(Counter, pool: pool, session_id: session_id)

      # Capture tree hash
      result = session.tree_hash("initial")
      refute_nil result
      assert result.key?(:hash) || result.key?("hash"), "tree_hash response should contain hash"

      session.stop
      pool.stop
    end

    # The tests below drive real renderer events through the decoder
    # end-to-end. They guard against silent decoder drift: a wire-shape
    # regression in key_press, cursor_moved, or wheel_scrolled would
    # surface here as zeroed-out coordinates, missing keys, or wrong
    # types. The unit tests in test_protocol_decode.rb cover the
    # decoder in isolation; these confirm the decoder agrees with what
    # the renderer actually emits over the wire, so a fixture drift on
    # either side cannot pass silently.
    #
    # animation_frame and theme_changed are not driven through the real
    # renderer here because they flow as top-level subscription events
    # without a session field, which the SessionPool drops; the unit
    # tests pin those wire shapes.

    def test_key_press_via_real_renderer_decodes_key_from_value
      with_mock_session do |session_id, pool|
        request_id = "press-1"
        pool.send_message(
          {type: "interact", id: request_id, action: "press",
           selector: {by: "id", value: ""}, payload: {combo: "Enter"}},
          session_id
        )
        events = wait_for_interact_response(pool, session_id, request_id)

        key_event = events.find { |e| e.is_a?(Plushie::Event::Key) && e.type == :press }
        refute_nil key_event, "expected Event::Key for scripting key_press"
        assert_equal :enter, key_event.key
      end
    end

    def test_cursor_moved_via_real_renderer_decodes_coords_from_value
      with_mock_session do |session_id, pool|
        request_id = "move-1"
        pool.send_message(
          {type: "interact", id: request_id, action: "move_to",
           selector: {by: "id", value: ""}, payload: {x: 123.5, y: 456.25}},
          session_id
        )
        events = wait_for_interact_response(pool, session_id, request_id)

        move = events.find do |e|
          e.is_a?(Plushie::Event::Widget) && e.type == :move && e.value[:pointer] == :mouse
        end
        refute_nil move, "expected cursor_moved Event::Widget"
        assert_in_delta 123.5, move.value[:x], 0.01
        assert_in_delta 456.25, move.value[:y], 0.01
      end
    end

    def test_wheel_scrolled_via_real_renderer_decodes_deltas_from_value
      with_mock_session do |session_id, pool|
        request_id = "scroll-1"
        pool.send_message(
          {type: "interact", id: request_id, action: "scroll",
           selector: {by: "id", value: ""}, payload: {delta_x: 10.5, delta_y: -25.0}},
          session_id
        )
        events = wait_for_interact_response(pool, session_id, request_id)

        scroll = events.find do |e|
          e.is_a?(Plushie::Event::Widget) && e.type == :scroll
        end
        refute_nil scroll, "expected wheel_scrolled Event::Widget"
        assert_in_delta 10.5, scroll.value[:delta_x], 0.01
        assert_in_delta(-25.0, scroll.value[:delta_y], 0.01)
      end
    end

    private

    # Yield a session_id and pool against a freshly spawned mock
    # renderer. Cleans up regardless of test outcome.
    def with_mock_session
      pool = Plushie::Test::SessionPool.new(
        mode: :mock, format: :msgpack, max_sessions: 1,
        binary: Plushie::Binary.path!
      )
      pool.start
      session_id = pool.register
      yield session_id, pool
    ensure
      pool&.stop
    end

    # Drain messages until the matching interact_response arrives;
    # return its embedded (already-decoded) events array.
    def wait_for_interact_response(pool, session_id, request_id, timeout: 5)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise Timeout::Error, "no interact_response for #{request_id}" if remaining <= 0

        msg = pool.read_message(session_id, timeout: remaining)
        next unless msg.is_a?(Hash)
        next unless (msg[:type] || msg["type"])&.to_sym == :interact_response
        next unless (msg[:id] || msg["id"]) == request_id

        return msg[:events] || msg["events"] || []
      end
    end

  else
    def test_skipped_no_binary
      skip "plushie binary not available (set PLUSHIE_BINARY_PATH to enable integration tests)"
    end
  end
end
