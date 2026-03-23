# Composition patterns

Plushie provides primitives, not pre-built composites. There is no `TabBar`
widget, no `Modal` widget, no `Card` widget. Instead, you compose the same
building blocks -- `row`, `column`, `container`, `stack`, `button`, `text`,
`rule`, `mouse_area`, `space` -- with `StyleMap` to build any UI pattern you
need.

This guide shows how. Every pattern is copy-pasteable and produces a polished
result. All examples assume `include Plushie::App` is in your class. See the
[notes demo](https://github.com/plushie-ui/plushie-demos/tree/main/ruby/notes)
for a full app using pure Ruby composite widgets (NoteCard, Toolbar, ShortcutBar)
with no Rust dependency.

---

## 1. Tab bar

A horizontal row of buttons where the active tab is visually distinct.

### Code

```ruby
class TabApp
  include Plushie::App

  Model = Plushie::Model.define(:active_tab)

  def init(_opts) = Model.new(active_tab: :overview)

  def update(model, event)
    case event
    in Event::Widget[type: :click, id: /\Atab:(.+)\z/]
      model.with(active_tab: $1.to_sym)
    else
      model
    end
  end

  def view(model)
    tabs = [:overview, :details, :settings]

    window("main", title: "Tab Demo") do
      column(width: :fill) do
        row(spacing: 0) do
          tabs.each do |tab|
            button("tab:#{tab}", tab.to_s.capitalize,
              style: tab_style(model.active_tab == tab),
              padding: {top: 10, bottom: 10, left: 20, right: 20})
          end
        end

        rule

        container("content", padding: 20, width: :fill, height: :fill) do
          text("Content for #{model.active_tab}")
        end
      end
    end
  end

  private

  def tab_style(active)
    if active
      Plushie::Type::StyleMap::Spec.new(
        background: "#ffffff",
        text_color: "#1a1a1a",
        border: Plushie::Type::Border.from_opts(color: "#0066ff", width: 2, rounded: 0)
      )
    else
      Plushie::Type::StyleMap::Spec.new(
        background: "#f0f0f0",
        text_color: "#666666",
        hovered: {background: "#e0e0e0"}
      )
    end
  end
end
```

### How it works

Each tab is a `button` with a `StyleMap` driven by whether it matches the
active tab. The active style uses a solid background and a blue border.
The `rule` below the row acts as a full-width horizontal divider.

---

## 2. Sidebar navigation

A dark column on the left side of the window with navigation items.

### Code

```ruby
class SidebarApp
  include Plushie::App

  NAV_ITEMS = [[:inbox, "Inbox"], [:sent, "Sent"], [:drafts, "Drafts"], [:trash, "Trash"]]

  Model = Plushie::Model.define(:page)

  def init(_opts) = Model.new(page: :inbox)

  def update(model, event)
    case event
    in Event::Widget[type: :click, id: /\Anav:(.+)\z/]
      model.with(page: $1.to_sym)
    else
      model
    end
  end

  def view(model)
    window("main", title: "Sidebar Demo") do
      row(width: :fill, height: :fill) do
        container("sidebar", width: 200, height: :fill, background: "#1e1e2e", padding: 8) do
          column(spacing: 4, width: :fill) do
            text("nav_label", "Navigation", size: 12, color: "#888888")
            space(height: 8)

            NAV_ITEMS.each do |id, label|
              button("nav:#{id}", label,
                style: nav_item_style(model.page == id),
                width: :fill,
                padding: {top: 8, bottom: 8, left: 12, right: 12})
            end
          end
        end

        container("main", width: :fill, height: :fill, padding: 24) do
          text("page_title", "#{model.page.to_s.capitalize} page", size: 20)
        end
      end
    end
  end

  private

  def nav_item_style(selected)
    if selected
      Plushie::Type::StyleMap::Spec.new(
        background: "#3366ff",
        text_color: "#ffffff",
        hovered: {background: "#4477ff"}
      )
    else
      Plushie::Type::StyleMap::Spec.new(
        background: "#1e1e2e",
        text_color: "#cccccc",
        hovered: {background: "#2a2a3e", text_color: "#ffffff"}
      )
    end
  end
end
```

---

## 3. Toolbar

A compact horizontal bar with grouped icon-style buttons separated by
vertical rules. Toolbars typically sit at the top of an editor or document
view.

### Code

```ruby
class ToolbarApp
  include Plushie::App

  Model = Plushie::Model.define(:bold, :italic, :underline)

  def init(_opts) = Model.new(bold: false, italic: false, underline: false)

  def update(model, event)
    case event
    in Event::Widget[type: :click, id: "tool:bold"]
      model.with(bold: !model.bold)
    in Event::Widget[type: :click, id: "tool:italic"]
      model.with(italic: !model.italic)
    in Event::Widget[type: :click, id: "tool:underline"]
      model.with(underline: !model.underline)
    else
      model
    end
  end

  def view(model)
    window("main", title: "Toolbar Demo") do
      column(width: :fill) do
        # Toolbar
        container("toolbar", width: :fill, background: "#f5f5f5", padding: 4) do
          row(spacing: 2, align_y: :center) do
            # File group
            button("tool:new", "New", style: tool_style(false), padding: 6)
            button("tool:open", "Open", style: tool_style(false), padding: 6)
            button("tool:save", "Save", style: tool_style(false), padding: 6)

            # Separator
            rule(direction: :vertical, height: 20)

            # Format group
            button("tool:bold", "B", style: tool_style(model.bold), padding: 6)
            button("tool:italic", "I", style: tool_style(model.italic), padding: 6)
            button("tool:underline", "U", style: tool_style(model.underline), padding: 6)

            # Separator
            rule(direction: :vertical, height: 20)

            # Spacer pushes trailing items to the right
            space(width: :fill)

            button("tool:help", "?", style: tool_style(false), padding: 6)
          end
        end

        rule

        # Editor area
        container("editor", width: :fill, height: :fill, padding: 16) do
          text("Editor content goes here")
        end
      end
    end
  end

  private

  def tool_style(toggled)
    if toggled
      Plushie::Type::StyleMap::Spec.new(
        background: "#d0d0d0",
        text_color: "#1a1a1a",
        border: Plushie::Type::Border.from_opts(color: "#b0b0b0", width: 1, rounded: 3),
        hovered: {background: "#c0c0c0"}
      )
    else
      Plushie::Type::StyleMap::Spec.new(
        background: "#f5f5f5",
        text_color: "#333333",
        hovered: {background: "#e0e0e0"},
        pressed: {background: "#d0d0d0"}
      )
    end
  end
end
```

### How it works

The toolbar is a `container` with a light background wrapping a `row`. Button
groups are visually separated by vertical `rule` widgets. A `space(width:
:fill)` between the main group and the help button pushes the help button to
the far right -- a common toolbar layout technique.

Toggle-style buttons (bold, italic, underline) pass their current state to
`tool_style`. When toggled on, they get a depressed look via a darker
background and a subtle border. The `pressed` status override on untoggled
buttons gives tactile click feedback.

---

## 4. Modal dialog

A full-screen overlay with a centered dialog box using `stack`.

### Code

```ruby
class ModalApp
  include Plushie::App

  Model = Plushie::Model.define(:show_modal, :confirmed)

  def init(_opts) = Model.new(show_modal: false, confirmed: false)

  def update(model, event)
    case event
    in Event::Widget[type: :click, id: "open_modal"]
      model.with(show_modal: true)
    in Event::Widget[type: :click, id: "confirm"]
      model.with(show_modal: false, confirmed: true)
    in Event::Widget[type: :click, id: "cancel"]
      model.with(show_modal: false)
    else
      model
    end
  end

  def view(model)
    window("main", title: "Modal Demo") do
      stack(width: :fill, height: :fill) do
        # Layer 0: main content
        container("main", width: :fill, height: :fill, padding: 24, center: true) do
          column(spacing: 12, align_x: :center) do
            text("main_content", "Main application content", size: 20)

            if model.confirmed
              text("confirmed_msg", "Action confirmed.", color: "#22aa44")
            end

            button("open_modal", "Open Dialog", style: :primary)
          end
        end

        # Layer 1: modal overlay
        if model.show_modal
          container("overlay", width: :fill, height: :fill,
                    background: "#00000088", center: true) do
            container("dialog", max_width: 400, padding: 24,
                      background: "#ffffff",
                      border: Plushie::Type::Border.from_opts(color: "#dddddd", width: 1, rounded: 8),
                      shadow: Plushie::Type::Shadow.from_opts(color: "#00000040", offset_y: 4, blur_radius: 16)) do
              column(spacing: 16) do
                text("dialog_title", "Confirm action", size: 18, color: "#1a1a1a")
                text("dialog_body", "Are you sure you want to proceed?",
                     color: "#555555", wrapping: :word)

                row(spacing: 8, align_x: :end) do
                  button("cancel", "Cancel", style: :secondary)
                  button("confirm", "Confirm", style: :primary)
                end
              end
            end
          end
        end
      end
    end
  end
end
```

---

## 5. Card

A container with rounded corners, a border, an optional shadow, and an
optional header section.

### Code

```ruby
def view(model)
  window("main", title: "Card Demo") do
    column(padding: 24, spacing: 16, width: :fill) do
      card("info", "System status") do
        text("status_msg", "All services operational", color: "#22aa44")
        text("last_checked", "Last checked: 2 minutes ago", size: 12, color: "#888888")
      end
    end
  end
end

private

def card(id, title, &block)
  border = Plushie::Type::Border.from_opts(color: "#e0e0e0", width: 1, rounded: 8)
  shadow = Plushie::Type::Shadow.from_opts(color: "#00000020", offset_y: 2, blur_radius: 8)

  container(id, width: :fill, padding: 16, background: "#ffffff",
            border: border, shadow: shadow) do
    column(spacing: 8) do
      text("card_title", title, size: 16, color: "#1a1a1a")
      rule
      instance_exec(&block) if block
    end
  end
end
```

---

## 6. Split panel

Two content areas side by side with a draggable divider.

### Code

```ruby
def view(model)
  window("main", title: "Split Panel Demo") do
    row(width: :fill, height: :fill) do
      container("left_panel", width: model.left_width, height: :fill,
                padding: 16, background: "#fafafa") do
        column(spacing: 8) do
          text("left_title", "Left panel", size: 16)
          text("left_desc", "File browser or sidebar content.", color: "#666666")
        end
      end

      mouse_area("divider", cursor: :resizing_horizontally) do
        container("divider_track", width: 5, height: :fill, background: "#e0e0e0") do
          rule(direction: :vertical)
        end
      end

      container("right_panel", width: :fill, height: :fill, padding: 16) do
        column(spacing: 8) do
          text("right_title", "Right panel", size: 16)
          text("right_desc", "Main editor or content area.", color: "#666666")
        end
      end
    end
  end
end
```

---

## 7. Breadcrumb

A horizontal trail of clickable path segments.

### Code

```ruby
def view(model)
  window("main", title: "Breadcrumb Demo") do
    column(padding: 16, spacing: 16, width: :fill) do
      row(spacing: 4, align_y: :center) do
        model.path.each_with_index do |segment, index|
          last = index == model.path.length - 1

          if last
            text("crumb_current", segment, size: 14, color: "#1a1a1a")
          else
            button("crumb:#{index}", segment,
              style: crumb_style,
              padding: {top: 2, bottom: 2, left: 4, right: 4})
            text("sep:#{index}", ">", size: 14, color: "#999999")
          end
        end
      end

      rule
      text("viewing", "Viewing: #{model.path.last}", size: 18)
    end
  end
end

private

def crumb_style
  Plushie::Type::StyleMap::Spec.new(
    background: "#00000000",
    text_color: "#3366ff",
    hovered: {text_color: "#1144cc", background: "#f0f0ff"}
  )
end
```

---

## 8. Badge / chip

Small containers with coloured backgrounds and pill shapes.

### Code

```ruby
# Display-only badge
def badge(id, label, bg_color, text_color)
  container(id,
    padding: {top: 2, bottom: 2, left: 8, right: 8},
    background: bg_color,
    border: Plushie::Type::Border.from_opts(rounded: 999)) do
    text("badge_text", label, size: 11, color: text_color)
  end
end

# Clickable chip style
def chip_style(selected)
  if selected
    Plushie::Type::StyleMap::Spec.new(
      background: "#3366ff",
      text_color: "#ffffff",
      border: Plushie::Type::Border.from_opts(color: "#3366ff", width: 1, rounded: 999)
    )
  else
    Plushie::Type::StyleMap::Spec.new(
      background: "#f0f0f0",
      text_color: "#333333",
      border: Plushie::Type::Border.from_opts(color: "#cccccc", width: 1, rounded: 999),
      hovered: {background: "#e4e4e4"}
    )
  end
end
```

---

## 9. Canvas interactive shapes

Canvas handles custom visuals and hit testing. Built-in widgets handle
text editing, scrolling, and popup positioning. Complex components compose
both -- the canvas draws what iced's widget set cannot, and built-in widgets
handle what canvas cannot.

### Canvas-only: custom toggle switch

A single canvas with one interactive group. The renderer handles hover
feedback and focus ring locally. The host only sees click events.

#### Code

```ruby
class ToggleApp
  include Plushie::App

  Model = Plushie::Model.define(:dark_mode)

  def init(_opts) = Model.new(dark_mode: false)

  def update(model, event)
    case event
    in Event::Widget[type: :canvas_element_click, id: "toggle", data: {"element_id" => "switch"}]
      model.with(dark_mode: !model.dark_mode)
    else
      model
    end
  end

  def view(model)
    on = model.dark_mode
    knob_x = on ? 36 : 16

    window("main", title: "Toggle Demo") do
      column(padding: 24, spacing: 16) do
        canvas("toggle", width: 52, height: 28) do
          layer("switch") do
            group do
              interactive("switch",
                on_click: true,
                cursor: :pointer,
                a11y: {role: :switch, label: "Dark mode", toggled: on})

              rect(0, 0, 52, 28, fill: on ? "#4CAF50" : "#ccc", radius: 14)
              circle(knob_x, 14, 10, fill: "#fff")
            end
          end
        end
      end
    end
  end
end
```

#### How it works

The canvas block collects `layer` declarations into a layers map. Each
layer contains shapes -- here a single `group` with a rounded rect
background and a circle knob. The `interactive` directive inside the
group enables click events, sets the pointer cursor, and provides a11y
metadata. On click, the host toggles `dark_mode` and the view re-renders
with new positions and colours.

Screen reader: "Dark mode, switch, on." Keyboard: Tab focuses the
canvas, Enter/Space toggles.

### Canvas-only: chart with clickable data points

Multiple interactive groups inside a canvas. Each bar is focusable,
has a tooltip, and announces its position in the set.

#### Code

```ruby
class ChartApp
  include Plushie::App

  DATA = [
    {month: "Jan", value: 120, color: "#3498db"},
    {month: "Feb", value: 85, color: "#2ecc71"},
    {month: "Mar", value: 200, color: "#e74c3c"},
    {month: "Apr", value: 150, color: "#f39c12"}
  ]

  Model = Plushie::Model.define(:selected)

  def init(_opts) = Model.new(selected: nil)

  def update(model, event)
    case event
    in Event::Widget[type: :canvas_element_click, id: "chart", data: {"element_id" => id}]
      model.with(selected: id)
    else
      model
    end
  end

  def view(model)
    bar_w = 60
    chart_h = 220
    count = DATA.length

    window("main", title: "Chart Demo") do
      column(padding: 24, spacing: 16) do
        canvas("chart", width: count * (bar_w + 20), height: chart_h, event_rate: 30) do
          layer("bars") do
            DATA.each_with_index do |bar, i|
              bar_h = bar[:value]
              bar_x = i * (bar_w + 20)
              bar_y = chart_h - bar_h

              group(x: bar_x, y: bar_y) do
                interactive("bar-#{i}",
                  on_click: true,
                  on_hover: true,
                  cursor: :pointer,
                  tooltip: "#{bar[:month]}: #{bar[:value]} units",
                  a11y: {
                    role: :button,
                    label: "#{bar[:month]}: #{bar[:value]} units",
                    position_in_set: i + 1,
                    size_of_set: count
                  })

                rect(0, 0, bar_w, bar_h, fill: bar[:color])
                text(bar_w / 2, -12, "#{bar[:value]}", fill: "#666", align_x: :center)
              end
            end
          end
        end

        if model.selected
          text("selection", "Selected: #{model.selected}")
        end
      end
    end
  end
end
```

#### How it works

Each bar is a `group` containing a rect and a label. The `interactive`
field enables click and hover events, sets a pointer cursor, and
provides a tooltip. The `position_in_set` and `size_of_set` fields
let screen readers announce "Jan: 120 units, button, 1 of 4." Arrow
keys navigate between bars. `event_rate: 30` throttles hover events
to 30fps.

### Canvas + built-in: custom styled text input

Stack a canvas behind a `text_input` to draw a custom background. The
canvas is purely decorative -- the text_input handles cursor, selection,
IME, and clipboard.

#### Code

```ruby
class SearchApp
  include Plushie::App

  Model = Plushie::Model.define(:query)

  def init(_opts) = Model.new(query: "")

  def update(model, event)
    case event
    in Event::Widget[type: :input, id: "search", value:]
      model.with(query: value)
    else
      model
    end
  end

  def view(model)
    window("main", title: "Search Demo") do
      column(padding: 24, spacing: 16) do
        stack(width: 300, height: 36) do
          canvas("search-bg", width: 300, height: 36,
            layers: {"bg" => [
              Plushie::Canvas::Shape.rect(0, 0, 300, 36, fill: "#f5f5f5", radius: 8,
                stroke: "#ddd", stroke_width: 1),
              Plushie::Canvas::Shape.image("priv/icons/search.svg", 8, 8, 20, 20)
            ]})

          container("search-wrap", padding: {left: 36, top: 0, right: 8, bottom: 0},
                    height: 36) do
            text_input("search", model.query, style: :borderless, width: :fill)
          end
        end
      end
    end
  end
end
```

#### How it works

The `stack` layers the canvas background behind the text_input. The
canvas draws the rounded rect and search icon -- purely visual, no
`interactive` field needed. The `text_input` sits on top in a padded
container so it clears the icon area.

Canvas = visuals. text_input = editing and IME.

### Canvas + built-in: custom combo box

Overlay positions the dropdown. Canvas draws the trigger and option
visuals. text_input handles filtering. scrollable handles long lists.

#### Code

```ruby
class ComboApp
  include Plushie::App

  OPTIONS = ["Elixir", "Rust", "Python", "TypeScript", "Go", "Haskell", "OCaml", "Zig"]

  Model = Plushie::Model.define(:open, :filter, :selected)

  def init(_opts) = Model.new(open: false, filter: "", selected: nil)

  def update(model, event)
    case event
    in Event::Widget[type: :click, id: "combo-trigger"]
      model.with(open: !model.open)
    in Event::Widget[type: :input, id: "combo-filter", value:]
      model.with(filter: value, open: true)
    in Event::Widget[type: :canvas_element_click, id: "combo-opts", data: {"element_id" => /\Aopt-(\d+)\z/}]
      index = $1.to_i
      chosen = filtered_options(model.filter)[index]
      model.with(selected: chosen, open: false, filter: "")
    else
      model
    end
  end

  def view(model)
    filtered = filtered_options(model.filter)
    count = filtered.length

    window("main", title: "Combo Demo") do
      column(padding: 24, spacing: 16, width: :fill) do
        text("label", "Language:", size: 14)

        overlay("combo", position: :below, gap: 4) do
          anchor do
            stack(width: 250, height: 36) do
              canvas("combo-bg", width: 250, height: 36,
                layers: {"bg" => [
                  Plushie::Canvas::Shape.rect(0, 0, 250, 36, fill: "#fff", radius: 8,
                    stroke: "#ddd", stroke_width: 1),
                  Plushie::Canvas::Shape.path(220, 12, "M 0 0 L 6 8 L 12 0", fill: "#999")
                ]})

              container("combo-input", padding: {left: 12, top: 0, right: 32, bottom: 0},
                        height: 36) do
                text_input("combo-filter", model.filter,
                  placeholder: model.selected || "Select...",
                  style: :borderless,
                  width: :fill)
              end
            end
          end

          if model.open && count > 0
            content do
              container("combo-dropdown", width: 250, background: "#fff",
                        border: Plushie::Type::Border.from_opts(color: "#ddd", width: 1, rounded: 8),
                        clip: true) do
                scrollable("combo-scroll", height: [count * 32, 200].min) do
                  canvas("combo-opts", width: 250, height: count * 32,
                    layers: {"opts" => filtered.each_with_index.map { |opt, i|
                      Plushie::Canvas::Shape.group(0, i * 32, [
                        Plushie::Canvas::Shape.rect(0, 0, 250, 32, fill: "#fff")
                          .hover_style(fill: "#e8f0fe"),
                        Plushie::Canvas::Shape.text(12, 22, opt, fill: "#333")
                      ]).interactive(
                        id: "opt-#{i}",
                        on_click: true,
                        on_hover: true,
                        a11y: {
                          role: :option,
                          label: opt,
                          selected: opt == model.selected,
                          position_in_set: i + 1,
                          size_of_set: count
                        })
                    }})
                end
              end
            end
          end
        end

        if model.selected
          text("chosen", "Selected: #{model.selected}", color: "#333")
        end
      end
    end
  end

  private

  def filtered_options(filter)
    return OPTIONS if filter.empty?
    OPTIONS.select { |opt| opt.downcase.include?(filter.downcase) }
  end
end
```

#### How it works

The `overlay` widget positions the dropdown below the trigger. The
trigger is a `stack` with a canvas background (border, chevron icon)
and a borderless text_input for typing. The dropdown is a `scrollable`
wrapping a canvas whose interactive groups are the options.

Each piece does what it is good at:

- **canvas** -- custom visuals, hover feedback, hit testing
- **text_input** -- text editing, cursor, IME, clipboard
- **overlay** -- popup positioning that escapes parent bounds
- **scrollable** -- scroll container for long option lists

---

## General techniques

These patterns share a few recurring techniques worth calling out:

**Style methods over style constants.** Most patterns define a private
method like `tab_style(active)` or `chip_style(selected)` that returns
a `StyleMap`. This keeps style logic next to the view, makes it easy to
derive styles from model state, and avoids class constants for something
that varies per render.

**`space(width: :fill)` as a flex pusher.** Inserting a space with
`width: :fill` inside a row pushes everything after it to the right edge.
This is the flexbox `margin-left: auto` equivalent and is used in toolbars,
headers, and nav bars.

**`border` radius 999 for pills.** Setting a border radius larger than the
element can possibly be tall creates a perfect pill shape. The renderer
clamps the radius to the available space.

**Transparent backgrounds for link-style buttons.** Using `#00000000` (fully
transparent) as a button background makes it look like a text link. Add a
hover state with a subtle background tint for affordance.

**`if` without `else` in blocks.** The DSL filters out `nil` values from
children. An `if` without `else` returns `nil` when the condition is false,
so the child simply does not appear in the tree. This is how the modal
overlay conditionally renders.

**Arrays in blocks are flattened.** Returning an array from inside a block
(via `each`, `map`, or a literal `[a, b]` expression) works because children
are flattened one level. The breadcrumb pattern relies on this to emit a
button and separator as a pair.

**Helper methods for repeated compositions.** Extract common patterns into
private methods (like `card` or `badge`) that return node trees. Keep them
in the same class or a dedicated view helpers module. They are plain methods
returning plain data -- no macros needed.

---

## State helpers

Plushie provides optional state management modules for common UI patterns.
None of these are required -- your model can be any object.

All helpers are pure data structures with no threads or side effects.

### Plushie::State

Path-based access to nested model data with revision tracking and
transactions.

```ruby
state = Plushie::State.new({user: {name: "Alice", prefs: {theme: "dark"}}})

# Read
Plushie::State.get(state, [:user, :name])
# => "Alice"

# Write
state = Plushie::State.put(state, [:user, :prefs, :theme], "light")
Plushie::State.revision(state)
# => 1

# Transaction (atomic multi-step update with rollback)
state = Plushie::State.begin_transaction(state)
state = Plushie::State.put(state, [:user, :name], "Bob")
state = Plushie::State.put(state, [:user, :prefs, :theme], "dark")
state = Plushie::State.commit_transaction(state)
# Both changes applied atomically. Revision incremented once.

# Or roll back:
state = Plushie::State.rollback_transaction(state)
# All changes since begin_transaction discarded.
```

The revision counter is useful for determining whether a re-render is
needed. If the revision has not changed, the tree has not changed.

Use `Plushie::State` when your model has deeply nested data that you update
from multiple event handlers. Skip it when your model is flat or simple
enough that plain hash updates read clearly.

### Plushie::Undo

Undo/redo stack with coalescing.

```ruby
undo = Plushie::Undo.new(model)

# Apply a command (records it for undo)
undo = Plushie::Undo.apply(undo, {
  apply: ->(m) { m.with(name: "Bob") },
  undo: ->(m) { m.with(name: "Alice") },
  label: "Rename to Bob"
})

Plushie::Undo.current(undo).name  # => "Bob"

# Undo
undo = Plushie::Undo.undo(undo)
Plushie::Undo.current(undo).name  # => "Alice"

# Redo
undo = Plushie::Undo.redo(undo)
Plushie::Undo.current(undo).name  # => "Bob"

# Coalescing (group rapid changes, like typing)
undo = Plushie::Undo.apply(undo, {
  apply: ->(m) { m.with(text: m.text + "a") },
  undo: ->(m) { m.with(text: m.text[0..-2]) },
  coalesce: [:typing, "editor"],
  coalesce_window_ms: 500
})
# Multiple applies with the same coalesce key within the time window
# are merged into a single undo entry.
```

Use `Plushie::Undo` when your app has user actions that should be reversible
(text editing, form filling, drawing, configuration changes). Skip it for
apps where undo does not make sense (dashboards, monitoring).

### Plushie::Selection

Selection state for lists and tables.

```ruby
sel = Plushie::Selection.new(mode: :multi)

sel = Plushie::Selection.select(sel, "item_1")
sel = Plushie::Selection.select(sel, "item_3", extend: true)

Plushie::Selection.selected(sel)
# => Set["item_1", "item_3"]

sel = Plushie::Selection.toggle(sel, "item_1")
Plushie::Selection.selected(sel)
# => Set["item_3"]

# Range select (shift-click pattern)
sel = Plushie::Selection.new(mode: :range, order: ["a", "b", "c", "d", "e"])
sel = Plushie::Selection.select(sel, "b")
sel = Plushie::Selection.range_select(sel, "d")
Plushie::Selection.selected(sel)
# => Set["b", "c", "d"]
```

Use `Plushie::Selection` when you have selectable lists, tables, or tree
views. It handles single, multi (ctrl-click), and range (shift-click)
selection modes correctly. Skip it for simple cases where a single
`selected_id` in your model is sufficient.

### Plushie::Route

Client-side routing for multi-view apps.

```ruby
route = Plushie::Route.new("/dashboard")

route = Plushie::Route.push(route, "/settings", {tab: "general"})
Plushie::Route.current(route)   # => "/settings"
Plushie::Route.params(route)    # => {tab: "general"}

route = Plushie::Route.pop(route)
Plushie::Route.current(route)   # => "/dashboard"
```

Routes are just data. There is no URL bar, no browser history API. This
is for apps that have multiple "screens" and want back/forward navigation
with history tracking. Use it for apps with distinct screens (settings,
detail views, wizards). Skip it for single-screen apps.

### Plushie::Data

Query pipeline for in-memory record collections.

```ruby
records = [
  {id: 1, name: "Alice", role: "admin", active: true},
  {id: 2, name: "Bob", role: "user", active: false},
  {id: 3, name: "Carol", role: "admin", active: true}
]

Plushie::Data.query(records,
  filter: ->(r) { r[:active] },
  sort: [:asc, :name],
  page: 1,
  page_size: 10
)
# => {entries: [...], total: 2, page: 1, page_size: 10}
```

Use `Plushie::Data` when you have tabular data that needs filtering, sorting,
grouping, or pagination in the UI. It is a query pipeline over arrays, not a
database -- keep data sets small enough to fit in memory.

### General philosophy

These helpers share a few properties:

- **Pure data.** No threads, no processes, no side effects.
- **Optional.** You can use zero, one, or all of them.
- **Composable.** Embed them as fields in your model.

```ruby
def init(_opts)
  Model.new(
    state: Plushie::State.new({...}),
    undo: Plushie::Undo.new({...}),
    selection: Plushie::Selection.new(mode: :single),
    route: Plushie::Route.new("/home"),
    todos: []
  )
end
```
