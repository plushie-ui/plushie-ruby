# Tutorial: building a todo app

This tutorial walks through building a complete todo app, introducing
one concept per step. By the end you'll understand text inputs,
dynamic lists, scoped IDs, commands, and conditional rendering.

## Step 1: the model

Start with a model that tracks a list of todos and the current input
text.

```ruby
require "plushie"

class Todo
  include Plushie::App

  Model = Plushie::Model.define(:todos, :input, :filter, :next_id)

  def init(_opts)
    Model.new(todos: [], input: "", filter: :all, next_id: 1)
  end

  def update(model, _event) = model

  def view(model)
    window("main", title: "Todos") do
      column("app", padding: 20, spacing: 12, width: :fill) do
        text("title", "My Todos", size: 24)
        text("empty", "No todos yet")
      end
    end
  end
end

Plushie.run(Todo)
```

Run it with `ruby lib/todo.rb`. You'll see a title and a
placeholder message. Not much yet, but the structure is in place:
`init` sets up state, `view` renders it.

## Step 2: adding a text input

Add a text input that updates the model on every keystroke, and a
submit handler that creates a todo when the user presses Enter.

```ruby
def update(model, event)
  case event
  in Event::Widget[type: :input, id: "new_todo", value:]
    model.with(input: value)

  in Event::Widget[type: :submit, id: "new_todo"]
    if model.input.strip != ""
      todo = {id: "todo_#{model.next_id}", text: model.input, done: false}
      model.with(
        todos: [todo] + model.todos,
        input: "",
        next_id: model.next_id + 1
      )
    else
      model
    end

  else
    model
  end
end
```

And the view:

```ruby
def view(model)
  window("main", title: "Todos") do
    column("app", padding: 20, spacing: 12, width: :fill) do
      text("title", "My Todos", size: 24)

      text_input("new_todo", model.input,
        placeholder: "What needs doing?",
        on_submit: true)
    end
  end
end
```

Type something and press Enter. The input clears (the model's
`input` resets to `""`), but you can't see the todos yet. Let's
fix that.

## Step 3: rendering the list with scoped IDs

Each todo needs its own row with a checkbox and a delete button.
We wrap each item in a named container using the todo's ID. This
creates a **scope** -- children get unique IDs automatically
without manual prefixing.

```ruby
def view(model)
  window("main", title: "Todos") do
    column("app", padding: 20, spacing: 12, width: :fill) do
      text("title", "My Todos", size: 24)

      text_input("new_todo", model.input,
        placeholder: "What needs doing?",
        on_submit: true)

      column("list", spacing: 4) do
        model.todos.each do |todo|
          container(todo[:id]) do
            row(spacing: 8) do
              checkbox("toggle", todo[:done])
              text(todo[:text])
              button("delete", "x")
            end
          end
        end
      end
    end
  end
end
```

Each todo row has `id: todo[:id]` (e.g., `"todo_1"`). Inside it,
the checkbox has local id `"toggle"` and the button has `"delete"`.
On the wire, these become `"list/todo_1/toggle"` and
`"list/todo_1/delete"` -- unique across all items.

## Step 4: handling toggle and delete with scope

When the checkbox or delete button is clicked, the event carries the
local `id` and a `scope` array with the todo's container ID as the
immediate parent. Pattern match on both:

```ruby
in Event::Widget[type: :toggle, id: "toggle", scope: [todo_id, *]]
  todos = model.todos.map { |t|
    (t[:id] == todo_id) ? t.merge(done: !t[:done]) : t
  }
  model.with(todos: todos)

in Event::Widget[type: :click, id: "delete", scope: [todo_id, *]]
  model.with(todos: model.todos.reject { |t| t[:id] == todo_id })
```

The `scope: [todo_id, *]` pattern binds the immediate parent's ID
(e.g., `"todo_1"`) regardless of how deep the row is nested. If you
later move the list into a sidebar or tab, the pattern still works.

## Step 5: refocusing with a command

After submitting a todo, the text input loses focus. Let's refocus
it automatically using `Command.focus`:

```ruby
in Event::Widget[type: :submit, id: "new_todo"]
  if model.input.strip != ""
    todo = {id: "todo_#{model.next_id}", text: model.input, done: false}
    new_model = model.with(
      todos: [todo] + model.todos,
      input: "",
      next_id: model.next_id + 1
    )
    [new_model, Command.focus("app/new_todo")]
  else
    model
  end
```

Note the scoped path `"app/new_todo"` -- the text input is inside
the `"app"` column, so its full ID is `"app/new_todo"`. Commands
always use the full scoped path.

## Step 6: filtering

Add filter buttons that toggle between all, active, and completed
todos.

```ruby
in Event::Widget[type: :click, id: "filter_all"]
  model.with(filter: :all)
in Event::Widget[type: :click, id: "filter_active"]
  model.with(filter: :active)
in Event::Widget[type: :click, id: "filter_done"]
  model.with(filter: :done)
```

Add the filter buttons and apply the filter in the view:

```ruby
def view(model)
  window("main", title: "Todos") do
    column("app", padding: 20, spacing: 12, width: :fill) do
      text("title", "My Todos", size: 24)

      text_input("new_todo", model.input,
        placeholder: "What needs doing?",
        on_submit: true)

      row(spacing: 8) do
        button("filter_all", "All")
        button("filter_active", "Active")
        button("filter_done", "Done")
      end

      column("list", spacing: 4) do
        filtered(model).each { |todo| todo_row(todo) }
      end
    end
  end
end

private

def filtered(model)
  case model.filter
  when :all    then model.todos
  when :active then model.todos.reject { |t| t[:done] }
  when :done   then model.todos.select { |t| t[:done] }
  end
end

def todo_row(todo)
  container(todo[:id]) do
    row(spacing: 8) do
      checkbox("toggle", todo[:done])
      text(todo[:text])
      button("delete", "x")
    end
  end
end
```

Notice `todo_row` is extracted as a view helper. Because
`Plushie::App` includes the UI DSL as instance methods, private
helpers can call widget methods directly -- no extra imports needed.

## The complete app

The full source is in
[`examples/todo.rb`](https://github.com/plushie-ui/plushie-ruby/blob/main/examples/todo.rb).

```ruby
require "plushie"

class Todo
  include Plushie::App

  Model = Plushie::Model.define(:todos, :input, :filter, :next_id)

  # -- Init -----------------------------------------------------------------

  def init(_opts)
    Model.new(todos: [], input: "", filter: :all, next_id: 1)
  end

  # -- Update ---------------------------------------------------------------

  def update(model, event)
    case event
    in Event::Widget[type: :input, id: "new_todo", value:]
      model.with(input: value)

    in Event::Widget[type: :submit, id: "new_todo"]
      if model.input.strip != ""
        todo = {id: "todo_#{model.next_id}", text: model.input, done: false}
        new_model = model.with(
          todos: [todo] + model.todos,
          input: "",
          next_id: model.next_id + 1
        )
        [new_model, Command.focus("app/new_todo")]
      else
        model
      end

    in Event::Widget[type: :toggle, id: "toggle", scope: [todo_id, *]]
      todos = model.todos.map { |t|
        (t[:id] == todo_id) ? t.merge(done: !t[:done]) : t
      }
      model.with(todos: todos)

    in Event::Widget[type: :click, id: "delete", scope: [todo_id, *]]
      model.with(todos: model.todos.reject { |t| t[:id] == todo_id })

    in Event::Widget[type: :click, id: "filter_all"]
      model.with(filter: :all)
    in Event::Widget[type: :click, id: "filter_active"]
      model.with(filter: :active)
    in Event::Widget[type: :click, id: "filter_done"]
      model.with(filter: :done)

    else
      model
    end
  end

  # -- View -----------------------------------------------------------------

  def view(model)
    window("main", title: "Todos") do
      column("app", padding: 20, spacing: 12, width: :fill) do
        text("title", "My Todos", size: 24)

        text_input("new_todo", model.input,
          placeholder: "What needs doing?",
          on_submit: true)

        row(spacing: 8) do
          button("filter_all", "All")
          button("filter_active", "Active")
          button("filter_done", "Done")
        end

        column("list", spacing: 4) do
          filtered(model).each { |todo| todo_row(todo) }
        end
      end
    end
  end

  private

  def filtered(model)
    case model.filter
    when :all    then model.todos
    when :active then model.todos.reject { |t| t[:done] }
    when :done   then model.todos.select { |t| t[:done] }
    end
  end

  def todo_row(todo)
    container(todo[:id]) do
      row(spacing: 8) do
        checkbox("toggle", todo[:done])
        text(todo[:text])
        button("delete", "x")
      end
    end
  end
end

Plushie.run(Todo)
```

## What you've learned

- **Text inputs** with `on_submit: true` for form-like behavior
- **Scoped IDs** via named containers (`container(todo[:id])`)
- **Scope binding** in update (`scope: [todo_id, *]`)
- **Commands** for side effects (`Command.focus` with scoped paths)
- **Conditional rendering** with filter functions
- **View helpers** extracted as private methods

## Next steps

- [Commands](commands.md) -- async work, file dialogs, timers
- [Scoped IDs](scoped-ids.md) -- full scoping reference
- [Composition patterns](composition-patterns.md) -- scaling beyond
  a single class
- [Testing](testing.md) -- unit and integration testing
