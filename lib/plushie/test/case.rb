# frozen_string_literal: true

require "minitest/test"

module Plushie
  module Test
    # Minitest test case base class for Plushie app testing.
    #
    # Inherits from Minitest::Test. Includes all test helpers and
    # manages session lifecycle automatically.
    #
    # @example
    #   class CounterTest < Plushie::Test::Case
    #     app Counter
    #
    #     def test_clicking_increment_updates_counter
    #       click("#increment")
    #       assert_text "#count", "Count: 1"
    #     end
    #
    #     def test_double_increment
    #       click("#increment")
    #       click("#increment")
    #       assert_text "#count", "Count: 2"
    #     end
    #   end
    class Case < Minitest::Test
      include Helpers

      class << self
        # Declare the app class for this test case.
        # @param klass [Class] app class (includes Plushie::App)
        def app(klass)
          @plushie_app_class = klass
        end

        # @return [Class] the declared app class
        attr_reader :plushie_app_class
      end

      # Setup: start a test session with the declared app.
      def setup
        super
        app_class = self.class.plushie_app_class
        raise "No app declared. Add `app MyApp` to your test class." unless app_class

        pool = Plushie::Test.pool
        session_id = pool.register
        @_plushie_session = Session.new(app_class, pool: pool, session_id: session_id)
        Thread.current[:_plushie_test_session] = @_plushie_session
      end

      # Teardown: stop the session and clean up.
      def teardown
        @_plushie_session&.stop
        Thread.current[:_plushie_test_session] = nil
        super
      end
    end
  end
end
