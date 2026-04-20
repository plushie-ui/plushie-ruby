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
    TextInput = Plushie::Widget.define(:text_input) do
      children :none
      positional :value, default: ""
      prop :value, :placeholder, :padding, :width, :size, :font, :line_height,
        :align_x, :icon, :on_submit, :on_paste, :secure, :input_purpose,
        :style, :placeholder_color, :selection_color,
        :required, :validation
      prop :a11y, :event_rate
      default_a11y role: :text_input, label_from: :placeholder
    end
  end
end
