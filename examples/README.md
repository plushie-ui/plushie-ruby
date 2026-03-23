# Plushie Examples

Example apps demonstrating Plushie's features from minimal to complex.
Run any example with:

```sh
ruby examples/<name>.rb
```

Or via Rake (add `require "plushie/rake"` to your Rakefile):

```sh
rake plushie:run[Counter]
```

## DSL styles

The examples use the block-based DSL throughout, which is the primary
Ruby API:

```ruby
window("main", title: "App") do
  column(padding: 16, spacing: 8) do
    text("greeting", "Hello")
    button("save", "Save")
  end
end
```

The typed widget builders (Layer 2 API) are also available for
programmatic use -- see `Plushie::Widget::Button.new("id").build`.

## Examples

### Counter

**File:** `counter.rb`

Minimal Elm-architecture example. Two buttons increment and decrement a count.
Start here to understand `init`, `update`, and `view`.

```sh
ruby examples/counter.rb
```

### Todo

**File:** `todo.rb`

Todo list with text input, checkboxes, filtering (all/active/completed), and
delete. Demonstrates `text_input` with `on_submit`, `checkbox` with dynamic
IDs, scoped ID binding in `update` via `scope:` pattern matching, and
`Command.focus` for refocusing after submit.

```sh
ruby examples/todo.rb
```

### Notes

**File:** `notes.rb`

Notes app combining all five state helpers: `Plushie::State` (change tracking),
`Plushie::Undo` (undo/redo for title and body editing), `Plushie::Selection`
(multi-select in list view), `Plushie::Route` (stack-based `/list` and `/edit`
navigation), and `Plushie::DataQuery` (search/query across note fields). Shows
how to compose multiple state helpers in a single model.

```sh
ruby examples/notes.rb
```

### Clock

**File:** `clock.rb`

Displays the current UTC time, updated every second. Demonstrates
`Plushie::Subscription.every` for timer-based subscriptions. The `subscribe`
callback returns a timer that delivers `Event::Timer[tag: :tick]` events.

```sh
ruby examples/clock.rb
```

### Shortcuts

**File:** `shortcuts.rb`

Logs keyboard events to a scrollable list. Demonstrates
`Plushie::Subscription.on_key_press` for global keyboard handling. Shows
modifier key detection (Ctrl, Alt, Shift, Command) and the `Event::Key`
struct with pattern matching.

```sh
ruby examples/shortcuts.rb
```

### AsyncFetch

**File:** `async_fetch.rb`

Button that triggers simulated background work. Demonstrates
`Command.async` for running expensive operations off the main update
loop. Shows the `[model, command]` return form from `update` and how
async results are delivered back as `Event::Async` events.

```sh
ruby examples/async_fetch.rb
```

### ColorPicker

**File:** `color_picker.rb`

HSV color picker using a canvas widget. A hue ring surrounds a
saturation/value square with drag interaction. Demonstrates canvas
layers, path commands for the hue ring segments, linear gradients
with alpha for the SV square, and coordinate-based canvas events
(press/move/release for continuous drag).

```sh
ruby examples/color_picker.rb
```

### Catalog

**File:** `catalog.rb`

Comprehensive widget catalog exercising every widget type across four
tabbed sections:

- **Layout:** column, row, container, scrollable, stack, grid, pin, floating,
  responsive, keyed_column, themer, space
- **Input:** button, text_input, checkbox, toggler, radio, slider,
  vertical_slider, pick_list, combo_box, text_editor
- **Display:** text, rule, progress_bar, tooltip, image, svg, markdown,
  rich_text, canvas
- **Composite:** mouse_area, sensor, pane_grid, table, simulated tabs,
  modal, collapsible panel

Use this as a reference for widget props and event patterns.

```sh
ruby examples/catalog.rb
```

### RatePlushie

**File:** `rate_plushie.rb`

App rating page with custom canvas-drawn widgets composed into a styled
UI. Features a 5-star rating built from path-drawn star geometry and an
animated theme toggle. The entire page theme interpolates smoothly
between light and dark palettes.

Demonstrates: canvas shapes with interactive hit regions, path commands
for star geometry, timer-based animation via subscriptions with easing
functions, dynamic theme interpolation, form validation, and complex
view composition with nested helper methods.

```sh
ruby examples/rate_plushie.rb
```
