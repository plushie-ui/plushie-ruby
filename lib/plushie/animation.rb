# frozen_string_literal: true

require_relative "animation/tween"
require_relative "animation/transition"
require_relative "animation/spring"
require_relative "animation/sequence"

module Plushie
  # Animation system.
  #
  # == Renderer-side descriptors (preferred)
  #
  # Transition, Spring, and Sequence are pure data descriptors that tell
  # the renderer how to animate a prop. The renderer interpolates locally
  # with zero wire traffic during animation. Use these for visual
  # property animations (opacity, position, size, color).
  #
  #   container("card",
  #     opacity: Animation::Transition.new(300, to: 1.0, from: 0.0),
  #     scale: Animation::Spring.new(to: 1.0, preset: :bouncy))
  #
  # == SDK-side tween (when needed)
  #
  # Animation::Tween is a manual interpolator for cases where you need
  # host-side control over the animated value. Requires subscribing to
  # animation frames and advancing the tween each tick.
  #
  module Animation
  end
end
