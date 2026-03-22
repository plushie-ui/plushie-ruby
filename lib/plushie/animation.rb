# frozen_string_literal: true

module Plushie
  # Server-side animation interpolation and easing functions.
  #
  # Pure functions operating on structs -- no threads, no state management
  # beyond what lives in your app model. The host computes interpolated
  # values on each animation frame tick.
  #
  # == Easing functions
  #
  # All easing functions take a +t+ value in 0.0..1.0 and return a
  # curved +t+ value. Available easings:
  #
  # - +linear+ -- identity
  # - +ease_in+ -- cubic ease in
  # - +ease_out+ -- cubic ease out
  # - +ease_in_out+ -- cubic ease in-out
  # - +ease_in_quad+ -- quadratic ease in
  # - +ease_out_quad+ -- quadratic ease out
  # - +ease_in_out_quad+ -- quadratic ease in-out
  # - +spring+ -- spring with overshoot
  #
  # == Interpolation
  #
  # +interpolate+ lerps between two numbers with an optional easing
  # function applied to +t+.
  #
  # == Animation struct
  #
  # The Animation tracks a single animated value over time.
  # Create one with +new+, start it with +start+, and advance it on
  # each frame with +advance+.
  #
  # @example
  #   anim = Plushie::Animation.new(0.0, 1.0, 300, easing: :ease_out)
  #   anim = Plushie::Animation.start(anim, timestamp)
  #   value, anim = Plushie::Animation.advance(anim, next_timestamp)
  #
  class Animation
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
        if t == 0.0
          0.0
        elsif t == 1.0
          1.0
        else
          c4 = 2.0 * Math::PI / 3.0
          2.0**(-10.0 * t) * Math.sin((t * 10.0 - 0.75) * c4) + 1.0
        end
      }
    }.freeze

    # Linear easing (identity). Returns +t+ unchanged.
    # @param t [Float]
    # @return [Float]
    def self.linear(t) = EASINGS[:linear].call(t)

    # Cubic ease in. Starts slow, accelerates.
    # @param t [Float]
    # @return [Float]
    def self.ease_in(t) = EASINGS[:ease_in].call(t)

    # Cubic ease out. Starts fast, decelerates.
    # @param t [Float]
    # @return [Float]
    def self.ease_out(t) = EASINGS[:ease_out].call(t)

    # Cubic ease in-out. Slow start, fast middle, slow end.
    # @param t [Float]
    # @return [Float]
    def self.ease_in_out(t) = EASINGS[:ease_in_out].call(t)

    # Quadratic ease in. Starts slow, accelerates.
    # @param t [Float]
    # @return [Float]
    def self.ease_in_quad(t) = EASINGS[:ease_in_quad].call(t)

    # Quadratic ease out. Starts fast, decelerates.
    # @param t [Float]
    # @return [Float]
    def self.ease_out_quad(t) = EASINGS[:ease_out_quad].call(t)

    # Quadratic ease in-out. Slow start and end, fast middle.
    # @param t [Float]
    # @return [Float]
    def self.ease_in_out_quad(t) = EASINGS[:ease_in_out_quad].call(t)

    # Spring easing with overshoot. Overshoots the target slightly
    # before settling. Uses a single-period damped sine approximation.
    # @param t [Float]
    # @return [Float]
    def self.spring(t) = EASINGS[:spring].call(t)

    # -- Interpolation ------------------------------------------------------

    # Linearly interpolate between +from+ and +to+ at progress +t+,
    # with an optional easing function applied to +t+ first.
    #
    # +t+ is clamped to 0.0..1.0 before easing is applied.
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
    # Resets the current value to +from+.
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
    # If the animation has not been started yet, returns +[from, animation]+
    # unchanged.
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
    # Note: once +advance+ returns +[value, :finished]+, the animation
    # struct is no longer updated. Use the +:finished+ return value from
    # +advance+ as the primary completion signal.
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
