# frozen_string_literal: true

require "plushie"

class Counter
  include Plushie::App

  Model = Plushie::Model.define(:count)

  def init(_opts) = Model.new(count: 0)

  def update(model, event)
    case event
    in Event::Widget[type: :click, id: "increment"]
      model.with(count: model.count + 1)
    in Event::Widget[type: :click, id: "decrement"]
      model.with(count: model.count - 1)
    else
      model
    end
  end

  def view(model)
    window("main", title: "Counter") do
      column(padding: 16, spacing: 8) do
        text("count", "Count: #{model.count}")
        row(spacing: 8) do
          button("increment", "+")
          button("decrement", "-")
        end
      end
    end
  end
end
