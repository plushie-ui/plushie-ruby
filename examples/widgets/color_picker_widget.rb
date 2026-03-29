# frozen_string_literal: true

require "plushie"

# Canvas-based HSV color picker widget.
#
# A hue ring surrounds a saturation/value square. Drag the ring to
# select a hue; drag the square to adjust saturation and value.
# Keyboard accessible: Tab to focus cursors, arrow keys to adjust.
#
#   ColorPickerWidget.new("picker")
#
# Events:
# - :change with {"hue" => h, "saturation" => s, "value" => v}
module ColorPickerWidget
  include Plushie::CanvasWidget
  extend self

  canvas_widget :color_picker_widget

  # -- Geometry constants ----------------------------------------------------

  CANVAS_SIZE = 400
  CX = CANVAS_SIZE / 2
  CY = CANVAS_SIZE / 2
  OUTER_R = 190
  INNER_R = 150
  MID_R = (INNER_R + OUTER_R) / 2
  SQ_ORIGIN = 100
  SQ_SIZE = 200
  SEGMENTS = 72
  CURSOR_R = 7

  FINE_STEP = 1
  COARSE_STEP = 15
  SV_FINE_STEP = 0.01
  SV_COARSE_STEP = 0.1

  def init
    {hue: 0.0, saturation: 1.0, value: 1.0, drag: :none}
  end

  # -- Event transformation --------------------------------------------------

  def handle_event(event, state)
    case event
    in Event::Widget[type: :canvas_press, data: {x:, y:, button: :left}]
      dx = x - CX
      dy = y - CY
      dist = Math.sqrt(dx * dx + dy * dy)

      if dist.between?(INNER_R, OUTER_R)
        new_state = state.merge(drag: :ring, hue: hue_from_point(dx, dy))
        [:emit, :change, hsv_data(new_state), new_state]
      elsif in_square?(x, y)
        new_state = apply_sv(state.merge(drag: :square), x, y)
        [:emit, :change, hsv_data(new_state), new_state]
      else
        [:consumed, state]
      end

    in Event::Widget[type: :canvas_move, data: {x:, y:}]
      case state[:drag]
      when :ring
        new_state = state.merge(hue: hue_from_point(x - CX, y - CY))
        [:emit, :change, hsv_data(new_state), new_state]
      when :square
        new_state = apply_sv(state, x, y)
        [:emit, :change, hsv_data(new_state), new_state]
      else
        [:consumed, state]
      end

    in Event::Widget[type: :canvas_release]
      [:update_state, state.merge(drag: :none)]

    in Event::Widget[type: :canvas_element_key_press, data:]
      element_id = data && data["element_id"]
      key = data && data["key"]
      mods = (data && data["modifiers"]) || {}
      handle_key(element_id, key, mods, state)

    else
      [:consumed, state]
    end
  end

  # -- Rendering -------------------------------------------------------------

  def render(id, _props, state)
    include Plushie::UI

    hue = state[:hue]
    saturation = state[:saturation]
    value = state[:value]

    canvas(id,
      width: CANVAS_SIZE, height: CANVAS_SIZE,
      on_press: true, on_release: true, on_move: true,
      arrow_mode: "none",
      alt: "HSV color picker",
      description: "Drag the ring to select a hue, drag the square to adjust saturation and value. Tab to focus cursors, use arrow keys to adjust.") do
      layer("a_ring") do
        ring_shapes
      end

      layer("b_sv_hue") do
        sv_hue_shapes(hue)
      end

      layer("c_sv_dark") do
        sv_dark_shapes
      end

      layer("d_cursors") do
        cursor_groups(hue, saturation, value)
      end
    end
  end

  # -- Keyboard --------------------------------------------------------------

  def handle_key(element_id, key, mods, state)
    case element_id
    when "hue-cursor"
      handle_hue_key(key, mods, state)
    when "sv-cursor"
      handle_sv_key(key, mods, state)
    else
      [:consumed, state]
    end
  end

  def handle_hue_key(key, mods, state)
    shift = mods["shift"] || false
    step = shift ? COARSE_STEP : FINE_STEP

    new_hue =
      case key
      when "ArrowRight", "ArrowUp" then fmod(state[:hue] + step, 360.0)
      when "ArrowLeft", "ArrowDown" then fmod(state[:hue] - step + 360.0, 360.0)
      when "PageUp" then fmod(state[:hue] + COARSE_STEP, 360.0)
      when "PageDown" then fmod(state[:hue] - COARSE_STEP + 360.0, 360.0)
      when "Home" then 0.0
      when "End" then 359.0
      else state[:hue]
      end

    if new_hue != state[:hue]
      new_state = state.merge(hue: new_hue)
      [:emit, :change, hsv_data(new_state), new_state]
    else
      [:consumed, state]
    end
  end

  def handle_sv_key(key, mods, state)
    shift = mods["shift"] || false
    step = shift ? SV_COARSE_STEP : SV_FINE_STEP

    new_s = state[:saturation]
    new_v = state[:value]

    case key
    when "ArrowRight" then new_s = clamp(new_s + step, 0.0, 1.0)
    when "ArrowLeft" then new_s = clamp(new_s - step, 0.0, 1.0)
    when "ArrowUp" then new_v = clamp(new_v + step, 0.0, 1.0)
    when "ArrowDown" then new_v = clamp(new_v - step, 0.0, 1.0)
    when "PageUp"
      if shift
        new_s = clamp(new_s + SV_COARSE_STEP, 0.0, 1.0)
      else
        new_v = clamp(new_v + SV_COARSE_STEP, 0.0, 1.0)
      end
    when "PageDown"
      if shift
        new_s = clamp(new_s - SV_COARSE_STEP, 0.0, 1.0)
      else
        new_v = clamp(new_v - SV_COARSE_STEP, 0.0, 1.0)
      end
    when "Home"
      shift ? new_s = 0.0 : new_v = 1.0
    when "End"
      shift ? new_s = 1.0 : new_v = 0.0
    end

    if new_s != state[:saturation] || new_v != state[:value]
      new_state = state.merge(saturation: new_s, value: new_v)
      [:emit, :change, hsv_data(new_state), new_state]
    else
      [:consumed, state]
    end
  end

  # -- Cursors ---------------------------------------------------------------

  def cursor_groups(hue, saturation, value)
    angle = (hue - 90) * Math::PI / 180
    ring_x = CX + MID_R * Math.cos(angle)
    ring_y = CY + MID_R * Math.sin(angle)

    sv_x = SQ_ORIGIN + saturation * SQ_SIZE
    sv_y = SQ_ORIGIN + (1.0 - value) * SQ_SIZE

    cursor_stroke = Plushie::Canvas::Shape.stroke("#333333", 2)
    focus_stroke = {stroke: {color: "#3b82f6", width: 3}}

    canvas_group("hue-cursor",
      x: ring_x, y: ring_y,
      focusable: true,
      on_click: true,
      focus_style: focus_stroke,
      show_focus_ring: false,
      a11y: {
        role: :slider,
        label: "Hue",
        value: "#{hue.round} degrees",
        orientation: :horizontal
      }) do
      canvas_circle(0, 0, CURSOR_R, fill: "#ffffff", stroke: cursor_stroke)
    end

    canvas_group("sv-cursor",
      x: sv_x, y: sv_y,
      focusable: true,
      on_click: true,
      focus_style: focus_stroke,
      show_focus_ring: false,
      a11y: {
        role: :slider,
        label: "Saturation and brightness",
        value: "#{(saturation * 100).round}% saturation, #{(value * 100).round}% brightness",
        orientation: :horizontal
      }) do
      canvas_circle(0, 0, CURSOR_R, fill: "#ffffff", stroke: cursor_stroke)
    end
  end

  # -- Ring layer ------------------------------------------------------------

  def ring_shapes
    deg_per_segment = 360.0 / SEGMENTS

    SEGMENTS.times do |i|
      hue_deg = i * deg_per_segment
      a1 = (hue_deg - 90) * Math::PI / 180
      a2 = (hue_deg + deg_per_segment - 90) * Math::PI / 180

      canvas_path([
        Plushie::Canvas::Shape.move_to(CX + INNER_R * Math.cos(a1), CY + INNER_R * Math.sin(a1)),
        Plushie::Canvas::Shape.line_to(CX + OUTER_R * Math.cos(a1), CY + OUTER_R * Math.sin(a1)),
        Plushie::Canvas::Shape.line_to(CX + OUTER_R * Math.cos(a2), CY + OUTER_R * Math.sin(a2)),
        Plushie::Canvas::Shape.line_to(CX + INNER_R * Math.cos(a2), CY + INNER_R * Math.sin(a2)),
        Plushie::Canvas::Shape.close
      ], fill: hsv_to_hex(hue_deg, 1.0, 1.0))
    end
  end

  # -- SV layers -------------------------------------------------------------

  def sv_hue_shapes(hue)
    hue_color = hsv_to_hex(hue, 1.0, 1.0)

    canvas_rect(SQ_ORIGIN, SQ_ORIGIN, SQ_SIZE, SQ_SIZE,
      fill: Plushie::Canvas::Shape.linear_gradient(
        [SQ_ORIGIN, SQ_ORIGIN],
        [SQ_ORIGIN + SQ_SIZE, SQ_ORIGIN],
        [[0.0, "#ffffff"], [1.0, hue_color]]
      ))
  end

  def sv_dark_shapes
    canvas_rect(SQ_ORIGIN, SQ_ORIGIN, SQ_SIZE, SQ_SIZE,
      fill: Plushie::Canvas::Shape.linear_gradient(
        [SQ_ORIGIN, SQ_ORIGIN],
        [SQ_ORIGIN, SQ_ORIGIN + SQ_SIZE],
        [[0.0, "#00000000"], [1.0, "#000000ff"]]
      ))
  end

  # -- Hit testing -----------------------------------------------------------

  def in_square?(x, y)
    x.between?(SQ_ORIGIN, SQ_ORIGIN + SQ_SIZE) &&
      y.between?(SQ_ORIGIN, SQ_ORIGIN + SQ_SIZE)
  end

  # -- Coordinate math -------------------------------------------------------

  def hue_from_point(dx, dy)
    angle = Math.atan2(dy, dx)
    hue = angle + Math::PI / 2
    hue += 2 * Math::PI if hue < 0
    hue * 180.0 / Math::PI
  end

  def apply_sv(state, x, y)
    s = clamp((x - SQ_ORIGIN).to_f / SQ_SIZE, 0.0, 1.0)
    v = clamp(1.0 - (y - SQ_ORIGIN).to_f / SQ_SIZE, 0.0, 1.0)
    state.merge(saturation: s, value: v)
  end

  def clamp(val, lo, hi)
    val.clamp(lo, hi)
  end

  def hsv_data(state)
    {hue: state[:hue], saturation: state[:saturation], value: state[:value]}
  end

  # -- Color conversion ------------------------------------------------------

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

  # -- Public builder --------------------------------------------------------

  def self.new(id, **props)
    Plushie::CanvasWidget.build(ColorPickerWidget, id, props)
  end
end
