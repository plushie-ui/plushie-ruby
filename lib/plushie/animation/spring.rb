# frozen_string_literal: true

module Plushie
  module Animation
    # Named spring presets.
    SPRING_PRESETS = {
      gentle: {stiffness: 120, damping: 14},
      bouncy: {stiffness: 300, damping: 10},
      stiff: {stiffness: 400, damping: 30},
      snappy: {stiffness: 200, damping: 20},
      molasses: {stiffness: 60, damping: 12}
    }.freeze

    # Renderer-side physics-based spring descriptor.
    #
    # Springs animate using a damped harmonic oscillator simulation.
    # Unlike timed transitions, springs have no fixed duration: they
    # settle naturally based on stiffness, damping, and mass. This
    # makes them ideal for interactive animations where the target
    # changes frequently (drag, scroll, hover) because interruption
    # preserves velocity for smooth redirection.
    #
    # @example Custom parameters
    #   container("card",
    #     scale: Spring.build(to: 1.05, stiffness: 200, damping: 20))
    #
    # @example Named preset
    #   container("card",
    #     scale: Spring.build(to: 1.05, preset: :bouncy))
    #
    # == Presets
    #
    # - +:gentle+: slow, smooth, no overshoot
    # - +:snappy+: quick, minimal overshoot
    # - +:bouncy+: quick with visible overshoot
    # - +:stiff+: very quick, crisp stop
    # - +:molasses+: slow, heavy, deliberate
    #
    Spring = Data.define(
      :to, :from, :stiffness, :damping, :mass,
      :velocity, :on_complete
    ) do
      # @param to [Object] target value (required)
      # @param from [Object, nil] starting value (nil = current value)
      # @param stiffness [Numeric] spring stiffness (default: 170)
      # @param damping [Numeric] damping ratio (default: 26)
      # @param mass [Numeric] oscillator mass (default: 1.0)
      # @param velocity [Numeric] initial velocity (default: 0.0)
      # @param on_complete [Symbol, nil] event tag fired when settled
      def initialize(
        to:, from: nil, stiffness: 170, damping: 26, mass: 1.0,
        velocity: 0.0, on_complete: nil
      )
        super
      end

      # @return [Hash] wire-ready descriptor map
      def to_wire
        h = {type: "spring", to: to, stiffness: stiffness, damping: damping, mass: mass}
        h[:from] = from unless from.nil?
        h[:velocity] = velocity unless velocity == 0.0
        h[:on_complete] = on_complete.to_s if on_complete
        h
      end

      # Create a spring with optional preset expansion.
      #
      # @param opts [Hash] spring options
      # @option opts [Object] :to target value (required)
      # @option opts [Symbol] :preset named preset (:gentle, :bouncy, etc.)
      # @return [Spring]
      def self.build(**opts)
        raise ArgumentError, "spring requires a :to value" unless opts.key?(:to)

        if (preset = opts.delete(:preset))
          values = SPRING_PRESETS.fetch(preset) do
            raise ArgumentError,
              "unknown spring preset #{preset.inspect}. " \
              "Available: #{SPRING_PRESETS.keys.inspect}"
          end
          opts = values.merge(opts)
        end

        new(**opts)
      end
    end
  end
end
