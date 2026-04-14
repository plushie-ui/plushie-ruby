# frozen_string_literal: true

module Plushie
  module Widget
    # Stack layout: layers children on top of each other.
    #
    # @example
    #   s = Plushie::Widget::Stack.new("layers", width: :fill, clip: true)
    #     .push(Plushie::Widget::Text.new("bg", "Background"))
    #     .push(Plushie::Widget::Text.new("fg", "Foreground"))
    #   node = s.build
    #
    # Props:
    # - width (length): stack width.
    # - height (length): stack height.
    # - clip (boolean): clip overflowing children.
    Stack = Plushie::Widget.define(:stack) do
      children :many
      prop :width, :height, :clip
    end
  end
end
