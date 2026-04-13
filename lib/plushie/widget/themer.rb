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
    # - a11y (hash): accessibility overrides.
    class Themer < BuiltIn
      wire_type :themer
      children :single
      positional :theme, default: nil
      prop :theme, :a11y
    end
  end
end
