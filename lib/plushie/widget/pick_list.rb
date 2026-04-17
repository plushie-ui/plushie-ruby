# frozen_string_literal: true

module Plushie
  module Widget
    # Pick list: dropdown selection.
    #
    # @example
    #   pl = Plushie::Widget::PickList.new("color", ["Red", "Green", "Blue"],
    #     selected: "Red", placeholder: "Choose...")
    #   node = pl.build
    #
    # Props:
    # - options (array of strings): available choices.
    # - selected (string|nil): currently selected value.
    # - placeholder (string): placeholder text.
    # - width (length): widget width.
    # - padding (number|hash): internal padding.
    # - text_size (number): text size in pixels.
    # - font (string|hash): font specification.
    # - line_height (number|hash): text line height.
    # - menu_height (number): max dropdown menu height in pixels.
    # - shaping (symbol): text shaping strategy.
    # - handle (hash): dropdown handle indicator config.
    # - ellipsis (string): text ellipsis strategy.
    # - menu_style (hash): dropdown menu style overrides.
    # - style (symbol|hash): named style or style map.
    # - on_open (boolean): emit open event.
    # - on_close (boolean): emit close event.
    PickList = Plushie::Widget.define(:pick_list) do
      children :none
      positional :options, default: []
      prop :options, :selected, :placeholder, :width, :padding, :text_size,
        :font, :line_height, :menu_height, :shaping, :handle, :ellipsis,
        :menu_style, :style, :on_open, :on_close,
        :required, :validation
      default_a11y role: :combo_box, label_from: :placeholder
    end
  end
end
