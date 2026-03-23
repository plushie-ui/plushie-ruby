# frozen_string_literal: true

require "test_helper"

class DocsAppBehaviourTest < Minitest::Test
  # -- App reproduced from app-behaviour.md --

  class TodoApp
    include Plushie::App

    Model = Plushie::Model.define(:todos, :input, :filter, :loading, :auto_refresh)

    def init(_opts)
      Model.new(todos: [], input: "", filter: :all, loading: false, auto_refresh: false)
    end

    def init_with_command(_opts)
      model = Model.new(todos: [], input: "", filter: :all, loading: true, auto_refresh: false)
      [model, Command.async(-> { [] }, :todos_loaded)]
    end

    def update(model, event)
      case event
      in Event::Widget[type: :click, id: "add_todo"]
        new_todo = {id: "t1", text: model.input, done: false}
        model.with(todos: [new_todo] + model.todos, input: "")

      in Event::Widget[type: :submit, id: "todo_field"]
        new_todo = {id: "t1", text: model.input, done: false}
        updated = model.with(todos: [new_todo] + model.todos, input: "")
        [updated, Command.focus("todo_field")]

      else
        model
      end
    end

    def subscribe(model)
      subs = [Subscription.on_key_press(:key_event)]

      if model.auto_refresh
        [Subscription.every(5000, :refresh)] + subs
      else
        subs
      end
    end

    def view(model)
      window("main", title: "Todos") do
        column(padding: 16, spacing: 8) do
          row(spacing: 8) do
            text_input("todo_field", model.input, placeholder: "What needs doing?")
            button("add_todo", "Add")
          end
        end
      end
    end

    def window_config(_model)
      {
        title: "My App",
        width: 800,
        height: 600,
        min_size: {width: 400, height: 300},
        resizable: true,
        theme: :dark
      }
    end

    def settings
      {
        default_font: {family: "monospace"},
        default_text_size: 16,
        antialiasing: true,
        fonts: ["priv/fonts/Inter.ttf"]
      }
    end
  end

  def setup
    @app = TodoApp.new
  end

  # -- init --

  def test_app_behaviour_init_bare_model
    model = @app.init({})
    assert_equal [], model.todos
    assert_equal "", model.input
    assert_equal :all, model.filter
    assert_equal false, model.loading
  end

  def test_app_behaviour_init_with_command
    model, cmd = @app.init_with_command({})
    assert_equal true, model.loading
    assert_equal :async, cmd.type
    assert_equal :todos_loaded, cmd.payload[:tag]
  end

  # -- update --

  def test_app_behaviour_update_add_todo
    model = @app.init({})
    model = model.with(input: "Buy milk")
    model = @app.update(model, Plushie::Event::Widget.new(type: :click, id: "add_todo"))

    assert_equal 1, model.todos.length
    assert_equal "Buy milk", model.todos.first[:text]
    assert_equal "", model.input
  end

  def test_app_behaviour_update_submit_returns_focus
    model = @app.init({})
    model = model.with(input: "Buy milk")
    model, cmd = @app.update(model, Plushie::Event::Widget.new(type: :submit, id: "todo_field"))

    assert_equal :focus, cmd.type
    assert_equal "todo_field", cmd.payload[:target]
    assert_equal "", model.input
  end

  # -- subscribe --

  def test_app_behaviour_subscribe_without_auto_refresh
    model = @app.init({})
    subs = @app.subscribe(model)

    assert_equal 1, subs.length
    assert_equal :on_key_press, subs.first.type
    assert_equal :key_event, subs.first.tag
  end

  def test_app_behaviour_subscribe_with_auto_refresh
    model = @app.init({}).with(auto_refresh: true)
    subs = @app.subscribe(model)

    assert_equal 2, subs.length
    timer = subs.find { |s| s.type == :every }
    refute_nil timer
    assert_equal 5000, timer.interval
    assert_equal :refresh, timer.tag
  end

  # -- view --

  def test_app_behaviour_view_basic_structure
    model = @app.init({})
    tree = Plushie::Tree.normalize(@app.view(model)).first

    assert_equal "window", tree.type
    assert_equal "main", tree.id
    assert_equal "Todos", tree.props[:title]
  end

  # -- window_config --

  def test_app_behaviour_window_config
    config = @app.window_config(nil)

    assert_equal "My App", config[:title]
    assert_equal 800, config[:width]
    assert_equal 600, config[:height]
    assert_equal true, config[:resizable]
    assert_equal :dark, config[:theme]
    assert_equal({width: 400, height: 300}, config[:min_size])
  end

  # -- settings --

  def test_app_behaviour_settings
    s = @app.settings

    assert_equal({family: "monospace"}, s[:default_font])
    assert_equal 16, s[:default_text_size]
    assert_equal true, s[:antialiasing]
    assert_equal ["priv/fonts/Inter.ttf"], s[:fonts]
  end
end
