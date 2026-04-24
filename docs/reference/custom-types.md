# Custom Types

Shared prop types live under `Plushie::Type::*`. They encode and
normalise the values widgets accept (lengths, colours, paddings,
fonts, accessibility hashes, and the like) before they reach the
wire. Each type is a plain Ruby module exposing module-level class
methods, not a formal behaviour: there is no compile-time field
validation, no guard generation, and no widget-macro integration.
Widget builders call into these modules at encode time, which means
any value you pass survives `prop :field` unchanged until a
builder is asked to emit a wire hash.

The conventions are uniform across the catalogue:

- `Module.encode(value)` converts an accepted input to the wire
  shape. All type modules expose this. Unknown values raise
  `ArgumentError` at encode time, not at view time, so typos in
  your view tree surface as loud errors during the first render
  rather than silent wire drift.
- `Module.cast(value)` normalises an input to a canonical Ruby
  value without going to the wire. Only the types that benefit
  from eager normalisation expose it (`Color`, `Padding`, `A11y`).
  `Color.encode` is an alias for `Color.cast` since the canonical
  Ruby representation already matches the wire.
- Struct types (`Border::Spec`, `Shadow::Spec`, `Font::Spec`,
  `StyleMap::Spec`, `A11y::Spec`, `Padding::Pad`) are immutable
  `Data` classes. Use `#with(field: value)` for modifications and
  `#to_wire` (where provided) to materialise the wire hash. A
  corresponding `Module.from_opts(**kwargs)` constructor accepts
  the same fields so you rarely need `Spec.new` directly.
- Symbol enums map one-to-one to the renderer's snake_case string
  values. `encode` calls `to_s` after validating membership
  against a `VALID` constant on the module.

There is no shared behaviour or mixin: each module stands alone.
If you find yourself wanting a common supertype for introspection
(listing every valid value across all enum types, for example),
the `VALID` constants are the right handle.

## Catalogue

| Module | One-liner | Documented in |
|---|---|---|
| `Plushie::Type::A11y` | Accessibility role, label, relationships, state | [Accessibility reference](accessibility.md) |
| `Plushie::Type::Alignment` | `align_x` / `align_y` values for layout containers | [Windows and Layout reference](windows-and-layout.md#alignment) |
| `Plushie::Type::Anchor` | Scroll anchor: `:start`, `:end` | [Windows and Layout reference](windows-and-layout.md#anchor) |
| `Plushie::Type::Border` | Stroke colour, width, radius (uniform or per-corner) | [Windows and Layout reference](windows-and-layout.md#border) |
| `Plushie::Type::Color` | Named colours, hex strings, RGBA constructors | [Themes and Styling reference](themes-and-styling.md#color) |
| `Plushie::Type::ContentFit` | Image / SVG scaling mode | [Built-in Widgets reference](built-in-widgets.md#content-fit) |
| `Plushie::Type::Direction` | Orientation for `scrollable` and `rule` | below |
| `Plushie::Type::FilterMethod` | Image interpolation mode | [Built-in Widgets reference](built-in-widgets.md#filter-method) |
| `Plushie::Type::Font` | Family, weight, style, stretch | [Built-in Widgets reference](built-in-widgets.md#font) |
| `Plushie::Type::Gradient` | Linear gradients with stop lists | [Themes and Styling reference](themes-and-styling.md#gradient) |
| `Plushie::Type::Length` | `:fill`, `:shrink`, `[:fill_portion, n]`, pixels | [Windows and Layout reference](windows-and-layout.md#sizing) |
| `Plushie::Type::LineHeight` | Relative multiplier or absolute pixels | below |
| `Plushie::Type::Padding` | Uniform, axis, per-side, or struct forms | [Windows and Layout reference](windows-and-layout.md#padding) |
| `Plushie::Type::Position` | Tooltip placement: `:top`, `:bottom`, `:left`, `:right`, `:follow_cursor` | below |
| `Plushie::Type::Shadow` | Drop shadow colour, offset, blur radius | [Windows and Layout reference](windows-and-layout.md#shadow) |
| `Plushie::Type::Shaping` | Text shaping strategy | [Built-in Widgets reference](built-in-widgets.md#shaping) |
| `Plushie::Type::StyleMap` | Per-instance widget style overrides | [Themes and Styling reference](themes-and-styling.md#stylemap) |
| `Plushie::Type::Theme` | Built-in theme names, `:system`, or a custom palette | [Themes and Styling reference](themes-and-styling.md#theme) |
| `Plushie::Type::Wrapping` | Line-break strategy for text | [Built-in Widgets reference](built-in-widgets.md#wrapping) |

The sections below cover the types without a dedicated home.

## Direction

`Plushie::Type::Direction`

Orientation symbol accepted by two props:

- `scrollable(direction:)` sets the scroll axis (`:vertical`,
  `:horizontal`, or `:both`).
- `rule(direction:)` draws a horizontal or vertical divider
  (`:horizontal`, `:vertical`).

```ruby
scrollable("content", direction: :vertical) do
  column(spacing: 8) do
    # ...
  end
end

rule("divider", direction: :horizontal)
```

Valid values: `:horizontal`, `:vertical`, `:both`. The `:both`
variant is scrollable-specific; passing it to `rule` is accepted
by the type but produces no useful rendering.

## Position

`Plushie::Type::Position`

Placement symbol for the `tooltip` widget's `position:` prop. The
tooltip sits on the named side of its anchor child, or follows the
cursor:

```ruby
tooltip("save-tip", "Save the current document", position: :top) do
  button("save", "Save")
end

tooltip("cursor-tip", "Current coordinates", position: :follow_cursor) do
  container("canvas-area", width: :fill, height: :fill)
end
```

Valid values: `:top`, `:bottom`, `:left`, `:right`,
`:follow_cursor`. Unknown symbols raise `ArgumentError` at encode.

## LineHeight

`Plushie::Type::LineHeight`

Controls the vertical space a line of text occupies. Used by
`text` and `rich_text`, and on individual spans inside rich text.

| Input | Meaning |
|---|---|
| Numeric | Relative multiplier of the font size (`1.5` is 150 percent) |
| `{ relative: n }` | Explicit relative multiplier (same as a bare number) |
| `{ absolute: n }` | Absolute line height in pixels |

```ruby
text("body", "Readable paragraph", size: 14, line_height: 1.5)

text("compact", "Tight", line_height: {relative: 1.1})

text("measured", "Exact", size: 16, line_height: {absolute: 24})
```

A bare number is the quickest form and matches renderer defaults.
Use the hash form only when you want to disambiguate (for example,
when a 24 reads as "24 pixels" but you meant "24x the font size")
or need the absolute variant.

Bare numbers and relative hashes produce identical output; they
exist as distinct forms so callers can make intent explicit in
source. A hash missing both keys raises `ArgumentError`.

## Authoring your own type

Ruby props are not typed at declaration time. Inside
`Plushie::Widget.define` (or a widget class), `prop :field` accepts
any Ruby value. Normalisation and validation happen when the
widget builds its node for the wire, at which point the builder
calls into whichever `Plushie::Type::*` module is appropriate for
the field.

To introduce a new shared type, write a module with class methods:

```ruby
module MyApp
  module Type
    module Temperature
      module_function

      VALID_UNITS = %i[celsius fahrenheit kelvin].freeze

      def cast(value)
        case value
        in Numeric then { value: value.to_f, unit: :celsius }
        in { value: Numeric => v, unit: Symbol => u } if VALID_UNITS.include?(u)
          { value: v.to_f, unit: u }
        else
          raise ArgumentError, "invalid temperature: #{value.inspect}"
        end
      end

      def encode(value)
        cast(value)
      end
    end
  end
end
```

Call `MyApp::Type::Temperature.encode(value)` from your custom
widget's builder before writing the field into the wire hash. No
registration is required; Ruby's duck typing is sufficient. If the
value should round-trip to a canonical in-memory form before
reaching the builder, expose `cast` separately and have consumers
call it eagerly. Otherwise, a single `encode` method is enough.

For custom widgets specifically, the widget's `build` callback is
the natural place to run type encoders over props. See
[Custom Widgets reference](custom-widgets.md) for the builder
lifecycle.

## See also

- [Built-in Widgets reference](built-in-widgets.md) - where each
  type is consumed (`font:`, `shaping:`, `wrapping:`,
  `content_fit:`, `filter_method:`)
- [Windows and Layout reference](windows-and-layout.md) - `Length`,
  `Padding`, `Alignment`, `Border`, `Shadow`, `Anchor`
- [Themes and Styling reference](themes-and-styling.md) - `Color`,
  `Theme`, `StyleMap`, `Gradient`
- [Accessibility reference](accessibility.md) - `A11y` fields and
  inference rules
- [Custom Widgets reference](custom-widgets.md) - embedding type
  encoders in widget builders
