# frozen_string_literal: true

require "test_helper"
require_relative "../../examples/counter"

class TestCounterExample < Minitest::Test
  def setup
    @app = Counter.new
  end

  def test_init_returns_model_with_zero
    model = @app.init({})
    assert_equal 0, model.count
  end

  def test_increment
    model = @app.init({})
    model = @app.update(model, Plushie::Event::Widget.new(type: :click, id: "increment"))
    assert_equal 1, model.count
  end

  def test_decrement
    model = @app.init({})
    model = @app.update(model, Plushie::Event::Widget.new(type: :click, id: "decrement"))
    assert_equal(-1, model.count)
  end

  def test_unknown_event_returns_model_unchanged
    model = @app.init({})
    model2 = @app.update(model, Plushie::Event::Widget.new(type: :click, id: "unknown"))
    assert_equal model, model2
  end

  def test_view_produces_tree
    model = Counter::Model.new(count: 42)
    tree = @app.view(model)

    assert_equal "window", tree.type
    assert_equal "main", tree.id

    count_node = Plushie::Tree.find(tree, "count")
    refute_nil count_node
    assert_equal "Count: 42", count_node.props[:content]
  end

  def test_view_after_increments
    model = @app.init({})
    3.times { model = @app.update(model, Plushie::Event::Widget.new(type: :click, id: "increment")) }

    tree = @app.view(model)
    count_node = Plushie::Tree.find(tree, "count")
    assert_equal "Count: 3", count_node.props[:content]
  end
end
