# Accessibility

Plushie provides built-in accessibility support via
[accesskit](https://github.com/AccessKit/accesskit), a cross-platform
accessibility toolkit. The default renderer build includes accessibility,
activating native platform APIs automatically: VoiceOver on macOS,
AT-SPI/Orca on Linux, and UI Automation/NVDA/JAWS on Windows.

Screen reader users, keyboard-only users, and other AT users interact with
the same widgets and receive the same events as mouse users. No special
event handling is needed in your `update` -- AT actions produce the same
`Event::Widget[type: :click, id: id]`, `Event::Widget[type: :input, ...]`
events as direct interaction.

## How it works

Iced's fork provides native accessibility support. Three pieces work together:

1. **iced widgets report `Accessible` metadata** -- each widget declares
   its role, label, and state to the accessibility system automatically.

2. **TreeBuilder assembles the accesskit tree** -- iced walks the widget
   tree during `operate()`, collecting metadata and building an accesskit
   `TreeUpdate`.

3. **AT actions become native iced events** -- when an AT triggers an action,
   iced translates it to a native event. The renderer maps it to a standard
   plushie event and sends it to Ruby over the wire protocol.

## Auto-inference

Most widgets get correct accessibility semantics without any annotation.

### Role mapping

| Widget type | Role | Notes |
|---|---|---|
| `button` | Button | |
| `text`, `rich_text` | Label | |
| `text_input` | TextInput | |
| `text_editor` | MultilineTextInput | |
| `checkbox` | CheckBox | |
| `toggler` | Switch | |
| `radio` | RadioButton | |
| `slider`, `vertical_slider` | Slider | |
| `pick_list`, `combo_box` | ComboBox | |
| `progress_bar` | ProgressIndicator | |
| `scrollable` | ScrollView | |
| `container`, `column`, `row`, `stack` | GenericContainer | |
| `window` | Window | |
| `image`, `svg`, `qr_code` | Image | |
| `canvas` | Canvas | |
| `table` | Table | |
| `markdown` | Document | |

### Labels

Labels are extracted from the prop that makes sense for each widget type:

| Widget type | Label source |
|---|---|
| `button`, `checkbox`, `toggler`, `radio` | `label` prop |
| `text`, `rich_text` | `content` prop |
| `image`, `svg` | `alt` prop |
| `text_input` | `placeholder` prop (as description) |

### State

Widget state is extracted from existing props automatically:

| State | Source | Widgets |
|---|---|---|
| Disabled | `disabled: true` | Any widget |
| Toggled | `checked` prop | `checkbox` |
| Toggled | `is_toggled` prop | `toggler` |
| Numeric value | `value` prop | `slider`, `progress_bar` |

## The a11y prop

Every widget accepts an `a11y` prop -- a hash of fields that override or
augment the inferred semantics.

### Fields

| Field | Type | Description |
|---|---|---|
| `role` | Symbol | Override the inferred role |
| `label` | String | Accessible name |
| `description` | String | Longer description |
| `live` | `:off`, `:polite`, `:assertive` | Live region |
| `hidden` | Boolean | Exclude from accessibility tree |
| `expanded` | Boolean | Expanded/collapsed state |
| `required` | Boolean | Mark form field as required |
| `level` | Integer | Heading level (1-6) |
| `busy` | Boolean | Suppresses AT announcements until cleared (auto-managed by sliders during drag; set explicitly for custom continuous interactions) |
| `invalid` | Boolean | Form validation failure |
| `modal` | Boolean | Dialog is modal |
| `read_only` | Boolean | Can be read but not edited |
| `mnemonic` | String | Alt+letter keyboard shortcut |
| `toggled` | Boolean | Toggled/checked state |
| `selected` | Boolean | Selected state |
| `value` | String | Current value as string |
| `orientation` | `:horizontal`, `:vertical` | Orientation hint |
| `labelled_by` | String | ID of labelling widget |
| `described_by` | String | ID of describing widget |
| `error_message` | String | ID of error message widget |
| `disabled` | Boolean | Override disabled state for AT |
| `position_in_set` | Integer | 1-based position in a set |
| `size_of_set` | Integer | Total items in the set |
| `has_popup` | String | Popup type: `"listbox"`, `"menu"`, `"dialog"` |

### Using the a11y prop

<!-- test: a11y_heading_level, a11y_icon_button_label, a11y_landmark_region, a11y_live_region_polite, a11y_hidden_decorative_image, a11y_labelled_by -- keep this code block in sync with the test -->
```ruby
# Headings
text("title", "Welcome to MyApp", a11y: {role: :heading, level: 1})

# Icon buttons that need a label for screen readers
button("close", "X", a11y: {label: "Close dialog"})

# Landmark regions
container("search_results", a11y: {role: :region, label: "Search results"}) do
  # ...
end

# Live regions -- AT announces changes automatically
text("save_status", "#{model.saved_count} items saved", a11y: {live: :polite})

# Decorative elements hidden from AT
rule(a11y: {hidden: true})
image("divider", "/images/decorative-line.png", a11y: {hidden: true})

# Disclosure / expandable sections
container("details", a11y: {expanded: model.expanded, role: :group, label: "Advanced options"}) do
  if model.expanded
    # ...
  end
end

# Required form fields
text_input("email", model.email, a11y: {required: true, label: "Email address"})
```

### Available roles

**Interactive:**
`:button`, `:checkbox`, `:combo_box`, `:link`, `:menu_item`, `:radio`,
`:slider`, `:switch`, `:tab`, `:text_input`, `:text_editor`, `:tree_item`

**Structure:**
`:generic_container`, `:group`, `:heading`, `:label`, `:list`, `:list_item`,
`:row`, `:cell`, `:column_header`, `:row_header`, `:table`, `:tree`

**Landmarks:**
`:navigation`, `:region`, `:search`

**Status:**
`:alert`, `:alert_dialog`, `:dialog`, `:status`, `:timer`, `:meter`,
`:progress_indicator`

**Other:**
`:document`, `:image`, `:menu`, `:menu_bar`, `:scroll_view`, `:separator`,
`:tab_list`, `:tab_panel`, `:toolbar`, `:tooltip`, `:window`

## Patterns and best practices

### Every interactive widget needs a name

```ruby
# Good -- label is auto-inferred
button("save", "Save document")

# Good -- explicit a11y label for terse visual text
button("close", "X", a11y: {label: "Close dialog"})

# Bad -- screen reader just announces "button"
button("do_thing", "")
```

### Use headings to create structure

```ruby
def view(model)
  window("main", title: "MyApp") do
    column do
      text("page_title", "Dashboard", a11y: {role: :heading, level: 1})
      text("h_recent", "Recent activity", a11y: {role: :heading, level: 2})
      # ... activity list ...
      text("h_actions", "Quick actions", a11y: {role: :heading, level: 2})
      # ... action buttons ...
    end
  end
end
```

### Use landmarks for page regions

```ruby
column do
  container("nav", a11y: {role: :navigation, label: "Main navigation"}) do
    row do
      button("home", "Home")
      button("settings", "Settings")
    end
  end

  container("main_content", a11y: {role: :region, label: "Main content"}) do
    # ...
  end
end
```

### Live regions for dynamic content

- `:polite` -- announced after the current speech finishes
- `:assertive` -- interrupts current speech

<!-- test: a11y_live_region_assertive -- keep this code block in sync with the test -->
```ruby
text("status", model.status_message, a11y: {live: :polite})

if model.error
  text("error", model.error, a11y: {live: :assertive, role: :alert})
end
```

### Busy state and continuous interactions

When a value changes rapidly (e.g. during a slider drag or canvas
interaction), setting `busy: true` on the node suppresses AT
announcements until `busy` clears. AT then announces the final
value once, avoiding a flood of intermediate announcements. This
maps to WAI-ARIA `aria-busy`.

**Built-in widgets handle this automatically.** Sliders set
`busy: true` during drag and clear it on release. No SDK code
needed.

**For app-managed live regions** that reflect values from a
continuous interaction (e.g. a text display showing a hex color
while the user drags a canvas), set `busy` explicitly based on
whether the interaction is active:

```ruby
text("hex", hex_value, a11y: {live: :polite, busy: model.drag != :none})
```

When the drag ends, `busy` clears and the screen reader announces
the final hex value.

### Forms

```ruby
column(spacing: 12) do
  column(spacing: 4) do
    text("email-label", "Email")
    text("email-help", "We'll send a confirmation link")
    text_input("email", model.email,
      a11y: {
        labelled_by: "email-label",
        described_by: "email-help",
        error_message: "email-error"
      })
    if model.email_error
      text("email-error", model.email_error,
        a11y: {role: :alert, live: :assertive})
    end
  end
end
```

### Hiding decorative content

<!-- test: a11y_hidden_decorative_rule -- keep this code block in sync with the test -->
```ruby
rule(a11y: {hidden: true})
image("hero", "/images/banner.png", a11y: {hidden: true})
space(a11y: {hidden: true})
```

### Canvas widgets

Canvas draws arbitrary shapes -- always provide alternative text:

<!-- test: a11y_canvas_with_alt_text -- keep this code block in sync with the test -->
```ruby
canvas("chart", layers: {"data" => chart_shapes},
  a11y: {role: :image, label: "Sales chart: Q1 revenue up 15%, Q2 flat"})
```

### Interactive canvas shapes

When a canvas contains shapes with the `interactive` field, each shape
becomes a separate accessible node. The canvas widget itself is the
container; individual shapes are focusable children. Tab and Arrow keys
navigate between shapes. Enter/Space activates the focused shape.

This is how you build accessible custom widgets from canvas primitives.
Without interactive shapes, a canvas is a single opaque "image" node to
screen readers.

```ruby
canvas("color-picker", width: 200, height: 100,
  layers: {"options" => colors.each_with_index.map { |color, i|
    Plushie::Canvas::Shape.rect(0, i * 32, 200, 32, fill: color.hex)
      .interactive(
        id: "color-#{i}",
        on_click: true,
        a11y: {
          role: :radio,
          label: color.name,
          selected: color == model.selected,
          position_in_set: i + 1,
          size_of_set: colors.length
        })
  }})
```

Screen reader: "Red, radio button, 1 of 5, selected."

The `position_in_set` and `size_of_set` fields tell screen readers
where each shape sits in the group. Without them, the reader announces
each shape individually with no positional context.

### Custom widgets with state

When building custom widgets with canvas or other primitives, use `toggled`,
`selected`, `value`, and `orientation` to expose their state to AT users.
Without these, screen readers have no way to know the state of a custom
control drawn with raw shapes.

```ruby
# Custom toggle switch built with canvas
canvas("dark-mode-switch", layers: [...],
  a11y: {
    role: :switch,
    label: "Dark mode",
    toggled: model.dark_mode
  })

# Custom gauge showing percentage
canvas("cpu-gauge", layers: [...],
  a11y: {
    role: :meter,
    label: "CPU usage",
    value: "#{model.cpu_percent}%",
    orientation: :horizontal
  })
```

`toggled` and `selected` are booleans. Use `toggled` for on/off controls
(switches, checkboxes) and `selected` for selection state (list items, tabs).
`value` is a string describing the current value in human-readable form.
`orientation` tells AT users whether a control is horizontal or vertical,
which affects how they navigate it.

### Set position and popup hints

Use `position_in_set` / `size_of_set` when building composite widgets
from primitives (custom lists, tab bars, radio groups). Without these,
screen readers cannot announce position context like "Item 3 of 7".

```ruby
# Radio group with position context
container("colors", a11y: {role: :group, label: "Favorite color"}) do
  colors.each_with_index do |color, idx|
    radio("color_#{color}", color, model.selected_color,
      a11y: {
        position_in_set: idx + 1,
        size_of_set: colors.length
      })
  end
end

# Custom tab bar
row do
  model.tabs.each_with_index do |tab, idx|
    button("tab_#{tab.id}", tab.label,
      a11y: {
        role: :tab,
        selected: tab.id == model.active_tab,
        position_in_set: idx + 1,
        size_of_set: model.tabs.length
      })
  end
end
```

Use `has_popup` to tell screen readers that activating a widget opens
a popup of a specific type:

```ruby
# Dropdown button
button("menu_btn", "Options",
  a11y: {has_popup: "menu", expanded: model.menu_open})

# Combo box with listbox popup
text_input("search", model.query,
  a11y: {has_popup: "listbox", expanded: model.suggestions_visible})
```

Use `disabled` to override the disabled state for AT when a widget
is visually disabled via custom styling but doesn't use the standard
`disabled` prop:

```ruby
button("submit", "Submit",
  a11y: {disabled: !model.form_valid})
```

### Expanded/collapsed state

For disclosure widgets, toggleable panels, and dropdown menus:

```ruby
def view(model)
  column do
    button("toggle_details",
      model.show_details ? "Hide details" : "Show details",
      a11y: {expanded: model.show_details})

    if model.show_details
      container("details", a11y: {role: :region, label: "Details"}) do
        # detail content
      end
    end
  end
end
```

The `expanded` field tells AT whether the control is currently
expanded or collapsed, so screen readers can announce "Show details,
button, collapsed" or "Hide details, button, expanded".

## Widget-specific accessibility props

Some widgets accept accessibility props directly as top-level fields,
outside the `a11y` hash. The Rust renderer reads these and maps them
to the appropriate accesskit node properties. They are simpler to use
than the full `a11y` hash for common cases.

### alt

An accessible label string for visual content widgets where the content
itself is not textual.

| Widget | Prop | Type |
|---|---|---|
| `image` | `alt` | String |
| `svg` | `alt` | String |
| `qr_code` | `alt` | String |
| `canvas` | `alt` | String |

<!-- test: a11y_image_alt_prop, a11y_svg_alt_prop, a11y_canvas_alt_prop -- keep this code block in sync with the test -->
```ruby
image("logo", "/images/logo.png", alt: "Company logo")
svg("icon", "/icons/search.svg", alt: "Search")
qr_code("invite", invite_url, alt: "QR code for invite link")
canvas("chart", layers: layers, alt: "Revenue chart")
```

### label

An accessible label string for interactive widgets that don't have a
visible text label prop.

| Widget | Prop | Type |
|---|---|---|
| `slider` | `label` | String |
| `vertical_slider` | `label` | String |
| `progress_bar` | `label` | String |

```ruby
slider("volume", [0, 100], model.volume, label: "Volume")
progress_bar("upload", [0, 100], model.progress, label: "Upload progress")
```

### decorative

A boolean that hides visual content from assistive technology entirely.
Use this for images and SVGs that are purely decorative and convey no
information.

| Widget | Prop | Type |
|---|---|---|
| `image` | `decorative` | Boolean |
| `svg` | `decorative` | Boolean |

```ruby
image("divider", "/images/decorative-line.png", decorative: true)
svg("flourish", "/icons/flourish.svg", decorative: true)
```

## Testing accessibility

```ruby
def test_heading_has_correct_role
  assert_role("#page_title", "heading")
end

def test_email_field_is_required
  assert_a11y("#email", {"required" => true, "label" => "Email address"})
end
```

## Platform support

| Platform | AT | API | Status |
|---|---|---|---|
| Linux | Orca | AT-SPI2 | Supported |
| macOS | VoiceOver | NSAccessibility | Supported |
| Windows | NVDA, JAWS, Narrator | UI Automation | Supported |
