# frozen_string_literal: true

require "test_helper"

class TestNode < Minitest::Test
  def test_creates_with_defaults
    node = Plushie::Node.new(id: "btn", type: "button")
    assert_equal "btn", node.id
    assert_equal "button", node.type
    assert_equal({}, node.props)
    assert_equal [], node.children
  end

  def test_creates_with_props_and_children
    child = Plushie::Node.new(id: "txt", type: "text", props: {content: "hi"})
    parent = Plushie::Node.new(id: "col", type: "column", children: [child])

    assert_equal 1, parent.children.length
    assert_equal "txt", parent.children.first.id
  end

  def test_is_frozen
    node = Plushie::Node.new(id: "x", type: "text")
    assert node.frozen?
    assert node.props.frozen?
    assert node.children.frozen?
  end

  def test_coerces_id_to_string
    node = Plushie::Node.new(id: :foo, type: :bar)
    assert_equal "foo", node.id
    assert_equal "bar", node.type
  end
end
