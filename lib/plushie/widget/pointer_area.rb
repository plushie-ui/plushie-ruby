# frozen_string_literal: true

module Plushie
  module Widget
    # Pointer area: captures pointer events (mouse, touch, pen) on child content.
    #
    # The widget responds to all pointer input types, not just mouse.
    # The iced renderer uses "mouse_area" as the internal widget name;
    # only the SDK-facing name is "pointer_area".
    #
    # @example
    #   pa = Plushie::Widget::PointerArea.new("clickable",
    #     cursor: :pointer, on_right_press: true)
    #     .push(Plushie::Widget::Text.new("label", "Right-click me"))
    #   node = pa.build
    #
    # Props:
    # - cursor (symbol): pointer cursor on hover.
    # - on_press (string): event tag for left press.
    # - on_release (string): event tag for left release.
    # - on_right_press (boolean): enable right press events.
    # - on_right_release (boolean): enable right release events.
    # - on_middle_press (boolean): enable middle press events.
    # - on_middle_release (boolean): enable middle release events.
    # - on_double_click (boolean): enable double-click events.
    # - on_enter (boolean): enable cursor enter events.
    # - on_exit (boolean): enable cursor exit events.
    # - on_move (boolean): enable cursor move events.
    # - on_scroll (boolean): enable scroll events.
    PointerArea = Plushie::Widget.define(:mouse_area) do
      children :single
      prop :cursor, :on_press, :on_release, :on_right_press, :on_right_release,
        :on_middle_press, :on_middle_release, :on_double_click, :on_enter,
        :on_exit, :on_move, :on_scroll
    end
  end
end
