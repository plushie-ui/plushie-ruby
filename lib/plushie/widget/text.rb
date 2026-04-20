# frozen_string_literal: true

module Plushie
  module Widget
    # Typed builder for the text widget (Layer 2 API).
    #
    # Construct a Text, set properties via fluent +set_*+ methods,
    # then call {#build} to produce a {Plushie::Node} for the view tree.
    Text = Plushie::Widget.define(:text) do
      children :none
      positional :content, default: nil
      prop :content, :size, :color, :font, :width, :height, :line_height,
        :align_x, :align_y, :wrapping, :ellipsis, :shaping, :style
      prop :a11y, :event_rate
      default_a11y role: :label, label_from: :content
    end
  end
end
