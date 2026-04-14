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

  # -- Search: exact vs suffix matching --------------------------------------

  def test_find_exact_with_window_qualifier
    tree = window("main") do
      column("form") do
        button("save", "Save")
      end
    end
    normalized = Plushie::Tree.normalize_view(tree)

    # Exact match with window#scope/id
    found = Plushie::Tree.find(normalized, "main#form/save")
    refute_nil found
    assert_equal "button", found.type

    # Exact match that doesn't exist
    assert_nil Plushie::Tree.find(normalized, "other#form/save")
  end

  def test_find_suffix_matches_at_boundary
    tree = window("main") do
      button("email", "Email")
      button("remail", "Remail")
    end
    normalized = Plushie::Tree.normalize_view(tree)

    # "email" matches "main#email" (at # boundary)
    found = Plushie::Tree.find(normalized, "email")
    refute_nil found
    assert found.id.end_with?("#email")

    # "remail" should NOT match when searching for "email"
    # because id_matches? requires a # or / boundary
    all = Plushie::Tree.find_all(normalized) { |n| n.id.end_with?("email") }
    emails = all.select { |n| Plushie::Tree.send(:find, [n], "email") }
    assert_equal 1, emails.length
  end

  def test_find_first_returns_first_match
    tree = column("root") do
      button("a", "First")
      button("b", "Second")
    end

    found = Plushie::Tree.find_first(tree) { |n| n.type == "button" }
    refute_nil found
    assert_equal "a", found.id
  end

  def test_find_first_nil_tree
    assert_nil Plushie::Tree.find_first(nil) { |n| n.type == "button" }
  end

  def test_find_all_nil_tree
    assert_equal [], Plushie::Tree.find_all(nil) { |n| n.type == "button" }
  end

  def test_ids_nil_tree
    assert_equal [], Plushie::Tree.ids(nil)
  end

  # -- Normalization: encode_value edge cases --------------------------------

  def test_encode_value_nested_symbols
    tree = Plushie::Node.new(
      id: "test", type: "container",
      props: {style: {base: :primary, hover: {bg: :red}}}
    )
    normalized = Plushie::Tree.normalize(tree).first
    style = normalized.props[:style]
    assert_equal "primary", style["base"]
    assert_equal "red", style["hover"]["bg"]
  end

  def test_encode_value_array_of_symbols
    tree = Plushie::Node.new(
      id: "test", type: "container",
      props: {items: [:one, :two, :three]}
    )
    normalized = Plushie::Tree.normalize(tree).first
    assert_equal %w[one two three], normalized.props[:items]
  end

  def test_encode_value_to_wire_custom_type
    custom = Object.new
    def custom.to_wire = {kind: :custom, data: 42}

    tree = Plushie::Node.new(
      id: "test", type: "container",
      props: {thing: custom}
    )
    normalized = Plushie::Tree.normalize(tree).first
    assert_equal({"kind" => "custom", "data" => 42}, normalized.props[:thing])
  end

  # -- Original tests --------------------------------------------------------

  def test_normalize_detects_canvas_shapes_in_widget_tree
    shape = Plushie::Canvas::Shape.rect(0, 0, 10, 10)
    tree = Plushie::Node.new(id: "root", type: "column", children: [shape])
    assert_raises(ArgumentError) { Plushie::Tree.normalize(tree) }
  end
end
