# frozen_string_literal: true

module Plushie
  module Widget
    # Button widget.
    #
    # @example
    #   Button.new("save", "Save").set_style(:primary).build
    Button = Plushie::Widget.define(:button) do
      children :none
      positional :label
      prop :label, :width, :height, :padding,
        :clip, :style, :disabled
      prop :a11y, :event_rate
      default_a11y role: :button, label_from: :label
    end
  end
end
