# frozen_string_literal: true

module Plushie
  module Widget
    # Typed builder for the container widget (Layer 2 API).
    #
    # Construct a Container, set properties via fluent +set_*+ methods,
    # then call {#build} to produce a {Plushie::Node} for the view tree.
    class Container < BuiltIn
      wire_type :container
      children :single
      prop :padding, :width, :height, :max_width, :max_height, :center,
        :clip, :align_x, :align_y, :background, :color, :border,
        :shadow, :style, :a11y

      # Return a copy with horizontal centering enabled.
      def center_x(width = :fill)
        dup.tap do |c|
          c.instance_variable_set(:@width, width)
          c.instance_variable_set(:@align_x, :center)
        end
      end

      # Return a copy with vertical centering enabled.
      def center_y(height = :fill)
        dup.tap do |c|
          c.instance_variable_set(:@height, height)
          c.instance_variable_set(:@align_y, :center)
        end
      end
    end
  end
end
