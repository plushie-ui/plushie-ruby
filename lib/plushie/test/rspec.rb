# frozen_string_literal: true

module Plushie
  module Test
    # RSpec integration for Plushie app testing.
    #
    # Provides before/after hooks that mirror the Minitest Case
    # setup/teardown, and a class-level plushie_app declaration.
    #
    # @example
    #   RSpec.describe Counter do
    #     include Plushie::Test::RSpec
    #     plushie_app Counter
    #
    #     it "increments" do
    #       click("#increment")
    #       expect(text(find!("#count"))).to eq("Count: 1")
    #     end
    #   end
    module RSpec
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
