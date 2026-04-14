# frozen_string_literal: true

module Plushie
  module Widget
    # Typed builder for the column widget (Layer 2 API).
    #
    # Construct a Column, set properties via fluent +set_*+ methods,
    # then call {#build} to produce a {Plushie::Node} for the view tree.
    Column = Plushie::Widget.define(:column) do
      children :many
      prop :spacing, :padding, :width, :height, :max_width,
        :align_x, :clip, :wrap
    end
  end
end
