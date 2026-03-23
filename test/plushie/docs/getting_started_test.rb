# frozen_string_literal: true

require "test_helper"

class DocsGettingStartedTest < Minitest::Test
  # -- Counter app reproduced from getting-started.md --

  class Counter
    include Plushie::App

    Model = Plushie::Model.define(:count)

    def init(_opts) = Model.new(count: 0)

    def update(model, event)
      case event
      in Event::Widget[type: :click, id: "increment"]
        model.with(count: model.count + 1)
      in Event::Widget[type: :click, id: "decrement"]
        model.with(count: model.count - 1)
      else
        model
      end
    end

    def view(model)
      window("main", title: "Counter") do
        column(padding: 16, spacing: 8) do
          text("count", "Count: #{model.count}", size: 20)

          row(spacing: 8) do
            button("increment", "+")
            button("decrement", "-")
          end
        end
      end
    end
  end

  # -- Tests --

  def test_getting_started_counter_init
    app = Counter.new
    model = app.init({})
    assert_equal 0, model.count
  end

  def test_getting_started_counter_increment
    app = Counter.new
    model = app.init({})
    model = app.update(model, Plushie::Event::Widget.new(type: :click, id: "increment"))
    assert_equal 1, model.count
  end

  def test_getting_started_counter_decrement
    app = Counter.new
    model = app.init({})
    model = app.update(model, Plushie::Event::Widget.new(type: :click, id: "decrement"))
    assert_equal(-1, model.count)
  end

  def test_getting_started_counter_unknown_event
    app = Counter.new
    model = app.init({})
    model2 = app.update(model, Plushie::Event::Widget.new(type: :click, id: "unknown"))
    assert_equal model, model2
  end

  def test_getting_started_counter_view
    app = Counter.new
    model = app.init({})
    tree = Plushie::Tree.normalize(app.view(model)).first

    assert_equal "window", tree.type
    assert_equal "main", tree.id
    assert_equal "Counter", tree.props[:title]

    column = tree.children.first
    assert_equal "column", column.type
    assert_equal 16, column.props[:padding]
    assert_equal 8, column.props[:spacing]

    text_node, row_node = column.children
    assert_equal "text", text_node.type
    assert_equal "Count: 0", text_node.props[:content]
    assert_equal 20, text_node.props[:size]

    assert_equal "row", row_node.type
    inc, dec = row_node.children
    assert_equal "increment", inc.id
    assert_equal "+", inc.props[:label]
    assert_equal "decrement", dec.id
    assert_equal "-", dec.props[:label]
  end

  def test_getting_started_counter_view_after_increments
    app = Counter.new
    model = app.init({})
    model = app.update(model, Plushie::Event::Widget.new(type: :click, id: "increment"))
    model = app.update(model, Plushie::Event::Widget.new(type: :click, id: "increment"))
    tree = Plushie::Tree.normalize(app.view(model)).first

    column = tree.children.first
    text_node = column.children.first
    assert_equal "Count: 2", text_node.props[:content]
  end
end
