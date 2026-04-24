# Themes and Styling

Plushie's visual styling works in three layers: **themes** set the
overall palette for a window, **style maps** customise individual
widget instances, and **type modules** (Color, Border, Shadow,
Gradient) provide the shared building blocks. Everything lives
under `Plushie::Type`.

## Color

`Plushie::Type::Color`

Colours appear everywhere visual: theme seeds, style maps, borders,
shadows, gradients, canvas fills, and widget props like `color:`
and `background:`. Any of these input forms is accepted:

| Input | Example | Result |
|---|---|---|
| Named symbol | `:cornflowerblue` | `"#6495ed"` |
| Hex string | `"#3b82f6"` | `"#3b82f6"` |
| Shorthand hex | `"#f00"` | `"#ff0000"` |
| Hex with alpha | `"#3b82f680"` | `"#3b82f680"` |
| Shorthand with alpha | `"#f008"` | `"#ff000088"` |
| Named string | `"cornflowerblue"` | `"#6495ed"` |

`Color.cast(value)` normalises any input to a canonical lowercase
hex string (`"#rrggbb"` or `"#rrggbbaa"`). All type modules that
accept colours run inputs through `cast` automatically. `Color.encode`
is an alias.

### Named colors

Plushie supports every CSS Color Module Level 4 named colour plus
`:transparent`. Named lookups are case-insensitive (both
`:cornflowerblue` and `"CornflowerBlue"` resolve the same). Grey
and gray aliases are interchangeable: `:darkgray` and `:darkgrey`
both return `"#a9a9a9"`.

The full map is exposed as `Plushie::Type::Color::NAMED_COLORS`.

### Constructors

```ruby
Plushie::Type::Color.from_rgb(255, 128, 0)        # => "#ff8000"
Plushie::Type::Color.from_rgba(255, 128, 0, 128)  # => "#ff800080"
Plushie::Type::Color.from_hex("f08")              # => "#ff0088"
Plushie::Type::Color.cast(:red)                   # => "#ff0000"
```

`from_rgb` and `from_rgba` take 0-255 integer channels. Channels
outside the range are clamped. `from_hex` accepts values with or
without a leading `#` and expands short forms (`#rgb`, `#rgba`) by
doubling each digit.

Short hex forms are accepted as input but the wire format is always
`#rrggbb` or `#rrggbbaa`; the SDK normalises before sending.

## Theme

`Plushie::Type::Theme`

Every window has a `theme:` prop that sets the colour palette for
all widgets inside it. Themes control button colours, input field
backgrounds, scrollbar tints, text colours. Every visual aspect
adapts to the active theme.

### Built-in themes

Pass the symbol to the window's `theme:` prop:

```ruby
window("main", title: "App", theme: :dark) do
  # ...
end
```

| Theme | Description |
|---|---|
| `:light`, `:dark` | Default light and dark themes |
| `:dracula` | [Dracula](https://draculatheme.com/) palette |
| `:nord` | [Nord](https://www.nordtheme.com/) palette |
| `:solarized_light`, `:solarized_dark` | [Solarized](https://ethanschoonover.com/solarized/) |
| `:gruvbox_light`, `:gruvbox_dark` | [Gruvbox](https://github.com/morhetz/gruvbox) |
| `:catppuccin_latte`, `:catppuccin_frappe`, `:catppuccin_macchiato`, `:catppuccin_mocha` | [Catppuccin](https://catppuccin.com/) |
| `:tokyo_night`, `:tokyo_night_storm`, `:tokyo_night_light` | [Tokyo Night](https://github.com/enkia/tokyo-night-vscode-theme) |
| `:kanagawa_wave`, `:kanagawa_dragon`, `:kanagawa_lotus` | [Kanagawa](https://github.com/rebelot/kanagawa.nvim) |
| `:moonfly`, `:nightfly` | [moonfly / nightfly](https://github.com/bluz71) |
| `:oxocarbon` | [Oxocarbon](https://github.com/nyoom-engineering/oxocarbon.nvim) |
| `:ferra` | [Ferra](https://github.com/casperstorm/ferra) |

Pass `:system` to follow the operating system's light / dark
preference. The full built-in list is available as
`Plushie::Type::Theme::BUILTIN`.

Unknown symbols raise `ArgumentError` at encode time.

### Custom themes

`Theme.custom(name, base: nil, **overrides)` creates a custom
palette from seed colours:

```ruby
my_theme = Plushie::Type::Theme.custom("My Brand",
  primary: "#3b82f6",
  danger: "#ef4444",
  background: "#1a1a2e",
  text: "#e0e0e8")

window("main", theme: my_theme) do
  # ...
end
```

| Seed key | Purpose |
|---|---|
| `:background` | Page / window background |
| `:text` | Default text colour |
| `:primary` | Primary accent (buttons, links, focus rings) |
| `:success` | Success indicators |
| `:danger` | Error / destructive actions |
| `:warning` | Warning indicators |

Every override value is passed through `Color.cast`, so any colour
input form works (symbols, hex, with or without alpha).

The secondary palette is auto-derived from `:background` and
`:text` by iced's palette generator. To customise it, use shade
overrides (`secondary_base`, `secondary_weak`, `secondary_strong`,
plus `_text` variants) rather than a core seed.

Unknown keys raise `ArgumentError` at construction to catch typos
early. The complete set of valid keys is exposed as
`Plushie::Type::Theme.valid_custom_keys`.

### Extending built-in themes

Provide `base:` to start from an existing theme and override only
the colours you want:

```ruby
Plushie::Type::Theme.custom("Nord+", base: :nord, primary: "#88c0d0")
```

### Shade overrides

For fine-grained control, themes support shade override keys that
target specific levels in the generated palette. The renderer
generates a full shade ramp from each seed; overrides replace
individual shades.

**Colour families** (primary, secondary, success, warning, danger)
each have three base shades and matching text variants:

- `primary_base`, `primary_weak`, `primary_strong`
- `primary_base_text`, `primary_weak_text`, `primary_strong_text`

The same pattern applies to `secondary_*`, `success_*`, `warning_*`,
and `danger_*`.

**Background family** has eight levels with text variants:

- `background_base`, `background_weakest`, `background_weaker`,
  `background_weak`, `background_neutral`, `background_strong`,
  `background_stronger`, `background_strongest`
- Each has a `_text` companion (e.g. `background_base_text`)

Pass shade overrides as additional keyword arguments to `custom`:

```ruby
Plushie::Type::Theme.custom("Custom",
  base: :dark,
  primary: "#3b82f6",
  primary_strong: "#1d4ed8",
  background_weakest: "#0f0f1a")
```

### Runtime theme switching

There is no dedicated "switch theme" command. The active theme is a
property of the view tree. Store the current theme in the model,
read it in `view`, and change it by updating the model; the next
render tree carries the new theme and the renderer applies it.

```ruby
def view(model)
  window("main", theme: model.dark_mode ? :dark : :light) do
    # ...
  end
end

def update(model, event)
  case event
  in Event::Widget[type: :toggle, id: "dark_mode", value: on]
    model.with(dark_mode: on)
  end
end
```

### Subtree theming

The `themer` widget applies a different theme to a subtree without
affecting the rest of the window. It takes exactly one child:

```ruby
themer("sidebar-theme", theme: :dark) do
  container("body", padding: 12) do
    text("info", "This section uses the dark theme")
  end
end
```

`themer` accepts the same values as the window `theme:` prop: a
built-in symbol, `:system`, or a `Theme.custom` result. See
[Built-in Widgets > themer](built-in-widgets.md#themer) for the
widget reference.

## StyleMap

`Plushie::Type::StyleMap`

StyleMap overrides the appearance of individual widget instances.
Themes set the baseline palette; StyleMap customises specific
widgets on top of it.

A style value can be:

- a named preset symbol: `style: :primary`
- a `StyleMap::Spec` struct for custom styling with status overrides
- a plain hash with the same field shape

### Named presets

Pass a preset symbol directly to any style-aware widget:

```ruby
button("save",   "Save",   style: :primary)
button("delete", "Delete", style: :danger)
button("cancel", "Cancel", style: :text)
```

Common presets include `:primary`, `:secondary`, `:success`,
`:danger`, `:warning`, and `:text`. Available presets vary by
widget; see each widget's module for its supported values.

### Spec struct

`StyleMap::Spec` is an immutable `Data` class. Construct one with
keyword arguments and use `#with` to produce modified copies:

```ruby
style = Plushie::Type::StyleMap::Spec.new(
  base: :primary,
  background: "#3b82f6",
  text_color: "#ffffff",
  border: Plushie::Type::Border.from_opts(color: "#2563eb", width: 1),
  shadow: Plushie::Type::Shadow.from_opts(color: "#0000001a", blur_radius: 4),
  hovered: {background: "#2563eb"},
  pressed: {background: "#1d4ed8"},
  disabled: {background: "#9ca3af", text_color: "#6b7280"},
  focused: {border: Plushie::Type::Border.from_opts(color: "#3b82f6", width: 2)})

button("save", "Save", style: style)
```

| Field | Type | Description |
|---|---|---|
| `base` | Symbol or nil | Named preset to inherit from |
| `background` | Color or Gradient or nil | Background fill |
| `text_color` | Color or nil | Text foreground colour |
| `border` | `Border::Spec` or Hash or nil | Border specification |
| `shadow` | `Shadow::Spec` or Hash or nil | Shadow specification |
| `hovered` | Hash or nil | Overrides applied on hover |
| `pressed` | Hash or nil | Overrides applied while pressed |
| `disabled` | Hash or nil | Overrides applied when disabled |
| `focused` | Hash or nil | Overrides applied when focused |

`StyleMap.from_opts(hash)` is a convenience constructor that slices
recognised keys off an options hash and returns a `Spec`.

### Status overrides

Each of `hovered`, `pressed`, `disabled`, and `focused` accepts a
subset of the base fields: `background`, `text_color`, `border`,
`shadow`. Only the properties you specify are overridden; others
inherit from the base style.

```ruby
Plushie::Type::StyleMap::Spec.new(
  base: :primary,
  hovered: {background: "#2563eb"})
```

### Hash shape

A widget's `style:` prop also accepts a plain hash with the same
field names. This is useful for short ad-hoc overrides:

```ruby
button("save", "Save",
  style: {base: :primary, hovered: {background: "#2563eb"}})
```

`StyleMap.encode` dispatches based on type: a `Symbol` becomes the
preset name string, a `Spec` is serialised via `#to_wire` with nil
fields stripped, and a `Hash` is passed through.

## Gradient

`Plushie::Type::Gradient`

Linear gradients for use as background fills. The SDK produces a
coordinate-based wire format matching canvas gradients; two
constructors cover the common shapes:

```ruby
# Coordinate-based: explicit start and end points.
Plushie::Type::Gradient.linear(
  [0, 0], [100, 100],
  [[0.0, "#3b82f6"], [1.0, "#1d4ed8"]])

# Angle-based: converts an angle (degrees) to coordinates on the
# unit square. 90 degrees is bottom-to-top.
Plushie::Type::Gradient.linear_from_angle(
  135, [[0.0, "#667eea"], [1.0, "#764ba2"]])
```

Stops are `[offset, color]` pairs where `offset` is a 0.0-1.0 float
and `color` is any form `Color.cast` accepts (named symbols, hex
strings, shorthand hex). Stop colours are normalised to canonical
hex on construction.

Use a gradient anywhere a background colour is accepted:

```ruby
container("card",
  background: Plushie::Type::Gradient.linear_from_angle(
    135, [[0.0, "#667eea"], [1.0, "#764ba2"]])) do
  text("label", "Gradient card")
end
```

## Border

`Plushie::Type::Border`

Border specifications for containers and style maps.

### Constructors

```ruby
Plushie::Type::Border.new
# => Spec(color: nil, width: 0, radius: 0)

Plushie::Type::Border.from_opts(color: "#e5e7eb", width: 1, rounded: 8)
# => Spec(color: "#e5e7eb", width: 1, radius: 8)
```

| Method | Signature | Description |
|---|---|---|
| `Border.new` | `()` | Default spec (no colour, zero width, zero radius) |
| `Border.from_opts` | `(color:, width:, rounded:, radius:)` | Keyword-built spec |
| `Spec#with` | `(**changes)` | Immutable copy with fields replaced |

`Border::Spec` is a `Data.define`d class with `:color`, `:width`,
and `:radius` fields. Negative widths or radii raise `ArgumentError`
when encoded.

### Per-corner radius

Pass a hash to `radius:` for independent corner radii:

```ruby
Plushie::Type::Border.from_opts(
  width: 1,
  color: "#ccc",
  radius: {top_left: 8, top_right: 8, bottom_right: 0, bottom_left: 0})
```

All four corner keys are optional; missing corners default to the
renderer's value. Both `rounded:` and `radius:` feed the same field;
`rounded:` is sugar for a uniform number, `radius:` allows the hash
shape.

## Shadow

`Plushie::Type::Shadow`

Drop shadow specifications for containers and style maps.

### Constructors

```ruby
Plushie::Type::Shadow.new
# => Spec(color: "#000000", offset_x: 0, offset_y: 0, blur_radius: 0)

Plushie::Type::Shadow.from_opts(
  color: "#00000040", offset_x: 2, offset_y: 2, blur_radius: 6)
```

| Method | Signature | Description |
|---|---|---|
| `Shadow.new` | `()` | Default spec (black, zero offset, zero blur) |
| `Shadow.from_opts` | `(color:, offset:, offset_x:, offset_y:, blur_radius:)` | Keyword-built spec |
| `Spec#with` | `(**changes)` | Immutable copy with fields replaced |

`offset:` accepts a two-element `[x, y]` array and splits to
`offset_x` and `offset_y` internally. The wire format recomposes
them as `offset: [x, y]`.

## Common styling props on widgets

Several widgets accept styling props directly, independent of the
`style:` system. Typical examples:

| Prop | Accepts | Appears on |
|---|---|---|
| `color:` | Color input | `text`, `rich_text`, `container` |
| `background:` | Color or Gradient | `container`, inside `StyleMap` |
| `border:` | `Border::Spec` or Hash | `container` |
| `shadow:` | `Shadow::Spec` or Hash | `container` |
| `style:` | Symbol or `StyleMap::Spec` or Hash | most interactive widgets |

Colour values are normalised through `Color.cast` at encode time, so
you can pass `color: :red`, `color: "#ff0000"`, or `color: "red"`
interchangeably.

## Canonical examples

### Dark-themed app

```ruby
class DarkApp < Plushie::App
  Model = Data.define(:counter) do
    def initialize(counter: 0) = super
  end

  def init(_opts) = Model.new

  def view(model)
    window("main", title: "Dark", theme: :dark) do
      container("body", padding: 24, width: :fill, height: :fill) do
        column(spacing: 12) do
          text("heading", "Welcome", size: 28)
          text("count", "Clicks: #{model.counter}")
          button("tick", "Click me", style: :primary)
        end
      end
    end
  end

  def update(model, event)
    case event
    in Event::Widget[type: :click, id: "tick"]
      model.with(counter: model.counter + 1)
    else
      model
    end
  end
end
```

### Subtree override with themer

```ruby
def view(model)
  window("main", title: "Editor", theme: :light) do
    row(spacing: 0, width: :fill, height: :fill) do
      themer("sidebar-theme", theme: :dark) do
        container("sidebar",
          padding: 16,
          width: 240,
          height: :fill,
          background: "#1a1a2e") do
          column(spacing: 8) do
            text("title", "Files", color: "#e0e0e8", size: 18)
            button("new-file", "New",  style: :primary)
            button("open",     "Open", style: :secondary)
          end
        end
      end

      container("content", padding: 24, width: :fill, height: :fill) do
        text("body", "Main content uses the light theme.")
      end
    end
  end
end
```

The `themer` widget only affects its descendants; the sibling
`content` container keeps the window's light theme.

## Encoding

All styling types serialise to wire-compatible hashes when widgets
are built. `Color.cast` runs on every colour input, `Border::Spec`
and `Shadow::Spec` each expose `#to_wire`, and `StyleMap::Spec#to_wire`
recursively encodes its border, shadow, and status-override fields.
You work with Ruby symbols, hex strings, and `Data` structs in view
code; encoding happens at the boundary.

## See also

- [Built-in Widgets reference](built-in-widgets.md) - which widgets
  accept `style:`, `background:`, `border:`, and `shadow:`
- [Windows and Layout reference](windows-and-layout.md) - window
  `theme:` prop, alignment, and sizing
- [Animation reference](animation.md) - transitioning colour and
  size props over time
- [Composition Patterns reference](composition-patterns.md) - theme
  toggles, design tokens, and shared style helpers
