# frozen_string_literal: true

module Plushie
  module Widget
    # Typed builder for the window widget (Layer 2 API).
    #
    # Construct a Window, set properties via fluent +set_*+ methods,
    # then call {#build} to produce a {Plushie::Node} for the view tree.
    #
    # Props:
    # - width (length): content width layout ("fill", "shrink", number, or {fill_portion: n}).
    # - height (length): content height layout ("fill", "shrink", number, or {fill_portion: n}).
    # - theme (symbol|hash): built-in theme name, :system, or Theme.custom result.
    Window = Plushie::Widget.define(:window) do
      children :single
      prop :title, :size, :width, :height, :position, :min_size, :max_size,
        :maximized, :fullscreen, :visible, :resizable, :closeable,
        :minimizable, :decorations, :transparent, :blur, :level,
        :exit_on_close_request, :scale_factor, :theme
      default_a11y role: :window
    end
  end
end
