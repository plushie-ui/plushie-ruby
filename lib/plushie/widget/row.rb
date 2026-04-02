# frozen_string_literal: true

module Plushie
  module Widget
    # Typed builder for the row widget (Layer 2 API).
    #
    # Construct a Row, set properties via fluent +set_*+ methods,
    # then call {#build} to produce a {Plushie::Node} for the view tree.
    class Row < BuiltIn
      wire_type :row
      children :many
      prop :spacing, :padding, :width, :height, :align_y,
        :max_width, :clip, :wrap, :a11y
    end
  end
end
