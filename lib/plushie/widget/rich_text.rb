# frozen_string_literal: true

module Plushie
  module Widget
    # Rich text display with individually styled spans.
    #
    # @example
    #   rt = Plushie::Widget::RichText.new("msg",
    #     spans: [{text: "Hello ", size: 16}, {text: "World", color: "#f00"}])
    #   node = rt.build
    #
    # Props:
    # - spans (array of hashes) -- list of span descriptors.
    # - width (length) -- widget width.
    # - height (length) -- widget height.
    # - size (number) -- default font size.
    # - font (string|hash) -- default font.
    # - color (string) -- default text color.
    # - line_height (number|hash) -- line height.
    # - wrapping (symbol) -- text wrapping mode.
    # - ellipsis (string) -- text ellipsis mode.
    # - a11y (hash) -- accessibility overrides.
    class RichText < BuiltIn
      wire_type :rich_text
      children :none
      prop :spans, :width, :height, :size, :font, :color, :line_height,
        :wrapping, :ellipsis, :a11y
    end
  end
end
