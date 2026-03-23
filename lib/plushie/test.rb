# frozen_string_literal: true

require_relative "test/session_pool"
require_relative "test/session"
require_relative "test/helpers"
require_relative "test/case"
require_relative "test/rspec"
require_relative "test/snapshot"
require_relative "test/event_decoder"
require_relative "test/script"
require_relative "test/script/runner"

module Plushie
  # Test framework for Plushie apps.
  #
  # All testing goes through the renderer binary (no Ruby-side mocks).
  # The mock backend is fast enough (~ms per interaction) for TDD.
  #
  # @example Minitest
  #   class CounterTest < Plushie::Test::Case
  #     app Counter
  #
  #     def test_increment
  #       click("#increment")
  #       assert_text "#count", "Count: 1"
  #     end
  #   end
  #
  # @example RSpec
  #   RSpec.describe Counter do
  #     include Plushie::Test::Helpers
  #     before { plushie_start(Counter) }
  #     after { plushie_stop }
  #
  #     it "increments" do
  #       click("#increment")
  #       expect(text(find!("#count"))).to eq("Count: 1")
  #     end
  #   end
  module Test
    @pool = nil
    @pool_mutex = Mutex.new

    # Get or create the shared session pool.
    # Lazy-initialized on first access. Cleaned up at_exit.
    #
    # @return [SessionPool]
    def self.pool
      @pool_mutex.synchronize do
        @pool ||= create_pool
      end
    end

    # @return [Symbol] :mock, :headless, or :windowed
    def self.backend
      env = ENV["PLUSHIE_TEST_BACKEND"]
      return env.to_sym if env && !env.empty?
      Plushie.configuration.test_backend || :mock
    end

    private_class_method def self.create_pool
      pool = SessionPool.new(
        mode: backend,
        format: :msgpack,
        max_sessions: 8,
        binary: Binary.path!
      )
      pool.start
      at_exit { pool.stop }
      pool
    end
  end
end
