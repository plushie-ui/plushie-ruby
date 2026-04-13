# frozen_string_literal: true

module Plushie
  module Animation
    # SDK-side animation interpolation.
    #
    # Pure functions operating on structs for manual, host-side animations.
    # The host computes interpolated values on each animation frame tick.
    #
    # For most use cases, prefer renderer-side descriptors (Transition,
    # Spring, Sequence) which animate with zero wire traffic. Use Tween
    # when you need host-side control over the interpolated value (e.g.,
    # driving non-visual state from an animation).
    #
    # == Easing functions
    #
    # All easing functions take a +t+ value in 0.0..1.0 and return a
    # curved +t+ value. Available easings:
    #
    # - +linear+: identity
    # - +ease_in+: cubic ease in
    # - +ease_out+: cubic ease out
    # - +ease_in_out+: cubic ease in-out
    # - +ease_in_quad+: quadratic ease in
    # - +ease_out_quad+: quadratic ease out
    # - +ease_in_out_quad+: quadratic ease in-out
    # - +spring+: spring with overshoot
    #
    # == Animation struct
    #
    # The Tween tracks a single animated value over time.
    # Create one with +new+, start it with +start+, and advance it on
    # each frame with +advance+.
    #
    # @example
    #   anim = Plushie::Animation::Tween.new(0.0, 1.0, 300, easing: :ease_out)
    #   anim = Plushie::Animation::Tween.start(anim, timestamp)
    #   value, anim = Plushie::Animation::Tween.advance(anim, next_timestamp)
    #
    class Tween
      # Immutable animation state.
      State = ::Data.define(:from, :to, :duration, :started_at, :easing, :value) do
        include Plushie::Model::Extensions
      end

      # -- Easing functions ---------------------------------------------------

      EASINGS = {
        linear: ->(t) { t },

        ease_in: ->(t) { t * t * t },

        ease_out: ->(t) {
          inv = 1.0 - t
          1.0 - inv * inv * inv
        },

        ease_in_out: ->(t) {
          if t < 0.5
            4.0 * t * t * t
          else
            inv = -2.0 * t + 2.0
            1.0 - inv * inv * inv / 2.0
          end
        },

        ease_in_quad: ->(t) { t * t },

        ease_out_quad: ->(t) { 1.0 - (1.0 - t) * (1.0 - t) },

        ease_in_out_quad: ->(t) {
          if t < 0.5
            2.0 * t * t
          else
            1.0 - (-2.0 * t + 2.0)**2 / 2.0
          end
        },

        spring: ->(t) {
          if t <= 0.0
            0.0
          elsif t >= 1.0
            1.0
          else
            c4 = 2.0 * Math::PI / 3.0
            2.0**(-10.0 * t) * Math.sin((t * 10.0 - 0.75) * c4) + 1.0
          end
        }
      }.freeze

      # Convenience class methods for each easing function.
      EASINGS.each_key do |name|
        define_singleton_method(name) { |t| EASINGS[name].call(t) }
      end

      # -- Interpolation ------------------------------------------------------

      # Linearly interpolate between +from+ and +to+ at progress +t+,
      # with an optional easing function applied to +t+ first.
      #
      # @param from [Numeric] start value
      # @param to [Numeric] end value
      # @param t [Numeric] progress (0.0 to 1.0)
      # @param easing [Proc, Symbol] easing function or symbol name
      # @return [Float]
      def self.interpolate(from, to, t, easing = :linear)
        easing_fn = resolve_easing(easing)
        clamped = clamp(t)
        eased = easing_fn.call(clamped)
        from + (to - from) * eased
      end

      # -- Animation lifecycle ------------------------------------------------

      # Create a new animation.
      #
      # @param from [Numeric] start value
      # @param to [Numeric] end value
      # @param duration_ms [Integer] duration in milliseconds (must be > 0)
      # @param easing [Proc, Symbol] easing function or name (default: :linear)
      # @return [State]
      def self.new(from, to, duration_ms, easing: :linear)
        raise ArgumentError, "duration_ms must be positive" unless duration_ms.is_a?(Integer) && duration_ms > 0

        State.new(
          from: from,
          to: to,
          duration: duration_ms,
          started_at: nil,
          easing: easing,
          value: from
        )
      end

      # Start (or restart) the animation at the given frame timestamp.
      #
      # @param anim [State]
      # @param timestamp [Integer] frame timestamp in milliseconds
      # @return [State]
      def self.start(anim, timestamp)
        anim.with(started_at: timestamp, value: anim.from)
      end

      # Advance the animation to the given frame timestamp.
      #
      # Returns +[current_value, updated_animation]+ while the animation is
      # in progress, or +[final_value, :finished]+ when it completes.
      #
      # @param anim [State]
      # @param timestamp [Integer]
      # @return [Array(Numeric, State), Array(Numeric, Symbol)]
      def self.advance(anim, timestamp)
        return [anim.value, anim] if anim.started_at.nil?

        elapsed = timestamp - anim.started_at
        t = clamp(elapsed.to_f / anim.duration)
        current = interpolate(anim.from, anim.to, t, anim.easing)

        if t >= 1.0
          [anim.to, :finished]
        else
          [current, anim.with(value: current)]
        end
      end

      # Returns true if the animation has run to completion.
      #
      # @param anim [State]
      # @return [Boolean]
      def self.finished?(anim)
        return false if anim.started_at.nil?
        anim.value == anim.to
      end

      # Return the current interpolated value.
      # @param anim [State]
      # @return [Numeric]
      def self.value(anim) = anim.value

      # -- Private ------------------------------------------------------------

      # @api private
      def self.clamp(t)
        return 0.0 if t < 0
        return 1.0 if t > 1.0
        t.to_f
      end

      # Resolve an easing symbol or proc to a callable.
      # @api private
      def self.resolve_easing(easing)
        case easing
        when Symbol
          EASINGS.fetch(easing) { raise ArgumentError, "unknown easing: #{easing}" }
        when Proc
          easing
        else
          raise ArgumentError, "easing must be a Symbol or Proc, got #{easing.class}"
        end
      end

      private_class_method :clamp, :resolve_easing
    end
  end
end
