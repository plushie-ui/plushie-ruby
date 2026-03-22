# frozen_string_literal: true

module Plushie
  module Test
    # RSpec integration for Plushie app testing.
    #
    # Include this module in an RSpec example group to get the full
    # Plushie test DSL (click, find!, assert_text, model, etc.) with
    # automatic session setup and teardown via before/after hooks.
    #
    # Mirrors the lifecycle provided by {Plushie::Test::Case} for
    # Minitest, so tests are interchangeable between frameworks.
    #
    # @example Basic usage
    #   RSpec.describe Counter do
    #     include Plushie::Test::RSpec
    #     plushie_app Counter
    #
    #     it "increments" do
    #       click("#increment")
    #       expect(text(find!("#count"))).to eq("Count: 1")
    #     end
    #   end
    #
    # @example Nested groups inherit the app declaration
    #   RSpec.describe Counter do
    #     include Plushie::Test::RSpec
    #     plushie_app Counter
    #
    #     context "after three clicks" do
    #       it "shows 3" do
    #         3.times { click("#increment") }
    #         expect(text(find!("#count"))).to eq("Count: 3")
    #       end
    #     end
    #   end
    module RSpec
      # Hook called when the module is included into an RSpec example group.
      # Wires up Helpers, ClassMethods, and before/after lifecycle hooks.
      #
      # @param base [Class] the including example group class
      # @return [void]
      def self.included(base)
        base.include Helpers
        base.extend ClassMethods

        base.before(:each) do
          app_class = self.class.plushie_app_class
          raise "No app declared. Add `plushie_app MyApp` to your describe block." unless app_class

          pool = Plushie::Test.pool
          session_id = pool.register
          @_plushie_session = Session.new(app_class, pool: pool, session_id: session_id)
          Thread.current[:_plushie_test_session] = @_plushie_session
        end

        base.after(:each) do
          @_plushie_session&.stop
          Thread.current[:_plushie_test_session] = nil
        end
      end

      # Class-level methods added to the RSpec describe block.
      module ClassMethods
        # Declare the app class for this example group.
        # @param klass [Class] app class (includes Plushie::App)
        def plushie_app(klass)
          @plushie_app_class = klass
        end

        # @return [Class, nil] the declared app class
        def plushie_app_class
          @plushie_app_class || (superclass.respond_to?(:plushie_app_class) && superclass.plushie_app_class)
        end
      end
    end
  end
end
