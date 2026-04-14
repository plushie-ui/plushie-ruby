# frozen_string_literal: true

module Plushie
  module Widget
    Container = Plushie::Widget.define(:container) do
      children :single
      prop :padding, :width, :height, :max_width, :max_height, :center,
        :clip, :align_x, :align_y, :background, :color, :border,
        :shadow, :style
    end

    # Single-child container widget with alignment and styling.
    #
    # @example
    #   Container.new("box").center_x.push(Text.new("msg", "Hello")).build
    class Container
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
