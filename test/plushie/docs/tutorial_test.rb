# frozen_string_literal: true

require "test_helper"

class DocsTutorialTest < Minitest::Test
  # -- Todo app reproduced from tutorial.md --

  class Todo
    include Plushie::App

    Model = Plushie::Model.define(:todos, :input, :filter, :next_id)

    def init(_opts)
      Model.new(todos: [], input: "", filter: :all, next_id: 1)
    end

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

    # Step 1 view (title + placeholder only)
    def step1_view(model)
      window("main", title: "Todos") do
        column("app", padding: 20, spacing: 12, width: :fill) do
          text("title", "My Todos", size: 24)
          text("empty", "No todos yet")
        end
      end
    end

    # Step 3 view (input + todo list, no filters)
    def step3_view(model)
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

    # Full view (step 6 -- filters + extracted helpers)
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

    def filtered(model)
      case model.filter
      when :all then model.todos
      when :active then model.todos.reject { |t| t[:done] }
      when :done then model.todos.select { |t| t[:done] }
      end
    end

    private

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

  def setup
    @app = Todo.new
  end

  # -- Step 1: init and initial view --

  def test_tutorial_step1_init
    model = @app.init({})
    assert_equal [], model.todos
    assert_equal "", model.input
    assert_equal :all, model.filter
    assert_equal 1, model.next_id
  end

  # -- Step 2: input handling --

  def test_tutorial_step2_input_updates_model
    model = @app.init({})
    model = @app.update(model, Plushie::Event::Widget.new(type: :input, id: "new_todo", value: "Buy milk"))
    assert_equal "Buy milk", model.input
  end

  def test_tutorial_step2_submit_creates_todo
    model = @app.init({})
    model = @app.update(model, Plushie::Event::Widget.new(type: :input, id: "new_todo", value: "Buy milk"))
    model, cmd = @app.update(model, Plushie::Event::Widget.new(type: :submit, id: "new_todo"))

    assert_equal "", model.input
    assert_equal 2, model.next_id
    assert_equal 1, model.todos.length
    assert_equal "Buy milk", model.todos.first[:text]
    assert_equal "todo_1", model.todos.first[:id]
    assert_equal false, model.todos.first[:done]
    assert_equal :focus, cmd.type
  end

  def test_tutorial_step2_empty_submit_noop
    model = @app.init({})
    model = @app.update(model, Plushie::Event::Widget.new(type: :input, id: "new_todo", value: "   "))
    result = @app.update(model, Plushie::Event::Widget.new(type: :submit, id: "new_todo"))
    assert_equal model, result
    assert_equal [], result.todos
  end

  # -- Step 3: rendering the list --

  def test_tutorial_step3_view_renders_todo_list
    model = Todo::Model.new(
      todos: [
        {id: "todo_1", text: "Buy milk", done: false},
        {id: "todo_2", text: "Walk dog", done: true}
      ],
      input: "",
      filter: :all,
      next_id: 3
    )

    tree = Plushie::Tree.normalize(@app.step3_view(model)).first
    list_col = Plushie::Tree.find(tree, "app/list")
    refute_nil list_col
    assert_equal "column", list_col.type
    assert_equal 4, list_col.props[:spacing]
    assert_equal 2, list_col.children.length
    assert_equal "app/list/todo_1", list_col.children[0].id
    assert_equal "app/list/todo_2", list_col.children[1].id
  end

  # -- Step 4: toggle and delete with scope --

  def test_tutorial_step4_toggle_with_scope
    model = Todo::Model.new(
      todos: [{id: "todo_1", text: "Buy milk", done: false}],
      input: "",
      filter: :all,
      next_id: 2
    )

    model = @app.update(model, Plushie::Event::Widget.new(
      type: :toggle,
      id: "toggle",
      scope: ["todo_1", "list", "app"]
    ))

    assert_equal true, model.todos.first[:done]
  end

  def test_tutorial_step4_delete_with_scope
    model = Todo::Model.new(
      todos: [{id: "todo_1", text: "Buy milk", done: false}],
      input: "",
      filter: :all,
      next_id: 2
    )

    model = @app.update(model, Plushie::Event::Widget.new(
      type: :click,
      id: "delete",
      scope: ["todo_1", "list", "app"]
    ))

    assert_equal [], model.todos
  end

  # -- Step 5: submit returns focus command --

  def test_tutorial_step5_submit_returns_focus_command
    model = Todo::Model.new(todos: [], input: "Buy milk", filter: :all, next_id: 1)
    _model, cmd = @app.update(model, Plushie::Event::Widget.new(type: :submit, id: "new_todo"))

    assert_equal :focus, cmd.type
    assert_equal "app/new_todo", cmd.payload[:target]
  end

  # -- Step 6: filtering --

  def test_tutorial_step6_filter_all
    model = @app.init({})
    model = @app.update(model, Plushie::Event::Widget.new(type: :click, id: "filter_active"))
    assert_equal :active, model.filter
    model = @app.update(model, Plushie::Event::Widget.new(type: :click, id: "filter_all"))
    assert_equal :all, model.filter
  end

  def test_tutorial_step6_filter_done
    model = @app.init({})
    model = @app.update(model, Plushie::Event::Widget.new(type: :click, id: "filter_done"))
    assert_equal :done, model.filter
  end

  def test_tutorial_step6_filtered_helper
    model = Todo::Model.new(
      todos: [
        {id: "todo_1", text: "Buy milk", done: false},
        {id: "todo_2", text: "Walk dog", done: true},
        {id: "todo_3", text: "Read book", done: false}
      ],
      input: "",
      filter: :all,
      next_id: 4
    )

    assert_equal 3, @app.filtered(model).length
    assert_equal 2, @app.filtered(model.with(filter: :active)).length
    assert_equal 1, @app.filtered(model.with(filter: :done)).length
  end
end
