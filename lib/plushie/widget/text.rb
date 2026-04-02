# frozen_string_literal: true

module Plushie
  module Widget
    # Typed builder for the text widget (Layer 2 API).
    #
    # Construct a Text, set properties via fluent +set_*+ methods,
    # then call {#build} to produce a {Plushie::Node} for the view tree.
    class Text < BuiltIn
      wire_type :text
      children :none
      positional :content, default: nil
      prop :content, :size, :color, :font, :width, :height, :line_height,
        :align_x, :align_y, :wrapping, :ellipsis, :shaping, :style, :a11y
    end
  end
end
