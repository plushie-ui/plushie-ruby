# frozen_string_literal: true

module Plushie
  module Widget
    # Typed builder for the button widget (Layer 2 API).
    #
    # @example Basic usage
    #   Button.new("save", "Save").set_style(:primary).build
    #
    # @example With padding and disabled state
    #   Button.new("cancel", "Cancel", padding: 8, disabled: true).build
    class Button < BuiltIn
      wire_type :button
      children :none
      positional :label
      prop :label, :width, :height, :padding,
        :clip, :style, :disabled, :a11y
    end
  end
end
