# Accessibility

Plushie integrates with platform accessibility services via
[AccessKit](https://github.com/AccessKit/accesskit): VoiceOver on
macOS, AT-SPI/Orca on Linux, UI Automation/NVDA/JAWS on Windows.
Most semantics are inferred automatically from widget type, so
correct roles, labels, and state ship without extra work. The
SDK-side types live in `Plushie::Type::A11y`, widget defaults are
declared with `default_a11y`, and announcement commands live in
`Plushie::Command`.

## Accessible by default

Each widget class declares `default_a11y role:, label_from:`, and
the builder merges those defaults into the resolved `a11y` hash
before the node reaches the wire. Layout containers (`column`,
`row`, `container`, `stack`, `grid`, `pane_grid`, ...) resolve to
`generic_container`, which the platform accessibility tree filters
out so screen reader users navigate through the semantic content
without intermediate wrappers.

When overrides are needed (custom canvas controls, widgets with
context-dependent labels, relationship annotations), the `a11y:`
prop is available on every widget.

## Auto-inference

### Role mapping

| Widget | Inferred role |
|---|---|
| `button` | `button` |
| `text`, `rich_text` | `label` |
| `text_input` | `text_input` |
| `text_editor` | `multiline_text_input` |
| `checkbox` | `check_box` |
| `toggler` | `switch` |
| `radio` | `radio_button` |
| `slider`, `vertical_slider` | `slider` |
| `pick_list`, `combo_box` | `combo_box` |
| `progress_bar` | `progress_indicator` |
| `scrollable` | `scroll_view` |
| `image`, `svg`, `qr_code` | `image` |
| `canvas` | `canvas` |
| `table` | `table` |
| `pane_grid` | `group` |
| `rule` | `separator` |
| `window` | `window` |
| `markdown` | `document` |
| `tooltip` | `tooltip` |
| `container`, `column`, `row`, `stack`, `grid` | `generic_container` |

### Label inference

When the caller does not pass a `label` inside `a11y:`, the builder
copies the value of another prop into the a11y label via the
`label_from:` directive on the widget's `default_a11y` declaration:

| Widget | Prop used as label |
|---|---|
| `button`, `checkbox`, `toggler`, `radio`, `slider`, `vertical_slider`, `progress_bar` | `label` |
| `text`, `rich_text` | `content` |
| `text_input`, `text_editor`, `pick_list`, `combo_box` | `placeholder` |
| `image`, `svg`, `qr_code` | no default (set `alt:` via `a11y:`) |

A user-supplied `a11y:` hash wins per field: the role, the label,
and any other key you pass in replaces the inferred default.

## The a11y prop

Every widget accepts an `a11y:` keyword. The value is either a
plain `Hash` or a `Plushie::Type::A11y::Spec` struct:

```ruby
# Hash form (most common).
button("save", "Save", a11y: { description: "Save the current document" })

text_input("email", model.email, a11y: {
  required: true,
  labelled_by: "email-label"
})

# Struct form, immutable.
spec = Plushie::Type::A11y.from_opts(role: :button, label: "Submit")
button("save", "Save", a11y: spec)
```

`Plushie::Type::A11y::Spec` is a `Data`-backed struct. Use `with`
to produce a modified copy and `to_wire` to emit a wire-ready hash.
Both forms resolve identically; internally the builder calls
`A11y.cast`, which strips `nil` fields and checks that `mnemonic`
is a single character.

### Fields

| Field | Type | Purpose |
|---|---|---|
| `role` | symbol | Override the inferred role |
| `label` | string | Accessible name (override inferred label) |
| `description` | string | Longer description read after the label |
| `live` | `:polite` / `:assertive` | Live region announcement mode |
| `hidden` | boolean | Exclude from accessibility tree |
| `expanded` | boolean | Disclosure state (combobox, menu) |
| `required` | boolean | Form field is required |
| `level` | 1-6 | Heading level |
| `busy` | boolean | Suppress announcements during updates |
| `invalid` | boolean | Form validation error state |
| `modal` | boolean | Dialog is modal (traps focus) |
| `read_only` | boolean | Value is readable but not editable |
| `toggled` | boolean | Toggle / checked state |
| `selected` | boolean | Selection state |
| `value` | string | Current value for assistive technology |
| `orientation` | `:horizontal` / `:vertical` | Layout orientation hint |
| `disabled` | boolean | Disabled state override |
| `mnemonic` | string (single character) | Keyboard mnemonic |
| `position_in_set` | integer | 1-based position in a group |
| `size_of_set` | integer | Total items in the group |
| `has_popup` | string | Popup type: `"listbox"`, `"menu"`, `"dialog"`, `"tree"`, `"grid"` |

### Cross-references

| Field | Purpose |
|---|---|
| `labelled_by` | ID of a widget that provides this widget's label |
| `described_by` | ID of a widget that provides a description |
| `error_message` | ID of a widget showing the validation error |
| `active_descendant` | ID of the currently active descendant (comboboxes, listboxes) |
| `radio_group` | List of widget IDs in the radio group |

Cross-reference IDs are resolved relative to the current scope
during tree normalization. A bare `"label"` inside a scope named
`"form"` rewrites to `"form/label"`. An unresolved reference
produces an `A11yRefUnresolved` diagnostic (see below) and the ID
ships unchanged.

Set `hidden: true` to exclude decorative content (background
images, separator glyphs) from the accessibility tree entirely. Do
not use `hidden:` on interactive widgets; screen reader users lose
access to them.

## Accessible name computation

Screen readers announce a widget's accessible name before its
role. Resolution order:

1. **Direct label** - an explicit `a11y: { label: ... }` or the
   label inferred from the widget's `label_from:` prop.
2. **Labelled-by** - if no direct label, the renderer follows
   `labelled_by` to a sibling widget. For roles that support
   name-from-contents (button, checkbox, radio, link), descendant
   text is used automatically.
3. **No name** - the screen reader announces only the role.

Interactive widgets without an accessible name produce a
`MissingAccessibleName` diagnostic during tree normalization.
Always ensure interactive widgets have a `label`, a descendant
text child, or a `labelled_by` reference.

## Keyboard navigation

Plushie has built-in keyboard navigation:

| Key | Behaviour |
|---|---|
| Tab / Shift+Tab | Cycle focus through focusable widgets |
| Space / Enter | Activate the focused widget |
| Arrow keys | Navigate within sliders, lists, and similar widgets |
| F6 / Shift+F6 | Cycle focus between pane_grid panes |
| Ctrl+Tab | Escape the current focus scope |
| Escape | Close popups, dismiss modals |

Focus rings follow the focus-visible pattern: they appear on
keyboard navigation and not on mouse clicks.

### Focus commands

Commands from `Plushie::Command` drive focus programmatically:

| Method | Purpose |
|---|---|
| `Command.focus(widget_id)` | Move focus to a specific widget |
| `Command.focus_next` | Move to the next focusable widget |
| `Command.focus_previous` | Move to the previous focusable widget |
| `Command.focus_next_within(scope)` | Next focusable widget inside a subtree |
| `Command.focus_previous_within(scope)` | Previous focusable widget inside a subtree |
| `Command.find_focused(tag)` | Query which widget currently has focus |
| `Command.focus_window(window_id)` | Bring a window to the front |

`focus_next_within` and `focus_previous_within` confine the cycle
to a subtree rooted at the given widget ID. Useful for menus, pane
grids, and keyboard containers that want a bounded Tab cycle
without leaking focus to siblings.

`Command.find_focused` delivers its result as
`Event::System[type: :find_focused, tag:, value:]`; match on the
tag to route the reply.

### Canvas keyboard navigation

Canvas interactive groups opt into keyboard focus with
`focusable: true`. Without it, the element responds to mouse clicks
but is invisible to keyboard navigation and screen readers. When
`a11y:` is not supplied, the group infers a role from its
interactive fields: `focusable` produces `group`, `on_click`
produces `button`, `draggable` produces `slider`. An explicit
`a11y:` hash replaces the inferred defaults.

```ruby
interactive(
  group([rect(0, 0, 100, 36, fill: "#3b82f6")]),
  "save-btn",
  on_click: true,
  focusable: true,
  cursor: :pointer,
  a11y: { role: :button, label: "Save experiment" }
)
```

## Screen reader announcements

### Live regions

Setting `live: :polite` or `live: :assertive` turns a widget into a
live region. The renderer re-announces the widget's label or
content when it changes.

| Value | Behaviour | Use for |
|---|---|---|
| `:polite` | Announced after current speech finishes | Status messages, counters, progress updates |
| `:assertive` | Interrupts current speech immediately | Error messages, critical alerts |

```ruby
text("status", model.status_message, a11y: { live: :polite })

text("error", model.error, a11y: { live: :assertive, role: :alert })
```

Reserve `:assertive` for urgent context. Rapid updates on an
assertive region cause announcement storms. Prefer `:polite` for
anything that updates more than once per user action. Do not set
`live:` on static content; screen readers re-announce on every
tree rebuild even when the content hasn't changed.

### Direct announcements

`Plushie::Command.announce` pushes text straight to assistive
technology without a visible widget:

```ruby
def update(model, event)
  case event
  in Event::Widget[type: :click, id: "save"]
    [save(model), Plushie::Command.announce("Document saved")]
  end
end
```

The signature is `announce(text, politeness = :polite)`.
`politeness` is `:polite` (queued) or `:assertive` (interrupts);
any other value raises `ArgumentError`. Use `:polite` for most
toast-style feedback; reserve `:assertive` for urgent context the
user must hear immediately.

## Focus and accessibility events

Accessibility-related interactions arrive through the standard
event pipeline. Assistive technology activations (e.g. VoiceOver
"activate") produce the same `Event::Widget[type: :click]` as
direct interaction, so no special handling is required in `update`.

| Event | Meaning |
|---|---|
| `Event::Widget[type: :focused]` | A widget received keyboard focus |
| `Event::Widget[type: :blurred]` | A widget lost keyboard focus |
| `Event::System[type: :find_focused, tag:, value:]` | Reply to `Command.find_focused` |
| `Event::System[type: :announce, value:]` | Renderer-originated announcement notice |

```ruby
case event
in Event::Widget[type: :focused, id: "email"]
  model.with(editing_field: "email")

in Event::Widget[type: :blurred, id: "email"]
  validate_email(model)

in Event::System[type: :find_focused, tag: "check_focus", value: id]
  model.with(focus_trace: [id] + model.focus_trace)
end
```

## Diagnostics

The renderer emits typed accessibility diagnostics through
`Event::DiagnosticMessage`. Match on the `diagnostic` field:

| Variant | Meaning |
|---|---|
| `Diagnostic::MissingAccessibleName[type_name:, id:]` | An interactive widget had no label, text child, `a11y.label`, or `a11y.labelled_by` |
| `Diagnostic::A11yRefUnresolved[id:, key:, value:, is_member:]` | A `labelled_by`, `described_by`, `error_message`, `active_descendant`, or `radio_group` ID did not resolve to any declared widget |

`key` on `A11yRefUnresolved` identifies which field held the bad
reference. `is_member` is true when the bad reference was inside a
collection (e.g., a radio group's members list). Both diagnostics
indicate authoring bugs: the affected widget ships without the
missing metadata.

## Disabled vs read-only

These are semantically different:

| State | Meaning | Screen reader behaviour |
|---|---|---|
| Disabled | Not currently usable | Often skipped in Tab navigation, announced as "dimmed" or "unavailable" |
| Read-only | Has a value that can be read but not changed | Fully navigable and announced, editing commands blocked |

Use `a11y: { disabled: true }` (or the widget's own `disabled:`
prop where available) for controls that become active based on
other state. Use `a11y: { read_only: true }` for displaying values
the user can select and copy but not edit.

## Radio groups

Radio widgets sharing the same `group:` string are auto-detected
during tree normalization. The builder injects `position_in_set`
and `size_of_set` into each radio's `a11y` hash and populates an
implicit `radio_group` list of sibling IDs, so screen readers
announce "option 2 of 3" without extra annotations:

```ruby
column do
  radio("small",  "Small",  group: "size", value: "s")
  radio("medium", "Medium", group: "size", value: "m")
  radio("large",  "Large",  group: "size", value: "l")
end
```

If you set `position_in_set` or `size_of_set` on a specific radio
yourself, inference respects the override; the node is still
counted toward the group's size for its siblings.

## Common patterns

### Form field labelling

Every form control needs an accessible name.

Direct label:

```ruby
text_input("email", model.email,
  placeholder: "Email address",
  a11y: { label: "Email address" })
```

Cross-widget `labelled_by`:

```ruby
text("email-label", "Email address")
text_input("email", model.email, a11y: { labelled_by: "email-label" })
```

Description for additional context:

```ruby
text_input("password", model.password,
  a11y: { label: "Password", described_by: "password-hint" })
text("password-hint", "Must be at least 8 characters", size: 11)
```

For `text_input`, `text_editor`, `checkbox`, `pick_list`, and
`combo_box`, the `required:` and `validation:` props flow into
`a11y.required`, `a11y.invalid`, and `a11y.error_message` during
normalization, so validation metadata does not need a separate
`a11y:` hash.

### Grouping related controls

Use the `:group` role when controls are logically related and the
grouping helps the user understand context:

```ruby
container("shipping-options",
  a11y: { role: :group, label: "Shipping options" }) do
  radio("standard", "Standard (5-7 days)", group: "shipping", value: :standard)
  radio("express",  "Express (1-2 days)",  group: "shipping", value: :express)
end
```

Layout containers without an `a11y:` override already filter out
of the tree, so only wrap things in groups when the grouping adds
semantic value.

## Testing

The test helpers in `Plushie::Test::Helpers` expose assertions that
operate on the resolved accessibility tree, catching missing
labels, wrong roles, and missing state annotations:

```ruby
assert find_by_role(:button)
assert find_by_label("Save")
assert_a11y("#save", role: "button", label: "Save")

a11y = resolved_a11y("#email")
assert_equal true, a11y[:required]
```

`resolved_a11y` returns the a11y hash after inference and
normalization, so tests see what assistive technology will see.
`assert_no_diagnostics` catches missing-name and unresolved-ref
regressions.

## See also

- [Built-in Widgets reference](built-in-widgets.md) - widget list
  and the `a11y:` prop on every widget
- [Commands reference](commands.md) - focus commands, announcements,
  and `find_focused`
- [Composition Patterns reference](composition-patterns.md) - forms,
  modals, menus, and other composed accessibility patterns
