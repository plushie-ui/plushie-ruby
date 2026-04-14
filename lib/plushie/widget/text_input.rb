# frozen_string_literal: true

module Plushie
  module Widget
    # Typed builder for the single-line text input widget (Layer 2 API).
    #
    # Construct a TextInput, configure via fluent +set_*+ methods,
    # then call {#build} to produce a {Plushie::Node}.
    #
    # @example
    #   TextInput.new("email", "", placeholder: "you@example.com")
    #     .set_size(16)
    #     .build
    class TextInput < BuiltIn
      wire_type :text_input
      children :none
      positional :value, default: ""
      prop :value, :placeholder, :padding, :width, :size, :font, :line_height,
        :align_x, :icon, :on_submit, :on_paste, :secure, :input_purpose,
        :style, :placeholder_color, :selection_color, :a11y
    end
  end
end
