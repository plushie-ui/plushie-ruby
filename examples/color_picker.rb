# frozen_string_literal: true

# HSV color picker using a canvas_widget.
#
# The color picker widget handles all interaction internally (mouse drag,
# keyboard adjustment, focus tracking). The app receives :change events
# with the current HSV values.

require "plushie"
require_relative "widgets/color_picker_widget"

class ColorPicker
  include Plushie::App

  Model = Plushie::Model.define(:hue, :saturation, :value)

  def init(_opts)
    Model.new(hue: 0.0, saturation: 1.0, value: 1.0)
  end

  def update(model, event)
    case event
    in Event::Widget[type: :change, id: "picker", data:]
      model.with(
        hue: data["hue"],
        saturation: data["saturation"],
        value: data["value"]
      )
    else
      model
    end
  end

  def view(model)
    hex = hsv_to_hex(model.hue, model.saturation, model.value)

    window("color_picker", title: "Color Picker") do
      column(padding: 20, spacing: 16, align_x: :center) do
        ColorPickerWidget.new("picker")

        row(spacing: 16, align_y: :center) do
          container("swatch", width: 48, height: 48, background: hex,
            border: {width: 1, color: "#cccccc", rounded: 4},
            a11y: {role: :image, label: "Selected color: #{hex}"})

          column(spacing: 4) do
            text("hex_display", hex, size: 18,
              a11y: {live: :polite, busy: model.hue.zero? && model.saturation >= 1.0 && model.value >= 1.0})
            text("hsv_display", hsv_label(model),
              a11y: {live: :polite})
          end
        end
      end
    end
  end

  private

  def hsv_label(model)
    h_int = model.hue.round
    s_pct = (model.saturation * 100).round
    v_pct = (model.value * 100).round
    "H: #{h_int}  S: #{s_pct}%  V: #{v_pct}%"
  end

  def hsv_to_hex(h, s, v)
    h = fmod(h, 360.0)
    h += 360.0 if h < 0

    c = v * s
    h_sector = h / 60.0
    x = c * (1.0 - (fmod(h_sector, 2.0) - 1.0).abs)
    m = v - c

    r1, g1, b1 =
      if h_sector < 1 then [c, x, 0.0]
      elsif h_sector < 2 then [x, c, 0.0]
      elsif h_sector < 3 then [0.0, c, x]
      elsif h_sector < 4 then [0.0, x, c]
      elsif h_sector < 5 then [x, 0.0, c]
      else [c, 0.0, x]
      end

    r = ((r1 + m) * 255).round
    g = ((g1 + m) * 255).round
    b = ((b1 + m) * 255).round

    "#%02x%02x%02x" % [r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255)]
  end

  def fmod(a, b)
    a - b * (a / b).floor
  end
end

Plushie.run(ColorPicker) if __FILE__ == $PROGRAM_NAME
