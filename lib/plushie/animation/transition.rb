# frozen_string_literal: true

module Plushie
  module Animation
    # Renderer-side timed transition descriptor.
    #
    # Declares animation intent in the view. The renderer handles
    # interpolation locally with zero wire traffic during animation.
    #
    # @example Basic transition
    #   button("fade", "Click",
    #     opacity: Transition.build(300, to: 0.0))
    #
    # @example With easing and delay
    #   container("slide",
    #     translate_y: Transition.build(200, to: 0, from: 20,
    #       easing: :ease_out, delay: 50))
    #
    # @example Looping
    #   text("pulse", "!",
    #     opacity: Transition.loop(800, to: 0.4, from: 1.0))
    #
    # @example Completion event
    #   container("item",
    #     opacity: Transition.build(300, to: 0.0, on_complete: :faded_out))
    #
    Transition = Data.define(
      :to, :duration, :easing, :delay,
      :from, :repeat, :auto_reverse, :on_complete
    ) do
      # @param to [Object] target value (required)
      # @param duration [Integer, nil] duration in milliseconds
      # @param easing [Symbol] easing curve name (default: :ease_in_out)
      # @param delay [Integer] delay before start in milliseconds (default: 0)
      # @param from [Object, nil] starting value (nil = current value)
      # @param repeat [Integer, :forever, nil] repeat count
      # @param auto_reverse [Boolean] reverse on each cycle (default: false)
      # @param on_complete [Symbol, nil] event tag fired on completion
      def initialize(
        to:, duration: nil, easing: :ease_in_out, delay: 0,
        from: nil, repeat: nil, auto_reverse: false, on_complete: nil
      )
        super
      end

      # @return [Hash] wire-ready descriptor map
      def to_wire
        h = {type: "transition", to: to}
        h[:duration] = duration if duration
        h[:easing] = easing.to_s unless easing == :ease_in_out
        h[:delay] = delay unless delay == 0
        h[:from] = from unless from.nil?
        h[:repeat] = (repeat == :forever) ? -1 : repeat if repeat
        h[:auto_reverse] = auto_reverse if auto_reverse
        h[:on_complete] = on_complete.to_s if on_complete
        h
      end

      # Create a transition with duration as a positional argument.
      #
      # @param duration [Integer] duration in milliseconds
      # @param opts [Hash] transition options (must include :to)
      # @return [Transition]
      def self.build(duration, **opts)
        raise ArgumentError, "duration must be an Integer" unless duration.is_a?(Integer)
        raise ArgumentError, "transition requires a :to value" unless opts.key?(:to)

        new(duration: duration, **opts)
      end

      # Create a looping transition.
      #
      # @param duration [Integer] duration per cycle in milliseconds
      # @param cycles [Integer, nil] number of cycles (nil = forever)
      # @param reverse [Boolean] auto-reverse on each cycle (default: true)
      # @param opts [Hash] must include :to
      # @return [Transition]
      def self.loop(duration, cycles: nil, reverse: true, **opts)
        build(duration,
          repeat: cycles || :forever,
          auto_reverse: reverse,
          **opts)
      end
    end
  end
end
