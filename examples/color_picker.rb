# frozen_string_literal: true

# Color picker with RGB sliders and canvas preview.
#
# Demonstrates:
# - slider widget for continuous values
# - Derived state (hex color from RGB components)
# - canvas widget for custom rendering
# - Dynamic prop values

require "plushie"

class ColorPicker
  include Plushie::App

  Model = Plushie::Model.define(:r, :g, :b)

  def init(_opts)
    Model.new(r: 100, g: 149, b: 237) # cornflowerblue
  end

  def update(model, event)
    case event
    in Event::Widget[type: :slide, id: "r", value:]
      model.with(r: value.to_i)
    in Event::Widget[type: :slide, id: "g", value:]
      model.with(g: value.to_i)
    in Event::Widget[type: :slide, id: "b", value:]
      model.with(b: value.to_i)
    else
      model
    end
  end

  def view(model)
    hex = "#%02x%02x%02x" % [model.r, model.g, model.b]

    window("main", title: "Color Picker") do
      column(padding: 24, spacing: 16, width: :fill, align_x: :center) do
        container("preview", width: 200, height: 200, background: hex)

        text("hex", hex, size: 24)

        column("sliders", spacing: 12, width: :fill) do
          slider_row("r", "Red", model.r)
          slider_row("g", "Green", model.g)
          slider_row("b", "Blue", model.b)
        end
      end
    end
  end

  private

  def slider_row(id, label_text, value)
    row(spacing: 8) do
      text("#{id}_label", "#{label_text}:", width: 60)
      slider(id, [0, 255], value, width: :fill)
      text("#{id}_value", value.to_s, width: 40)
    end
  end
end

Plushie.run(ColorPicker) if __FILE__ == $PROGRAM_NAME
