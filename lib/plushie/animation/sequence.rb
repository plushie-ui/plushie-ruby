# frozen_string_literal: true

module Plushie
  module Animation
    # Renderer-side sequential animation chain.
    #
    # Chains multiple transitions and springs that execute one after
    # another on the same prop. Each step's +from:+ defaults to the
    # previous step's final value if not specified.
    #
    # @example
    #   container("item",
    #     opacity: Sequence.new([
    #       Transition.new(200, to: 1.0, from: 0.0),
    #       Transition.loop(800, to: 0.7, from: 1.0, cycles: 3),
    #       Transition.new(300, to: 0.0)
    #     ]))
    #
    # @example With completion event
    #   container("item",
    #     opacity: Sequence.new([
    #       Transition.new(200, to: 1.0, from: 0.0),
    #       Transition.new(300, to: 0.0)
    #     ], on_complete: :fade_cycle_done))
    #
    Sequence = Data.define(:steps, :on_complete) do
      # @param steps [Array<Transition, Spring>] animation steps
      # @param on_complete [Symbol, nil] event tag fired on sequence completion
      def initialize(steps:, on_complete: nil)
        super
      end

      # @return [Hash] wire-ready descriptor map
      def to_wire
        h = {
          type: "sequence",
          steps: steps.map(&:to_wire)
        }
        h[:on_complete] = on_complete.to_s if on_complete
        h
      end
    end

    # Reopen to validate steps in new.
    class Sequence
      class << self
        alias_method :_data_new, :new

        # Create a sequence from a list of transition/spring steps.
        #
        #   Sequence.new([Transition.new(200, to: 1.0), Transition.new(300, to: 0.0)])
        #
        # @param steps [Array<Transition, Spring>] animation steps
        # @param opts [Hash] sequence options
        # @option opts [Symbol] :on_complete event tag on completion
        # @return [Sequence]
        def new(steps, **opts)
          unless steps.is_a?(Array) && steps.all? { |s| s.respond_to?(:to_wire) }
            raise ArgumentError, "sequence steps must be an Array of Transition/Spring descriptors"
          end
          _data_new(steps: steps, **opts)
        end
      end
    end
  end
end
