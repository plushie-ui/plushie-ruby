# frozen_string_literal: true

module Plushie
  module Widget
    # Combo box: searchable dropdown with free-form text input.
    #
    # @example
    #   cb = Plushie::Widget::ComboBox.new("fruit", ["Apple", "Banana"],
    #     selected: "Apple", placeholder: "Search...")
    #   node = cb.build
    #
    # Props:
    # - options (array of strings): available choices.
    # - selected (string|nil): currently selected value.
    # - placeholder (string): placeholder text.
    # - width (length): widget width.
    # - padding (number|hash): internal padding.
    # - size (number): text size in pixels.
    # - font (string|hash): font specification.
    # - line_height (number|hash): text line height.
    # - menu_height (number): max dropdown menu height in pixels.
    # - icon (hash): icon inside the text input.
    # - on_option_hovered (boolean): emit option hover events.
    # - on_open (boolean): emit open event.
    # - on_close (boolean): emit close event.
    # - shaping (symbol): text shaping strategy.
    # - ellipsis (string): text ellipsis strategy.
    # - menu_style (hash): dropdown menu style overrides.
    # - style (symbol|hash): named style or style map.
    ComboBox = Plushie::Widget.define(:combo_box) do
      children :none
      positional :options, default: []
      prop :options, :selected, :placeholder, :width, :padding, :size, :font,
        :line_height, :menu_height, :icon, :on_option_hovered, :on_open,
        :on_close, :shaping, :ellipsis, :menu_style, :style,
        :required, :validation
      default_a11y role: :combo_box, label_from: :placeholder
    end
  end
end
