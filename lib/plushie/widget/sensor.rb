# frozen_string_literal: true

module Plushie
  module Widget
    # Sensor: detects visibility and size changes on child content.
    #
    # @example
    #   s = Plushie::Widget::Sensor.new("detect", delay: 100, anticipate: 50)
    #     .push(Plushie::Widget::Text.new("content", "Watched"))
    #   node = s.build
    #
    # Props:
    # - delay (integer): delay in ms before emitting events.
    # - anticipate (number): anticipation distance in pixels.
    # - on_resize (string): event tag for resize events.
    Sensor = Plushie::Widget.define(:sensor) do
      children :single
      prop :delay, :anticipate, :on_resize
      prop :a11y, :event_rate
    end
  end
end
