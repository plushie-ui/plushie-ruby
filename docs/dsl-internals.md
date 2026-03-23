# DSL internals

Maintainer and extension author guide to the Plushie UI DSL. This covers
the runtime architecture, how blocks are evaluated, and how to add new
widgets and type structs that participate in the DSL.

For user-facing DSL documentation, see the `Plushie::UI` module docs.

## How the DSL works

The DSL is three layers that compose bottom-up:

### Widget structs (data layer)

`Plushie::Widget::*` modules define typed builders for each widget.
`Plushie::Type::*` modules define shared property types (padding, border,
color, font, etc.). `Plushie::Canvas::Shape::*` modules define canvas shape
types. Each builder carries its valid fields, default values, and type
metadata.

### Builder methods (construction layer)

Every widget module exposes `new(id, opts)` (or `new(id, content, opts)`
for widgets with positional args like `Button.new("id", "label", opts)`),
`with_options(opts)`, and `build`. Type modules expose `from_opts(opts)`.
Canvas shapes expose builder methods like `Shape.rect(x, y, w, h, opts)`.
These are plain methods -- no metaprogramming. They can be called anywhere.

### Block-based DSL (DSL layer)

`Plushie::UI` methods provide ergonomic block syntax. They use a
thread-local context stack to collect children during block evaluation.
The methods handle:

- Auto-ID generation from call-site file and line number
- Block-form option parsing
- Container child collection (flattening arrays, filtering nils)
- Canvas context validation
- Option key validation with helpful error messages

The key design constraint: DSL methods produce the same `Node` objects as
calling builder methods directly. The DSL is sugar, not a separate
representation.

## Thread-local context stack

Unlike Elixir's macro-based DSL (which rewrites the AST at compile time),
Ruby's DSL uses a thread-local stack at runtime. This is the fundamental
mechanism:

```ruby
# Simplified conceptual model
module Plushie::UI
  def column(id = nil, **opts, &block)
    node = Widget::Column.new(id || auto_id, opts)

    if block
      # Push a new children collector onto the thread-local stack
      Thread.current[:plushie_dsl_stack] ||= []
      Thread.current[:plushie_dsl_stack].push([])

      begin
        # Evaluate the block -- child DSL calls push onto the stack
        instance_exec(&block)
        children = Thread.current[:plushie_dsl_stack].pop
      ensure
        # ensure cleanup even if the block raises
        Thread.current[:plushie_dsl_stack].pop if Thread.current[:plushie_dsl_stack].last == children
      end

      node = node.with_children(children.flatten.compact)
    end

    # Push this node onto the parent's children collector
    push_node(node.build)
  end

  private

  def push_node(node)
    stack = Thread.current[:plushie_dsl_stack]
    if stack && !stack.empty?
      stack.last << node
    end
    node
  end
end
```

### Why thread-local, not instance variables

Thread-local storage ensures DSL evaluation is safe in concurrent contexts.
Each thread gets its own stack, so multiple views can be rendered in parallel
(e.g. in test suites) without interference. Instance variables would require
the DSL module to maintain state on the including class, which creates
coupling and concurrency issues.

### Why not instance_eval

The DSL does **not** use `instance_eval` for block evaluation. Instead,
blocks are evaluated via `instance_exec` in the context of the app instance
(the object that includes `Plushie::App`). This means:

- You have access to the app's private methods from within blocks
- `self` inside a block is the app instance, not a DSL context object
- Helper methods like `filtered_todos(model)` work naturally

```ruby
def view(model)
  window("main") do
    column do
      # This calls a private method on the app -- works because
      # the block runs in the app's context
      filtered_todos(model).each do |todo|
        text(todo.text)
      end
    end
  end
end

private

def filtered_todos(model)
  # ...
end
```

## Ensure cleanup

The DSL stack uses `ensure` blocks to guarantee cleanup even when exceptions
occur inside blocks. Without this, an exception would leave stale entries on
the stack, corrupting subsequent renders:

```ruby
begin
  instance_exec(&block)
ensure
  # Always pop, even if the block raised
  Thread.current[:plushie_dsl_stack]&.pop
end
```

This is critical for error recovery. The runtime catches exceptions in
`view` and re-renders with the previous model. If the stack wasn't cleaned
up, the next render would inherit orphaned children from the failed render.

## Auto-IDs

When a widget builder is called without an explicit ID, it generates one
from the call site:

```ruby
def auto_id
  loc = caller_locations(2, 1)&.first
  "auto:#{loc&.path}:#{loc&.lineno}"
end
```

Auto-IDs are stable across re-renders (same file + line = same ID) but
do not create scopes. This matches the Elixir SDK's behaviour where
auto-IDs pass through without adding to the scope chain.

## How containers collect children

When a container's block contains both option declarations and children,
the DSL partitions them at runtime:

1. **Option recognition.** Certain method calls inside blocks are recognized
   as option setters rather than children. For example, `spacing 8` inside
   a `column` block sets the spacing option.

2. **Child collection.** Everything else (widget calls, loops, conditionals)
   produces child nodes that are collected on the thread-local stack.

3. **Merge.** Block-form options are merged over keyword options from the
   call line. Block values win on conflict.

```ruby
# Both produce the same result:
column(spacing: 16, padding: 8) do
  text("hello")
end

column do
  spacing 16
  padding 8
  text("hello")
end
```

## Adding a new widget

### 1. Create the builder module

Create `lib/plushie/widget/my_widget.rb`:

```ruby
module Plushie
  module Widget
    class MyWidget
      OPTION_KEYS = %i[width height some_prop a11y].freeze

      attr_reader :id, :some_prop, :width, :height, :a11y

      def initialize(id, opts = {})
        @id = id
        @some_prop = opts[:some_prop]
        @width = opts[:width]
        @height = opts[:height]
        @a11y = opts[:a11y]
      end

      def build
        props = {}
        props[:some_prop] = @some_prop if @some_prop
        props[:width] = @width if @width
        props[:height] = @height if @height
        Node.new(id: @id, type: "my_widget", props: props, children: [])
      end
    end
  end
end
```

### 2. Add a DSL method to Plushie::UI

For a **leaf widget** (no children):

```ruby
def my_widget(id, **opts)
  node = Widget::MyWidget.new(id, opts).build
  push_node(node)
end
```

For a **container widget** (has children):

```ruby
def my_widget(id = nil, **opts, &block)
  # ... follow the column/row pattern with stack push/pop
end
```

### 3. Register

Add the new DSL method to the `Plushie::UI` module and ensure it's
available when `include Plushie::App` is used.

## Adding a new type struct

Type structs represent complex property values (padding, border, font,
shadow, etc.).

### 1. Create the type module

```ruby
module Plushie
  module Type
    class MyType
      attr_reader :field_a, :field_b

      def initialize(field_a: nil, field_b: nil)
        @field_a = field_a
        @field_b = field_b
      end

      def self.from_opts(opts)
        new(**opts.slice(:field_a, :field_b))
      end

      def to_encode
        h = {}
        h["field_a"] = @field_a if @field_a
        h["field_b"] = @field_b if @field_b
        h
      end
    end
  end
end
```

### 2. Add the Encode implementation

Register the type with `Plushie::Encode` so it serializes correctly:

```ruby
Plushie::Encode.register(Plushie::Type::MyType) do |obj|
  obj.to_encode
end
```

## Control flow in blocks

### Multi-expression bodies

Unlike Elixir (where blocks evaluate to their last expression), Ruby
blocks naturally collect all values when each DSL call pushes onto the
stack. There is no multi-expression problem in Ruby -- every `text(...)`,
`button(...)`, etc. call inside a block independently pushes its node.

```ruby
column do
  if show_header?
    text("Title")      # pushes to stack
    text("Subtitle")   # also pushes to stack -- both appear
  end
end
```

### Loops

`each` and `map` work naturally:

```ruby
column do
  items.each do |item|
    text(item.name)
  end
end
```

### Conditionals

`if` without `else` returns `nil`, which the DSL filters out:

```ruby
column do
  text("Always here")
  text("Conditional") if model.show_extra  # nil when false, filtered out
end
```

## Prop override semantics

When both keyword arguments on the call line and block-form declarations
specify the same option, the block-form value wins:

```ruby
column(spacing: 8) do
  spacing 16         # overrides the keyword arg -- spacing is 16
  text("hello")
end
```
