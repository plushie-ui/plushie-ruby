# Theming

Plushie exposes iced's theming system directly. No additional abstraction
layer, no token system, no design system framework. If you need those,
build them in your app.

## Setting a theme

Themes are set at the window level:

```ruby
def view(model)
  window("main", title: "My App") do
    themer("theme", theme: :catppuccin_mocha) do
      column do
        text("Themed content")
      end
    end
  end
end
```

## Built-in themes

Iced 0.14 ships with 22 built-in themes. Plushie passes the theme name
string directly to the renderer, which resolves it to an iced `Theme`
variant.

All 22 built-in themes:

| Name | Description |
|---|---|
| `light` | Default light theme |
| `dark` | Default dark theme |
| `dracula` | Dracula color scheme |
| `nord` | Nord color scheme |
| `solarized_light` | Solarized Light |
| `solarized_dark` | Solarized Dark |
| `gruvbox_light` | Gruvbox Light |
| `gruvbox_dark` | Gruvbox Dark |
| `catppuccin_latte` | Catppuccin Latte (light) |
| `catppuccin_frappe` | Catppuccin Frappe |
| `catppuccin_macchiato` | Catppuccin Macchiato |
| `catppuccin_mocha` | Catppuccin Mocha (dark) |
| `tokyo_night` | Tokyo Night |
| `tokyo_night_storm` | Tokyo Night Storm |
| `tokyo_night_light` | Tokyo Night Light |
| `kanagawa_wave` | Kanagawa Wave |
| `kanagawa_dragon` | Kanagawa Dragon |
| `kanagawa_lotus` | Kanagawa Lotus |
| `moonfly` | Moonfly |
| `nightfly` | Nightfly |
| `oxocarbon` | Oxocarbon |
| `ferra` | Ferra |

Unknown names fall back to `dark`.

## Custom themes

Custom themes are defined by providing a palette:

```ruby
theme = Plushie::Type::Theme.custom("my_app",
  background: "#1e1e2e",
  text: "#cdd6f4",
  primary: "#89b4fa",
  success: "#a6e3a1",
  danger: "#f38ba8",
  warning: "#f9e2af"
)
```

Then pass it to a `themer` widget:

```ruby
themer("app_theme", theme: theme) do
  # ...
end
```

The palette is passed to iced's `Theme::custom()` with Oklch-based
palette generation (plushie-iced). Only the colors you specify are overridden;
the rest are derived automatically.

## Extended palette shade overrides

When you set a custom theme, iced generates an "extended palette" of shade
variants from your six core colors. If the auto-generated shades don't
match your design, you can override individual shades by adding flat keys
to the theme hash:

### Key naming convention

For the five color families (primary, secondary, success, warning, danger),
each has three shade levels:

| Key | What it controls |
|-----|------------------|
| `{family}_base` | Base shade background |
| `{family}_weak` | Weak shade background |
| `{family}_strong` | Strong shade background |
| `{family}_base_text` | Text color on the base shade |
| `{family}_weak_text` | Text color on the weak shade |
| `{family}_strong_text` | Text color on the strong shade |

The background family has eight levels: `background_base`,
`background_weakest`, `background_weaker`, `background_weak`,
`background_neutral`, `background_strong`, `background_stronger`,
`background_strongest`. Each also supports a `_text` suffix.

### Example

```ruby
theme = Plushie::Type::Theme.custom("branded",
  background: "#1a1a2e",
  text: "#e0e0e0",
  primary: "#0f3460",
  primary_strong: "#1a5276",
  primary_strong_text: "#ffffff",
  background_weakest: "#0d0d1a"
)
```

Shade overrides only apply to custom themes (hash values). Built-in theme
symbols like `:dark` or `:nord` are not affected.

## Per-subtree theme override

Themes can be overridden for a subtree using a `themer` wrapper:

```ruby
column do
  text("Uses window theme")
  themer("sidebar_theme", theme: :nord) do
    container("sidebar") do
      text("Uses Nord theme")
    end
  end
end
```

This is useful for panels, modals, or sections that need a different
visual treatment.

## Widget-level styling

Individual widgets accept a `style` prop. This can be a named preset symbol
or a `Plushie::Type::StyleMap` for per-instance visual customization.

### Named presets

```ruby
button("save", "Save", style: :primary)
button("cancel", "Cancel", style: :secondary)
button("delete", "Delete", style: :danger)
```

Style symbols (`:primary`, `:secondary`, `:danger`, etc.) map to iced's
built-in style functions. Available presets vary by widget.

### Style maps

Style maps let you fully customize widget appearance from Ruby without
writing Rust. They work on all styleable widgets: button, container,
text_input, text_editor, checkbox, radio, toggler, pick_list, progress_bar,
rule, slider, vertical_slider, and tooltip.

```ruby
card_style = Plushie::Type::StyleMap.new
  .background("#ffffff")
  .text_color("#1a1a1a")
  .border(
    Plushie::Type::Border.new
      .rounded(8)
      .width(1)
      .color("#e0e0e0")
  )
  .shadow(
    Plushie::Type::Shadow.new
      .color("#00000020")
      .offset(0, 2)
      .blur_radius(8)
  )

container("card", style: card_style) do
  text("Card content")
end
```

### Style map fields

- `background` -- hex color for the widget background
- `text_color` -- hex color for text
- `border` -- a `Plushie::Type::Border` (color, width, radius)
- `shadow` -- a `Plushie::Type::Shadow` (color, offset, blur_radius)

### Status overrides

Style maps support interaction state overrides:

```ruby
nav_item_style = Plushie::Type::StyleMap.new
  .background("#00000000")
  .text_color("#cccccc")
  .hovered(background: "#333333", text_color: "#ffffff")
  .pressed(background: "#222222")
  .disabled(text_color: "#666666")
```

Supported statuses: `hovered`, `pressed`, `disabled`, `focused`.

If you don't specify an override for a status, the renderer auto-derives:

- **hovered**: darkens background by 10%
- **pressed**: uses the base style (matching iced's own pattern)
- **disabled**: applies 50% alpha to background and text_color

### Presets and style maps together

Style maps don't replace presets -- they complement them:

```ruby
# Standard danger button
button("delete", "Delete", style: :danger)

# Custom branded button
button("cta", "Get Started", style:
  Plushie::Type::StyleMap.new
    .background("#7c3aed")
    .text_color("#ffffff")
    .border(Plushie::Type::Border.new.rounded(24))
)
```

## System theme detection

The simplest way to follow the OS light/dark preference is to set the
window theme to `:system`:

```ruby
window("main", title: "My App") do
  themer("sys_theme", theme: :system) do
    # content
  end
end
```

The renderer tracks the current OS mode and applies Light or Dark
automatically. This also works in `settings` for the app-level default:

```ruby
def settings = {theme: :system}
```

For manual control, subscribe to theme change events:

```ruby
def subscribe(_model)
  [Subscription.on_theme_change(:theme_changed)]
end

# ...
in Event::System[type: :theme_changed, data:]
  model.with(preferred_theme: data)
```

**Note:** The `themer` widget (per-subtree theme override) does not support
`:system` as a theme value. Use `:system` on window nodes or in `settings`
instead.

## Density

For apps that need density-aware spacing, build a simple helper method:

```ruby
def spacing(density, size)
  case [density, size]
  in [:compact, :md]      then 4
  in [:comfortable, :md]  then 8
  in [:roomy, :md]        then 12
  end
end

column(spacing: spacing(:compact, :md)) do
  # ...
end
```

There is no global density setting or built-in density module -- your app
decides how to handle it.
