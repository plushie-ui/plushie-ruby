# frozen_string_literal: true

require "test_helper"

class TestTree < Minitest::Test
  include Plushie::UI

  def test_find_by_id
    tree = column("root") do
      text("greeting", "Hello")
      row("buttons") do
        button("save", "Save")
      end
    end

    node = Plushie::Tree.find(tree, "save")
    refute_nil node
    assert_equal "button", node.type
  end

  def test_find_returns_nil_for_missing
    tree = column("root") do
      text("a", "hi")
    end

    assert_nil Plushie::Tree.find(tree, "nonexistent")
  end

  def test_exists
    tree = text("msg", "hello")
    assert Plushie::Tree.exists?(tree, "msg")
    refute Plushie::Tree.exists?(tree, "other")
  end

  def test_ids
    tree = column("root") do
      text("a", "1")
      text("b", "2")
      row("row") do
        button("c", "3")
      end
    end

    ids = Plushie::Tree.ids(tree)
    assert_equal %w[root a b row c], ids
  end

  def test_find_all
    tree = column("root") do
      button("a", "A")
      text("b", "B")
      button("c", "C")
    end

    buttons = Plushie::Tree.find_all(tree) { |n| n.type == "button" }
    assert_equal 2, buttons.length
    assert_equal %w[a c], buttons.map(&:id)
  end

  def test_normalize_converts_symbols
    tree = text("msg", "hi")
    normalized = Plushie::Tree.normalize(tree)
    # normalize returns an array
    assert_kind_of Array, normalized
    assert_equal 1, normalized.length
  end

  def test_normalize_scopes_a11y_references
    tree = container("form") do
      text("label_node", "Name:")
      text_input("name_input", "", a11y: {labelled_by: "label_node"})
    end
    normalized = Plushie::Tree.normalize(tree).first
    input = Plushie::Tree.find(normalized, "form/name_input")
    refute_nil input
    a11y = input.props["a11y"] || input.props[:a11y]
    # labelled_by should be scoped to "form/label_node"
    assert_equal "form/label_node", a11y["labelled_by"] || a11y[:labelled_by]
  end

  def test_normalize_detects_canvas_shapes_in_widget_tree
    shape = Plushie::Canvas::Shape.rect(0, 0, 10, 10)
    tree = Plushie::Node.new(id: "root", type: "column", children: [shape])
    assert_raises(ArgumentError) { Plushie::Tree.normalize(tree) }
  end
end
