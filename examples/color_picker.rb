# frozen_string_literal: true

# HSV color picker using a custom canvas widget.
#
# A hue ring surrounds a saturation/value square. Drag the ring to select
# a hue; drag the square to adjust saturation and value. The selected color
# is displayed as a swatch and hex string below the canvas.
#
# Demonstrates:
# - Canvas widget with layers (ring, SV gradients, cursors)
# - Canvas press/move/release events for drag interaction
# - Path shapes for hue ring segments
# - Linear gradients for SV square
# - HSV to hex color conversion

require "plushie"
require_relative "widgets/color_picker_widget"

class ColorPicker
  include Plushie::App

  Model = Plushie::Model.define(:hue, :saturation, :value, :drag)

  def init(_opts)
    Model.new(hue: 0.0, saturation: 1.0, value: 1.0, drag: :none)
  end

  def update(model, event)
    case event
    in Event::Canvas[type: :press, id: "picker", x:, y:, button: "left"]
      dx = x - ColorPickerWidget::CX
      dy = y - ColorPickerWidget::CY
      dist = Math.sqrt(dx * dx + dy * dy)

      if dist.between?(ColorPickerWidget::INNER_R, ColorPickerWidget::OUTER_R)
        model.with(drag: :ring, hue: hue_from_point(dx, dy))
      elsif in_square?(x, y)
        apply_sv(model.with(drag: :square), x, y)
      else
        model
      end

    in Event::Canvas[type: :move, id: "picker", x:, y:]
      case model.drag
      when :ring
        model.with(hue: hue_from_point(x - ColorPickerWidget::CX, y - ColorPickerWidget::CY))
      when :square
        apply_sv(model, x, y)
      else
        model
      end

    in Event::Canvas[type: :release, id: "picker"]
      model.with(drag: :none)

    else
      model
    end
  end

  def view(model)
    hex = hsv_to_hex(model.hue, model.saturation, model.value)

    window("color_picker", title: "Color Picker") do
      column(padding: 20, spacing: 16, align_x: :center) do
        ColorPickerWidget.render("picker", model.hue, model.saturation, model.value)

        row(spacing: 16, align_y: :center) do
          container("swatch", width: 48, height: 48, background: hex,
            border: {width: 1, color: "#cccccc", rounded: 4})

          column(spacing: 4) do
            text("hex_display", hex, size: 18)
            text("hsv_display", hsv_label(model))
          end
        end
      end
    end
  end

  private

  # -- Hit testing -------------------------------------------------------------

  def in_square?(x, y)
    x.between?(ColorPickerWidget::SQ_ORIGIN, ColorPickerWidget::SQ_ORIGIN + ColorPickerWidget::SQ_SIZE) &&
      y.between?(ColorPickerWidget::SQ_ORIGIN, ColorPickerWidget::SQ_ORIGIN + ColorPickerWidget::SQ_SIZE)
  end

  # -- Coordinate math ---------------------------------------------------------

  def hue_from_point(dx, dy)
    angle = Math.atan2(dy, dx)
    hue = angle + Math::PI / 2
    hue += 2 * Math::PI if hue < 0
    hue * 180.0 / Math::PI
  end

  def apply_sv(model, x, y)
    s = ((x - ColorPickerWidget::SQ_ORIGIN).to_f / ColorPickerWidget::SQ_SIZE).clamp(0.0, 1.0)
    v = (1.0 - (y - ColorPickerWidget::SQ_ORIGIN).to_f / ColorPickerWidget::SQ_SIZE).clamp(0.0, 1.0)
    model.with(saturation: s, value: v)
  end

  # -- Display helpers ---------------------------------------------------------

  def hsv_label(model)
    h_int = model.hue.round
    s_pct = (model.saturation * 100).round
    v_pct = (model.value * 100).round
    "H: #{h_int}  S: #{s_pct}%  V: #{v_pct}%"
  end

  # -- Color conversion --------------------------------------------------------

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
