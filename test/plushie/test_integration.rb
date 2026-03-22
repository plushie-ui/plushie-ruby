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
      session.click("#increment")
      assert_equal 1, session.model.count

      # Click increment again
      session.click("#increment")
      assert_equal 2, session.model.count

      # Click decrement
      session.click("#decrement")
      assert_equal 1, session.model.count

      # Query the tree via renderer
      count_node = session.find("#count")
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
  else
    def test_skipped_no_binary
      skip "plushie binary not available (set PLUSHIE_BINARY_PATH to enable integration tests)"
    end
  end
end
