# frozen_string_literal: true

require "test_helper"

class DocsTestingDocTest < Minitest::Test
  # -- Todo app for unit test examples from testing.md --

  class MyApp
    include Plushie::App

    Model = Plushie::Model.define(:todos, :input)

    def init(_opts) = Model.new(todos: [], input: "")

    def update(model, event)
      case event
      in Event::Widget[type: :click, id: "add_todo"]
        if model.input.strip != ""
          todo = {text: model.input, done: false}
          model.with(todos: model.todos + [todo], input: "")
        else
          model
        end

      in Event::Widget[type: :submit, id: "todo_input", value:]
        if value.strip != ""
          todo = {text: value, done: false}
          new_model = model.with(todos: model.todos + [todo], input: "")
          [new_model, Command.focus("todo_input")]
        else
          model
        end

      in Event::Widget[type: :input, id: "todo_input", value:]
        model.with(input: value)

      else
        model
      end
    end

    def view(model)
      window("main", title: "Todos") do
        column("app", padding: 16, spacing: 8) do
          text_input("todo_input", model.input, placeholder: "Add a todo...")

          button("add_todo", "Add")

          text("todo_count", "#{model.todos.length} item#{model.todos.length == 1 ? "" : "s"}")

          column("list", spacing: 4) do
            model.todos.each_with_index do |todo, i|
              text("todo_#{i}", todo[:text])
            end
          end
        end
      end
    end
  end

  # -- Testing update: adding a todo appends and clears input --

  def test_adding_a_todo_appends_and_clears_input
    model = MyApp::Model.new(todos: [], input: "Buy milk")
    model = MyApp.new.update(model, Plushie::Event::Widget.new(type: :click, id: "add_todo"))

    assert_equal "Buy milk", model.todos.first[:text]
    refute model.todos.first[:done]
    assert_equal "", model.input
  end

  # -- Testing commands: submit returns focus --

  def test_submitting_todo_refocuses_the_input
    model = MyApp::Model.new(todos: [], input: "Buy milk")
    model, cmd = MyApp.new.update(model, Plushie::Event::Widget.new(type: :submit, id: "todo_input", value: "Buy milk"))

    assert_equal "Buy milk", model.todos.first[:text]
    assert_equal :focus, cmd.type
    assert_equal "todo_input", cmd.payload[:target]
  end

  # -- Testing view: tree structure --

  def test_view_shows_todo_count
    model = MyApp::Model.new(todos: [{text: "Buy milk", done: false}], input: "")
    tree = Plushie::Tree.normalize(MyApp.new.view(model))

    counter = Plushie::Tree.find(tree, "app/todo_count")
    refute_nil counter
    assert_includes counter.props[:content], "1"
  end

  def test_view_shows_zero_when_empty
    model = MyApp::Model.new(todos: [], input: "")
    tree = Plushie::Tree.normalize(MyApp.new.view(model))

    counter = Plushie::Tree.find(tree, "app/todo_count")
    refute_nil counter
    assert_includes counter.props[:content], "0"
  end

  # -- Tree query helpers from testing.md --

  def test_tree_find_by_id
    model = MyApp.new.init({})
    tree = Plushie::Tree.normalize(MyApp.new.view(model))

    node = Plushie::Tree.find(tree, "app/add_todo")
    refute_nil node
    assert_equal "button", node.type
  end

  def test_tree_exists
    model = MyApp.new.init({})
    tree = Plushie::Tree.normalize(MyApp.new.view(model))

    assert Plushie::Tree.exists?(tree, "app/add_todo")
    refute Plushie::Tree.exists?(tree, "nonexistent_widget")
  end

  def test_tree_ids
    model = MyApp.new.init({})
    tree = Plushie::Tree.normalize(MyApp.new.view(model))

    all_ids = Plushie::Tree.ids(tree)
    assert_includes all_ids, "main"
    assert_includes all_ids, "app/add_todo"
    assert_includes all_ids, "app/todo_count"
  end

  def test_tree_find_all_by_predicate
    model = MyApp::Model.new(
      todos: [{text: "Buy milk", done: false}, {text: "Walk dog", done: false}],
      input: ""
    )
    tree = Plushie::Tree.normalize(MyApp.new.view(model))

    buttons = Plushie::Tree.find_all(tree) { |node| node.type == "button" }
    refute_empty buttons
    assert(buttons.all? { |n| n.type == "button" })
  end

  # -- Init returns valid initial state --

  def test_init_returns_valid_initial_state
    model = MyApp.new.init({})

    assert_kind_of Array, model.todos
    assert_equal "", model.input
  end
end
