# frozen_string_literal: true

require "plushie"

# To-do list with add, toggle, delete, and filter.
#
# Demonstrates:
# - text_input with on_submit for keyboard-driven entry
# - Scoped IDs via named containers for dynamic list items
# - Scope binding in update for item-level events
# - Command.focus with scoped paths for refocusing
# - Filter buttons with conditional list rendering
class Todo
  include Plushie::App

  Model = Plushie::Model.define(:todos, :input, :filter, :next_id)
  TodoItem = Plushie::Model.define(:id, :text, :done)

  def init(_opts)
    Model.new(todos: [], input: "", filter: :all, next_id: 1)
  end

  def update(model, event)
    case event
    in Event::Widget[type: :input, id: "new_todo", value:]
      model.with(input: value)

    in Event::Widget[type: :submit, id: "new_todo"]
      return model if model.input.strip.empty?

      todo = TodoItem.new(id: "todo_#{model.next_id}", text: model.input, done: false)
      model = model.with(
        todos: [todo, *model.todos],
        input: "",
        next_id: model.next_id + 1
      )
      [model, Command.focus("app/new_todo")]

    in Event::Widget[type: :toggle, id: "toggle", scope: [todo_id, *]]
      todos = model.todos.map do |t|
        (t.id == todo_id) ? t.with(done: !t.done) : t
      end
      model.with(todos: todos)

    in Event::Widget[type: :click, id: "delete", scope: [todo_id, *]]
      model.with(todos: model.todos.reject { |t| t.id == todo_id })

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
          filtered(model).each do |todo|
            todo_row(todo)
          end
        end
      end
    end
  end

  private

  def filtered(model)
    case model.filter
    when :all then model.todos
    when :active then model.todos.reject(&:done)
    when :done then model.todos.select(&:done)
    end
  end

  def todo_row(todo)
    container(todo.id) do
      row(spacing: 8) do
        checkbox("toggle", todo.done)
        text(todo.text)
        button("delete", "x")
      end
    end
  end
end
