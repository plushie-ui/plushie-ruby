# Composition patterns

Plushie provides primitives, not pre-built composites. There is no `TabBar`
widget, no `Modal` widget, no `Card` widget. Instead, you compose the same
building blocks -- `row`, `column`, `container`, `stack`, `button`, `text`,
`rule`, `mouse_area`, `space` -- with `StyleMap` to build any UI pattern you
need.

This guide shows how. Every pattern is copy-pasteable and produces a polished
result. All examples assume `include Plushie::App` is in your class.

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
      Plushie::Type::StyleMap.new
        .background("#ffffff")
        .text_color("#1a1a1a")
        .border(Plushie::Type::Border.new.color("#0066ff").width(2).rounded(0))
    else
      Plushie::Type::StyleMap.new
        .background("#f0f0f0")
        .text_color("#666666")
        .hovered(background: "#e0e0e0")
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
      Plushie::Type::StyleMap.new
        .background("#3366ff")
        .text_color("#ffffff")
        .hovered(background: "#4477ff")
    else
      Plushie::Type::StyleMap.new
        .background("#1e1e2e")
        .text_color("#cccccc")
        .hovered(background: "#2a2a3e", text_color: "#ffffff")
    end
  end
end
```

---

## 3. Modal dialog

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
                      border: Plushie::Type::Border.new.color("#dddddd").width(1).rounded(8),
                      shadow: Plushie::Type::Shadow.new.color("#00000040").offset(0, 4).blur_radius(16)) do
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

## 4. Card

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
  border = Plushie::Type::Border.new.color("#e0e0e0").width(1).rounded(8)
  shadow = Plushie::Type::Shadow.new.color("#00000020").offset(0, 2).blur_radius(8)

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

## 5. Split panel

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

## 6. Breadcrumb

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
  Plushie::Type::StyleMap.new
    .background("#00000000")
    .text_color("#3366ff")
    .hovered(text_color: "#1144cc", background: "#f0f0ff")
end
```

---

## 7. Badge / chip

Small containers with coloured backgrounds and pill shapes.

### Code

```ruby
# Display-only badge
def badge(id, label, bg_color, text_color)
  container(id,
    padding: {top: 2, bottom: 2, left: 8, right: 8},
    background: bg_color,
    border: Plushie::Type::Border.new.rounded(999)) do
    text("badge_text", label, size: 11, color: text_color)
  end
end

# Clickable chip style
def chip_style(selected)
  if selected
    Plushie::Type::StyleMap.new
      .background("#3366ff")
      .text_color("#ffffff")
      .border(Plushie::Type::Border.new.color("#3366ff").width(1).rounded(999))
  else
    Plushie::Type::StyleMap.new
      .background("#f0f0f0")
      .text_color("#333333")
      .border(Plushie::Type::Border.new.color("#cccccc").width(1).rounded(999))
      .hovered(background: "#e4e4e4")
  end
end
```

---

## General techniques

**Style methods over style constants.** Most patterns define a private
method like `tab_style(active)` or `chip_style(selected)` that returns
a `StyleMap`. This keeps style logic next to the view and makes it easy to
derive styles from model state.

**`space(width: :fill)` as a flex pusher.** Inserting a space with
`width: :fill` inside a row pushes everything after it to the right edge.

**`border` radius 999 for pills.** Setting a border radius larger than the
element height creates a perfect pill shape.

**Transparent backgrounds for link-style buttons.** Using `#00000000` as a
button background makes it look like a text link.

**`if` without `else` in blocks.** The DSL filters out `nil` values from
children. An `if` without `else` returns `nil`, so the child simply does
not appear.

**Arrays in blocks are flattened.** The DSL flattens child arrays one
level, so returning an array from a conditional or loop works naturally.

**Helper methods for repeated compositions.** Extract common patterns into
private methods (like `card` or `badge`) that return node trees.

---

## State helpers

Plushie provides optional state management modules for common UI patterns.
None of these are required -- your model can be any object.

All helpers are pure data structures with no threads or side effects.

### Plushie::State

Path-based access to nested model data with revision tracking.

```ruby
state = Plushie::State.new({user: {name: "Alice", prefs: {theme: "dark"}}})

Plushie::State.get(state, [:user, :name])
# => "Alice"

state = Plushie::State.put(state, [:user, :prefs, :theme], "light")
Plushie::State.revision(state)
# => 1
```

### Plushie::Undo

Undo/redo stack with coalescing.

```ruby
undo = Plushie::Undo.new(model)

undo = Plushie::Undo.apply(undo, {
  apply: ->(m) { m.with(name: "Bob") },
  undo: ->(m) { m.with(name: "Alice") },
  label: "Rename to Bob"
})

Plushie::Undo.current(undo).name  # => "Bob"

undo = Plushie::Undo.undo(undo)
Plushie::Undo.current(undo).name  # => "Alice"

undo = Plushie::Undo.redo(undo)
Plushie::Undo.current(undo).name  # => "Bob"
```

### Plushie::Selection

Selection state for lists and tables.

```ruby
sel = Plushie::Selection.new(mode: :multi)

sel = Plushie::Selection.select(sel, "item_1")
sel = Plushie::Selection.select(sel, "item_3", extend: true)

Plushie::Selection.selected(sel)
# => Set["item_1", "item_3"]
```

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
