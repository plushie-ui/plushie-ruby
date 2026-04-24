# Styling

With the layout in place, it is time to make the pad look good.
Plushie has a layered styling system: **themes** set the overall
palette for a window, **style presets** and **StyleMap** override
individual widget instances, and the type modules under
`Plushie::Type` (Color, Font, Border, Shadow, Gradient) handle
the details.

This chapter covers the parts you will use most often. The full
theme list, shade override keys, and every type option are in the
[Themes and Styling reference](../reference/themes-and-styling.md).

## Themes

Every window has a `theme:` prop that sets the colour palette for
all widgets inside it. The pad's `view` opens with this line:

```ruby
window("main", title: "Plushie Pad", theme: :dark) do
  # ...
end
```

That one prop is why the editor, sidebar, preview pane, toolbar,
and event log all appear with dark backgrounds and light text.
Plushie ships with a healthy collection of built-in themes. Pass
any of them as a symbol:

| Theme | Description |
|---|---|
| `:light`, `:dark` | Default light and dark themes |
| `:dracula` | Dracula palette |
| `:nord` | Nord palette |
| `:solarized_light`, `:solarized_dark` | Solarized |
| `:gruvbox_light`, `:gruvbox_dark` | Gruvbox |
| `:catppuccin_latte`, `:catppuccin_frappe`, `:catppuccin_macchiato`, `:catppuccin_mocha` | Catppuccin |
| `:tokyo_night`, `:tokyo_night_storm`, `:tokyo_night_light` | Tokyo Night |
| `:kanagawa_wave`, `:kanagawa_dragon`, `:kanagawa_lotus` | Kanagawa |
| `:moonfly`, `:nightfly` | moonfly / nightfly |
| `:oxocarbon` | Oxocarbon |
| `:ferra` | Ferra |

The complete list is exposed as `Plushie::Type::Theme::BUILTIN`.
Unknown symbols raise `ArgumentError` at encode time, so typos
surface loudly.

Use `:system` to follow the operating system's light / dark
preference:

```ruby
window("main", title: "Plushie Pad", theme: :system) do
  # ...
end
```

Swap the pad's `theme: :dark` for any of the built-ins and restart
to see how dramatically the UI adapts. Buttons, text inputs,
scrollbars, and the editor all respond.

## Runtime theme switching

There is no dedicated "switch theme" command. The active theme is
part of the view tree, so switching is just a model update:

```ruby
def view(model)
  window("main", title: "Plushie Pad", theme: model.theme) do
    # ...
  end
end

def update(model, event)
  case event
  in Event::Widget[type: :click, id: "cycle-theme"]
    next_theme = (model.theme == :dark) ? :light : :dark
    model.with(theme: next_theme)
  end
end
```

The next render tree carries the new theme and the renderer
applies it. Model-driven UI, all the way down.

## Custom themes

`Plushie::Type::Theme.custom` builds a palette from a handful of
seed colours. The signature is
`custom(name, base: nil, **overrides)`:

```ruby
brand = Plushie::Type::Theme.custom("My Brand",
  primary: "#3b82f6",
  danger: "#ef4444",
  background: "#1a1a2e",
  text: "#e0e0e8")

window("main", theme: brand) do
  # ...
end
```

The core seeds are `:background`, `:text`, `:primary`, `:success`,
`:danger`, and `:warning`. Every override runs through
`Color.cast`, so any colour input form works (named symbols, hex,
with or without alpha).

Pass `base:` to start from an existing theme and override only the
colours you want:

```ruby
Plushie::Type::Theme.custom("Nord+", base: :nord, primary: "#88c0d0")
```

For fine-grained control, the theme system supports shade
overrides (keys like `primary_strong`, `background_weakest`,
`danger_base_text`) that target specific levels in the generated
palette. See the
[Themes and Styling reference](../reference/themes-and-styling.md)
for the full key list. Unknown keys raise `ArgumentError` at
construction, which catches typos at the source.

## Subtree theming with `themer`

The `themer` widget applies a different theme to a subtree without
affecting the rest of the window. It takes a single child:

```ruby
window("main", title: "Notes", theme: :light) do
  row do
    themer("sidebar-theme", theme: :dark) do
      container("sidebar", padding: 12, width: 240) do
        column(spacing: 8) do
          text("title", "Files", size: 18)
          button("new-file", "New", style: :primary)
        end
      end
    end

    container("body", padding: 24) do
      text("content", "Main area stays light themed.")
    end
  end
end
```

`themer` accepts the same values as the window `theme:` prop: a
built-in symbol, `:system`, or a `Theme.custom` result. Useful for
a dark sidebar in a light app, brand-specific sections, or giving
the pad's preview pane a distinct palette so experiments stand
out visually.

## Colors

`Plushie::Type::Color` normalises every colour input the SDK
accepts. Symbol names, hex strings, RGB constructors - all feed
through the same `cast` pipeline and emerge as canonical lowercase
hex:

```ruby
Plushie::Type::Color.cast(:cornflowerblue)         # => "#6495ed"
Plushie::Type::Color.cast("#ff8800")               # => "#ff8800"
Plushie::Type::Color.cast("#f80")                  # => "#ff8800"
Plushie::Type::Color.cast("#3b82f680")             # => "#3b82f680"
Plushie::Type::Color.from_rgb(255, 128, 0)         # => "#ff8000"
Plushie::Type::Color.from_rgba(255, 128, 0, 128)   # => "#ff800080"
```

Any prop that accepts a colour (widget `color:`, `background:`,
theme seeds, border colour, shadow colour, style map fields) runs
the input through `cast` automatically. Pass `:red`, `"#ff0000"`,
or `"red"` interchangeably and stop worrying about the difference.

Plushie supports every CSS Color Module Level 4 named colour, plus
`:transparent`. Named lookups are case-insensitive; grey and gray
aliases resolve to the same value.

## Style presets

The simplest way to restyle a widget is to pass a preset symbol to
its `style:` prop. The pad already uses three of them in the
sidebar's per-file row:

```ruby
def file_row(model, file)
  select_style = (model.active_file == file) ? :primary : :secondary
  container(file, padding: 4) do
    row("row", spacing: 4) do
      button("select", file, style: select_style)
      button("delete", "x", style: :danger)
    end
  end
end
```

`:primary` highlights the active file, `:secondary` quiets the
inactive ones, and `:danger` marks the delete button as
destructive. The preset names map to the renderer's built-in style
functions, so they automatically reflect whichever theme is
active. Common presets:

- `:primary`
- `:secondary`
- `:success`
- `:warning`
- `:danger`
- `:text`

Available presets vary by widget. Buttons support the full list;
text and container accept a smaller set. Check each widget's
module for its supported values, or pass an unknown preset and
read the runtime error.

The pad's save button uses the default style. Promote it to
primary so it stands out from the auto-save checkbox and new-name
input:

```ruby
def toolbar(model)
  row("toolbar", padding: [8, 4], spacing: 8) do
    button("save", "Save", style: :primary)
    checkbox("auto-save", model.auto_save, label: "Auto-save")
    text_input("new-name", model.new_name,
      placeholder: "new_name.rb",
      on_submit: true)
  end
end
```

## StyleMap: custom styling

When the built-in presets are not enough, `Plushie::Type::StyleMap`
builds per-widget custom styles with hover, press, disabled, and
focus overrides. A `StyleMap::Spec` is an immutable `Data` class;
construct one with keyword args and pass it as `style:`:

```ruby
save_style = Plushie::Type::StyleMap::Spec.new(
  base: :primary,
  background: "#3b82f6",
  text_color: "#ffffff",
  hovered: {background: "#2563eb"},
  pressed: {background: "#1d4ed8"})

button("save", "Save", style: save_style)
```

The `base:` field inherits from a named preset; every other field
layers on top. `StyleMap.from_opts(hash)` is a convenience
constructor that slices recognised keys off an options hash and
returns a `Spec`.

### Fields

| Field | Type | Description |
|---|---|---|
| `base` | Symbol or nil | Named preset to inherit from |
| `background` | Color or Gradient or nil | Background fill |
| `text_color` | Color or nil | Text foreground colour |
| `border` | `Border::Spec` or Hash or nil | Border spec |
| `shadow` | `Shadow::Spec` or Hash or nil | Shadow spec |
| `hovered` | Hash or nil | Overrides on hover |
| `pressed` | Hash or nil | Overrides while pressed |
| `disabled` | Hash or nil | Overrides when disabled |
| `focused` | Hash or nil | Overrides when focused |

Each of the four status fields accepts a subset of the base fields
(`background`, `text_color`, `border`, `shadow`). Only the
properties you specify are overridden; the rest inherit from the
base.

### Hash shape

A widget's `style:` prop also accepts a plain hash with the same
field names. This is useful for short ad-hoc overrides without
constructing a `Spec`:

```ruby
button("save", "Save",
  style: {base: :primary, hovered: {background: "#2563eb"}})
```

`StyleMap.encode` dispatches on type: a `Symbol` becomes a preset
name, a `Spec` serialises via `#to_wire` with nil fields stripped,
and a `Hash` passes through. Everything ends up as a wire-ready
map before it leaves the SDK.

## Borders

`Plushie::Type::Border` builds border specs for containers and
style maps. The pad's sidebar already uses one for the 1px divider
between the file list and the editor:

```ruby
def sidebar(model)
  container("sidebar-wrap",
    width: 200,
    height: :fill,
    border: Plushie::Type::Border.from_opts(color: "#333333", width: 1)) do
    # ...
  end
end
```

Always use `Border.from_opts(...)` or `Border.new` when building a
spec from Ruby. The keyword form accepts `:color`, `:width`,
`:rounded` (uniform radius), and `:radius` (uniform number or
per-corner hash):

```ruby
# Rounded card border
Plushie::Type::Border.from_opts(color: "#e5e7eb", width: 1, rounded: 8)

# Per-corner radius: rounded top, square bottom
Plushie::Type::Border.from_opts(
  color: "#ccc",
  width: 1,
  radius: {top_left: 8, top_right: 8, bottom_right: 0, bottom_left: 0})
```

The corner hash keys are `:top_left`, `:top_right`,
`:bottom_right`, `:bottom_left`. Missing corners fall back to the
renderer default. Negative widths or radii raise `ArgumentError`
when the spec is encoded.

Containers also accept a block form for borders, which reads
naturally when the border is part of a longer container body:

```ruby
container("card") do
  border do
    color "#e5e7eb"
    width 1
    rounded 8
  end
  padding 16
  text("content", "Card content")
end
```

## Shadows

`Plushie::Type::Shadow` works the same way. Build a spec with
`Shadow.from_opts` and pass it to a container's `shadow:` prop or
a `StyleMap`'s `shadow:` field:

```ruby
card_shadow = Plushie::Type::Shadow.from_opts(
  color: "#00000040",
  offset_x: 0,
  offset_y: 2,
  blur_radius: 6)

container("card",
  padding: 16,
  border: Plushie::Type::Border.from_opts(color: "#e5e7eb", width: 1, rounded: 8),
  shadow: card_shadow) do
  text("content", "Elevated card")
end
```

`offset:` accepts a two-element `[x, y]` array and splits to
`offset_x` and `offset_y` internally; use whichever form reads
better. The block DSL equivalent is the mirror image of the border
example above:

```ruby
container("card") do
  shadow do
    color "#00000022"
    offset_y 2
    blur_radius 4
  end
  padding 16
end
```

## Gradients

`Plushie::Type::Gradient` builds linear gradients for use as
backgrounds. Two constructors cover the common shapes:

```ruby
# Coordinate-based: explicit start and end points on the unit square.
Plushie::Type::Gradient.linear(
  [0, 0], [1, 1],
  [[0.0, "#3b82f6"], [1.0, "#1d4ed8"]])

# Angle-based: angle in degrees, 90 is bottom-to-top.
Plushie::Type::Gradient.linear_from_angle(
  135, [[0.0, "#667eea"], [1.0, "#764ba2"]])
```

Stops are `[offset, color]` pairs where `offset` is a 0.0 to 1.0
float and `color` is any form `Color.cast` accepts. Pass a
gradient anywhere a background colour is accepted:

```ruby
container("toolbar-wrap",
  padding: 0,
  background: Plushie::Type::Gradient.linear_from_angle(
    90, [[0.0, "#1e293b"], [1.0, "#0f172a"]])) do
  toolbar(model)
end
```

The pad's toolbar becomes a subtle vertical gradient. The effect
is small, but it gives the bottom of the window a grounded feel.

## Fonts

`Plushie::Type::Font` accepts three forms:

- `:default` - the system default proportional font
- `:monospace` - the system monospace font
- `"Family Name"` - a specific font family by name

The pad uses `:monospace` on the editor and on each event-log
line, which is why both read as code:

```ruby
text_editor("editor", model.source,
  width: [:fill_portion, 2],
  height: :fill,
  highlight_syntax: "ruby",
  font: :monospace)
```

For detailed font control (weight, style, stretch), build a spec
with `Font.from_opts`:

```ruby
Plushie::Type::Font.from_opts(family: "Inter", weight: :bold, style: :italic)
```

App-level font defaults are set via the `App#settings` method.
Fonts declared on `settings` are loaded at startup and available
by family name in any widget's `font:` prop:

```ruby
class PlushiePad::App
  include Plushie::App

  def settings
    {
      default_text_size: 14,
      default_font: "Inter",
      fonts: ["/path/to/Inter-Regular.ttf"]
    }
  end
end
```

## Design tokens

Plushie does not ship a design system framework. Ruby's module
system is enough: define a module of helper methods that return
consistent values and include it where you need them. This pattern
scales well as the pad grows:

```ruby
module PlushiePad::Design
  module_function

  SPACING = {xs: 4, sm: 8, md: 12, lg: 16, xl: 24}.freeze
  FONT_SIZES = {sm: 12, md: 14, lg: 18, xl: 24}.freeze

  def spacing(size) = SPACING.fetch(size)
  def font_size(size) = FONT_SIZES.fetch(size)

  def card_border
    Plushie::Type::Border.from_opts(color: "#e5e7eb", width: 1, rounded: 8)
  end

  def card_shadow
    Plushie::Type::Shadow.from_opts(color: "#00000022", offset_y: 2, blur_radius: 4)
  end
end
```

Then use the helpers in your views:

```ruby
include PlushiePad::Design

column(spacing: spacing(:md), padding: spacing(:lg)) do
  text("title", "Experiments", size: font_size(:lg))
  # ...
end
```

This is plain Ruby, no Plushie magic. But it prevents the gradual
drift toward inconsistent values that creeps into any growing UI
codebase.

## Applying it: the styled pad

The pad already has `theme: :dark` on its window and preset styles
on the sidebar buttons. Fold in a primary save button, a toolbar
gradient, and a red tint on the error text for a cohesive look:

```ruby
def view(model)
  window("main", title: "Plushie Pad", theme: :dark) do
    column("root", width: :fill, height: :fill) do
      row("main-row", width: :fill, height: :fill) do
        sidebar(model)
        editor_pane(model)
        preview_pane(model)
      end
      toolbar_bar(model)
      event_log_pane(model)
    end
  end
end

def toolbar_bar(model)
  container("toolbar-wrap",
    padding: 0,
    background: Plushie::Type::Gradient.linear_from_angle(
      90, [[0.0, "#1e293b"], [1.0, "#0f172a"]])) do
    row("toolbar", padding: [8, 4], spacing: 8) do
      button("save", "Save", style: :primary)
      checkbox("auto-save", model.auto_save, label: "Auto-save")
      text_input("new-name", model.new_name,
        placeholder: "new_name.rb",
        on_submit: true)
    end
  end
end

def preview_pane(model)
  container("preview",
    width: [:fill_portion, 2],
    height: :fill,
    padding: 16) do
    if model.error
      text("error", model.error, color: "#ef4444", size: 14)
    elsif model.preview
      Plushie::UI::Context.current&.push(model.preview) || model.preview
    else
      text("placeholder", "Press Save to compile")
    end
  end
end
```

The dark theme transforms the entire pad. The primary save button
stands out against the toolbar gradient. The sidebar border
creates visual separation. Error text uses an explicit red for
contrast. Small adjustments, dramatic result.

## Verify it

Styling is visual, but a regression test still has value: it
confirms the theme, borders, and style changes did not break the
compile-and-preview flow.

```ruby
class StyledPadTest < Plushie::Test::Case
  def test_styled_pad_compiles_and_previews
    click("#save")
    assert_text("#preview/greeting", "Hello, Plushie!")
    assert_not_exists("#error")
  end
end
```

## Try it

Write a styling experiment in your pad:

- Build a card: container with a border, shadow, rounded corners,
  and padding.
- Try a `StyleMap` with status overrides: a button that changes
  background on hover and press.
- Swap the toolbar's solid dark for the gradient above. Adjust the
  angle and the stop colours.
- Apply different themes to nested `themer` widgets to see how
  palettes compose.
- Build a design token module for your experiments with a spacing
  scale, a palette, and reusable styles.

## See also

- [Themes and Styling reference](../reference/themes-and-styling.md),
  the full theme list, every shade override key, and the complete
  type module surface
- [Built-in Widgets reference](../reference/built-in-widgets.md),
  which widgets accept `style:`, `background:`, `border:`, and
  `shadow:`
- [Windows and Layout reference](../reference/windows-and-layout.md),
  the window `theme:` prop and sizing
- [Composition Patterns reference](../reference/composition-patterns.md),
  theme toggles, design tokens, and shared style helpers

## Next chapter

[Animation and Transitions](09-animation.md)
