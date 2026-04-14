# frozen_string_literal: true

module Plushie
  module Widget
    # Themer: per-subtree theme override.
    #
    # @example
    #   t = Plushie::Widget::Themer.new("dark", :dark)
    #     .push(Plushie::Widget::Text.new("msg", "Dark themed"))
    #   node = t.build
    #
    # Props:
    # - theme (symbol|hash): built-in theme atom or custom palette map.
    Themer = Plushie::Widget.define(:themer) do
      children :single
      positional :theme, default: nil
      prop :theme
    end
  end
end
