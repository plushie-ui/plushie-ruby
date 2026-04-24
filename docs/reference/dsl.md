# DSL

`Plushie::UI` is the block-based DSL used inside `view(model)`. It
mixes in widget methods that collect nodes into a thread-local
context stack as blocks execute, then returns a `Plushie::Node` tree
for the runtime to diff. `Plushie::App` includes it automatically,
so every app class sees the widget methods as private instance
methods.

This reference covers how the mixin is wired, how the context stack
and auto-IDs work, the `memo` cache, canvas and table DSLs,
`WidgetSet` overrides, and the typed builder alternative under
`Plushie::Widget::*`.

## How the DSL mixes in

```ruby
class Counter
  include Plushie::App

  def view(model)
    window("main", title: "Counter") do
      column(padding: 16, spacing: 8) do
        text("count", "Count: #{model.count}")
        button("increment", "+")
      end
    end
  end
end
```

`include Plushie::App` does three things:

- Includes `Plushie::UI`, bringing every widget method into the
  class as a private instance method.
- Includes `DefaultCallbacks` for the optional lifecycle hooks
  (`subscribe`, `settings`, `window_config`, `handle_renderer_exit`).
- Includes `Aliases`, exposing `Event`, `Command`, and `Subscription`
  as shortcuts for the top-level modules.

Widget methods are private, which matters for one practical reason:
blocks passed to the DSL execute in the caller's binding, not via
`instance_eval`. `self` remains the app instance throughout the
view, so private helpers, instance variables, and accessor methods
all work normally inside a `column do ... end` block:

```ruby
def view(model)
  window("main") do
    column do
      text("greeting", greeting_text(model))  # private helper
      button("save", "Save") if model.dirty?  # instance method
    end
  end
end

private

def greeting_text(model)
  "Hello, #{model.user.name}"
end
```

The block-in-caller-binding approach is why the DSL uses a
thread-local context stack rather than an instance-local one:
there is no DSL instance to attach state to.

## The context stack

`Plushie::UI::Context` is a thread-local stack of child arrays.
Each container method pushes an empty array, runs the block, and
pops the array back off:

```ruby
def _plushie_container(type, id, props, &block)
  children = if block
    child_list = []
    UI::Context.push(child_list)
    begin
      block.call
    ensure
      UI::Context.pop
    end
    child_list
  else
    props.delete(:children) || []
  end

  node = Node.new(id:, type:, props:, children:)
  parent = UI::Context.current
  parent << node if parent
  node
end
```

Leaf methods do the same minus the push: they build a `Node` and
append it to `Context.current` if a context exists.

`Context` exposes a small surface:

| Method | Purpose |
|---|---|
| `UI::Context.push(children)` | Push a child-array frame onto the stack |
| `UI::Context.pop` | Pop the top frame (called from `ensure`) |
| `UI::Context.current` | The top frame, or `nil` at the top level |
| `UI::Context.clear` | Reset the stack (runtime error recovery) |

Calls outside a DSL block return the constructed node directly.
That is how `view(model)` returns a single window node: `window(...)`
has no outer context, so the node falls out of the call as a return
value instead of being appended anywhere.

Because the stack lives on `Thread.current`, concurrent views from
different threads do not interfere. Each thread has its own stack;
each runtime renders from a single thread.

## Auto-IDs

Layout containers (`column`, `row`, `stack`, `grid`, `keyed_column`,
`pin`, `floating`, `overlay`, `themer`) and some display widgets
(`text` with a single argument, `rule`, `space`, `table`) support
an omitted ID. When the ID argument is `nil`, the DSL generates one
from the caller's source location:

```ruby
def _plushie_auto_id
  loc = caller_locations(2, 1)&.first
  "auto:#{loc&.label}:#{loc&.lineno}"
end
```

The enclosing method name and line number produce IDs like
`"auto:view:42"` or `"auto:render_sidebar:108"`. These IDs are
stable across renders as long as the source does not move: the
same call site produces the same ID on every render, so the diff
matches children in place.

Auto-IDs are **unstable across code changes**. A refactor that
moves a call to a different line regenerates its ID, invalidating
any state or test selector that referenced it. Interactive and
stateful widgets require explicit string IDs for this reason. See
[Scoped IDs](scoped-ids.md) for the full rules.

## Windows

`window(id, **props, &block)` is the top-level container. It is
the only DSL method that is always explicitly rooted: `view` must
return at least one window node or an array of window nodes.
Widgets at the top level raise during normalisation.

```ruby
def view(model)
  window("main", title: "Notes") do
    column { text("title", model.title) }
  end
end

def view(model)
  [
    window("main",  title: "Main"),
    window("prefs", title: "Preferences", width: 480)
  ]
end
```

Per-window props (`title:`, `size:`, `position:`, `theme:`,
`resizable:`, and the rest) live on the `window` call. See the
[Windows and Layout reference](windows-and-layout.md) for the
full set.

## Container methods

Container methods collect children from their block and construct a
single `Node`. The call form is:

```ruby
column(id = nil, **props) do
  # children appended to the current context
end
```

Every container follows the same pattern: push a fresh child list,
run the block, pop the list, wrap it in a `Node`. Children append
themselves to the current context as a side effect of being called,
so `column do ... end` does not need to collect return values
manually. Writing `button("save", "Save")` inside a container is
enough to place the button.

Control flow works inline because the DSL does not require a
special array-return shape:

```ruby
column do
  text("title", "Inbox")
  rule if model.messages.any?
  model.messages.each do |msg|
    text(msg.id, msg.body)
  end
  text("empty", "No messages") if model.messages.empty?
end
```

## Leaf methods

Leaf methods build a `Node` with no children and append it to the
current context:

```ruby
button("save", "Save", style: :primary)
text("greeting", "Hello")
text_input("email", model.email, placeholder: "you@example.com")
```

Leaf methods still return the node they construct, so the same call
works outside a container:

```ruby
node = button("save", "Save")  # returned, not appended
```

This matters for the typed builder escape hatch below and for
programmatic construction in helper methods.

## memo

`memo(deps) { subtree }` caches a normalised subtree across renders.
When `deps` compares equal (via `==`) to the previous render's value
for the same call site, the cached node is reused and the block
never runs:

```ruby
column do
  memo(model.sidebar_version) do
    render_sidebar(model)
  end

  memo([model.view, model.filter]) do
    render_body(model)
  end
end
```

The call inserts a placeholder node with `type: "__memo__"` and
metadata pointing at the dep value and the block. During
`Plushie::Tree.normalize`, memo nodes are expanded: on a cache hit
the previous normalised result is reused directly; on a miss the
block runs, the result is normalised, and the new result is cached.

The memo site is identified by `block.source_location`, so two
memos on the same line would collide. Keep each `memo` call on its
own source line.

For dynamic lists, include the item key in `deps` so each row gets
its own cache entry:

```ruby
keyed_column do
  model.items.each do |item|
    memo([item.id, item.version]) do
      render_item(item)
    end
  end
end
```

`Plushie::UI::MemoCache` is a thread-local pair of hashes managed
by the runtime:

| Method | Purpose |
|---|---|
| `MemoCache.seed(cache)` | Runtime seeds the previous cache before normalise |
| `MemoCache.prev` | Current normalisation reads from this |
| `MemoCache.current` | Accumulates the new cache during normalise |
| `MemoCache.capture` | Runtime captures `current` as `prev` for the next render |

The runtime swaps these each render, so memo entries persist exactly
one render at a time. Cache entries that were not reused during a
render are dropped, keeping memory bounded.

## Canvas DSL

Canvas widgets are containers whose children are shape nodes. The
DSL nests three scopes: `canvas`, `layer`, and either `canvas_group`
or `canvas_interactive`.

```ruby
canvas("chart", width: 400, height: 300) do
  layer("grid") do
    canvas_rect(0, 0, 400, 300, stroke: "#eee")
  end

  layer("data") do
    canvas_group(x: 200, y: 150) do
      canvas_circle(0, 0, 40, fill: "#07f")
    end
    canvas_interactive("reset", on_click: true, cursor: "pointer") do
      canvas_rect(350, 10, 40, 20, fill: "#888", radius: 4)
      canvas_text(370, 24, "x", color: "#fff", align: :center)
    end
  end
end
```

`layer(name)` produces a node with `type: "__layer__"` keyed by the
layer name. Each layer maps to a separate cache on the renderer
side, so a shape change in one layer does not invalidate the
others.

`canvas_group(x:, y:, transforms:, ...)` is a structural group with
shared transforms and clipping. It takes no required ID; one is
generated from a thread-local counter.

`canvas_interactive(id, on_click:, on_hover:, draggable:, cursor:,
a11y:, ...)` is the interactive variant. It requires an explicit
ID for hit testing, focus tracking, and a11y. Both variants encode
as `type: "group"` on the wire; the distinction is API-level.

Shape leaves (`canvas_rect`, `canvas_circle`, `canvas_line`,
`canvas_text`, `canvas_path`, `canvas_image`, `canvas_svg`) follow
the same context-stack pattern as any leaf method: they build a
node and append it to the current layer or group.

### Canvas auto-IDs

Structural groups and shape leaves use a monotonic thread-local
counter rather than source locations:

```ruby
def _plushie_canvas_counter
  Thread.current[:_plushie_canvas_counter] =
    (Thread.current[:_plushie_canvas_counter] || 0) + 1
end
```

The runtime resets this counter to `0` before each `view` call, so
a given canvas DSL that runs the same code path produces the same
shape IDs on every render, which is what the diff needs to see
"this is the same rectangle, not a new one." The counter is
separate from the source-location auto-ID scheme because canvas
shapes are often produced in loops where every iteration would share
a caller line.

See the [Canvas reference](canvas.md) for the full shape vocabulary
and event model.

## Table DSL

Tables support two row construction paths that are mutually
exclusive. The block form uses `table_row` and `cell` for rich
cells containing arbitrary widgets:

```ruby
cols = [
  { key: "name",    label: "Name", sortable: true, width: :fill },
  { key: "email",   label: "Email" },
  { key: "actions", label: "" }
]

table("users", columns: cols) do
  model.users.each do |user|
    table_row(user.id) do
      cell("name",    text("name-#{user.id}", user.name))
      cell("email",   text("email-#{user.id}", user.email))
      cell("actions", button("del-#{user.id}", "Delete"))
    end
  end
end
```

`table_row(id, **props, &block)` is a plain container keyed by the
row ID. `cell(column_key, content_or_props, **props, &block)` binds
its content to a column by key; the key defaults to the first
positional argument. A single-node shorthand passes the child
directly as the second positional argument (`cell("name",
text(...))`); the block form applies when a cell contains multiple
widgets.

The data shorthand passes `rows:` directly for simple text-only
tables; the builder expands each hash into row and cell nodes at
build time. Setting both `rows:` and a block raises. See the
[Table section in Built-in Widgets](built-in-widgets.md#table).

## Typed builders

Every widget in `Plushie::Widget::*` is also a typed builder class
with chainable setters:

```ruby
node = Plushie::Widget::Button.new("save", "Save")
  .set_style(:primary)
  .set_width(:fill)
  .build

Plushie::Widget::Column.new("list")
  .set_spacing(8)
  .push(Plushie::Widget::Text.new("title", "Inbox").build)
  .push(Plushie::Widget::Button.new("compose", "New").build)
  .build
```

Builders and DSL methods produce the same `Node` shape. They are
interchangeable: a builder's `#build` result can be returned from a
DSL block, and a DSL call can be pushed into a builder.

Prefer the DSL inside `view(model)` for readability. Reach for
builders when:

- Building a subtree in a helper method that runs outside a view
  block (no context stack available).
- Constructing a widget programmatically from data where setters
  are clearer than keyword juggling.
- Writing a custom widget's `self.view(id, props, state)` that
  composes built-in widgets.

A builder instance works without a surrounding context because
`build` returns the node directly rather than appending it. Inside
a view block, `build` still appends to the current context on the
way out, so the result is the same either way.

See the [Custom Widgets reference](custom-widgets.md) for the
`Plushie::Widget.define` macro that produces these builder classes.

## WidgetSet overrides

`Plushie::WidgetSet.create` builds a module that re-exports
`Plushie::UI` with specific DSL methods swapped for custom widget
classes:

```ruby
MaterialButton = Plushie::Widget.define(:button) do
  children :none
  positional :label, default: nil
  prop :label, :style, :disabled, :ripple_color
  default_a11y role: :button, label_from: :label
end

MaterialUI = Plushie::WidgetSet.create(
  button: MaterialButton
)

class MyApp
  include Plushie::App
  include MaterialUI   # overrides `button(...)` everywhere

  def view(_model)
    window("main") do
      button("save", "Save", ripple_color: "#1d4ed8")
    end
  end
end
```

Override classes must expose `new(id, *args, **opts)` and `#build`
returning a `Plushie::Node`. `Plushie::Widget.define` satisfies
both automatically.

The generated override method runs the block through the same
context-stack dance as the built-in method, then calls
`builder.push(child)` for each collected child. Widgets declared
with `children :none` raise when invoked with a block. Naming a
method that `Plushie::UI` does not define raises at creation time.

The `include` order matters: `include MaterialUI` after
`include Plushie::App` lets the override win over the built-in.

## Thread safety

The context stack, memo cache, and canvas counter all live on
`Thread.current`, not on class state:

| Thread-local | Purpose |
|---|---|
| `:_plushie_ctx_stack` | Container child-array stack |
| `:_plushie_memo_prev` / `:_plushie_memo_current` | Memo cache swap |
| `:_plushie_canvas_counter` | Canvas shape and group auto-IDs |

A runtime renders from a single thread, so concurrency inside one
app is not a concern. The thread-local approach matters for:

- Tests that exercise multiple apps in parallel (each test thread
  has its own stack).
- Tooling that snapshots trees or runs view-only helpers outside a
  live runtime (no state leaks between callers).
- Isolation if a future runtime variant ever renders multiple apps
  in one process.

The runtime resets the canvas counter before every `view` call and
seeds the memo cache, so the DSL is ready to use from a fresh state
each render.

## See also

- [Built-in Widgets](built-in-widgets.md) - the full widget catalog,
  prop tables, and per-widget call forms
- [Scoped IDs](scoped-ids.md) - how auto-IDs and explicit IDs
  compose through container scopes
- [Custom Widgets](custom-widgets.md) - `Plushie::Widget.define`,
  the typed builder macro, and `Plushie::CanvasWidget`
- [App Lifecycle](app-lifecycle.md) - `Plushie::App`, the required
  callbacks, and startup sequencing
