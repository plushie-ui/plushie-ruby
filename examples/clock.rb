# frozen_string_literal: true

require "plushie"

# Clock example showing the current time, updated every second.
#
# Demonstrates:
# - Subscription.every for timer-based updates
# - Pattern matching on Event::Timer in update
# - Simple model with derived display value
class Clock
  include Plushie::App

  Model = Plushie::Model.define(:time)

  def init(_opts) = Model.new(time: current_time)

  def update(model, event)
    case event
    in Event::Timer[tag: :tick]
      model.with(time: current_time)
    else
      model
    end
  end

  def subscribe(_model)
    [Subscription.every(1000, :tick)]
  end

  def view(model)
    window("main", title: "Clock") do
      column(padding: 24, spacing: 16, width: :fill, align_x: :center) do
        text("clock_display", model.time, size: 48)
        text("subtitle", "Updates every second", size: 12, color: "#888888")
      end
    end
  end

  private

  def current_time = Time.now.utc.strftime("%H:%M:%S")
end
