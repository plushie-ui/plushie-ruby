# frozen_string_literal: true

require "test_helper"

class TestUI < Minitest::Test
  include Plushie::UI

  def test_button_creates_node
    node = button("save", "Save")
    assert_equal "save", node.id
    assert_equal "button", node.type
    assert_equal "Save", node.props[:label]
  end

  def test_text_with_explicit_id
    node = text("greeting", "Hello")
    assert_equal "greeting", node.id
    assert_equal "text", node.type
    assert_equal "Hello", node.props[:content]
  end

  def test_text_with_auto_id
    node = text("Hello world")
    assert_match(/\Aauto:/, node.id)
    assert_equal "Hello world", node.props[:content]
  end

  def test_column_with_children_block
    node = column("main", spacing: 8) do
      text("a", "First")
      text("b", "Second")
    end

    assert_equal "column", node.type
    assert_equal 8, node.props[:spacing]
    assert_equal 2, node.children.length
    assert_equal "a", node.children[0].id
    assert_equal "b", node.children[1].id
  end

  def test_nested_containers
    node = window("main", title: "App") do
      column(padding: 16) do
        row(spacing: 8) do
          button("ok", "OK")
          button("cancel", "Cancel")
        end
      end
    end

    assert_equal "window", node.type
    col = node.children.first
    assert_equal "column", col.type
    row = col.children.first
    assert_equal "row", row.type
    assert_equal 2, row.children.length
  end

  def test_conditional_rendering
    show_extra = false
    node = column("list") do
      text("always", "Always here")
      text("extra", "Bonus") if show_extra
    end

    assert_equal 1, node.children.length
  end

  def test_iteration
    items = %w[a b c]
    node = column("list") do
      items.each { |item| text(item, item.upcase) }
    end

    assert_equal 3, node.children.length
    assert_equal "A", node.children[0].props[:content]
    assert_equal "B", node.children[1].props[:content]
    assert_equal "C", node.children[2].props[:content]
  end

  def test_text_input
    node = text_input("search", "hello", placeholder: "Search...")
    assert_equal "text_input", node.type
    assert_equal "hello", node.props[:value]
    assert_equal "Search...", node.props[:placeholder]
  end

  def test_checkbox
    node = checkbox("agree", true)
    assert_equal "checkbox", node.type
    assert_equal true, node.props[:checked]
  end

  def test_slider
    node = slider("vol", [0, 100], 50)
    assert_equal "slider", node.type
    assert_equal 0, node.props[:min]
    assert_equal 100, node.props[:max]
    assert_equal 50, node.props[:value]
  end

  def test_context_cleanup_on_exception
    assert_raises(RuntimeError) do
      column("broken") do
        text("ok", "fine")
        raise "boom"
      end
    end

    # Context should be clean -- next build should work
    node = column("after") do
      text("good", "works")
    end
    assert_equal 1, node.children.length
  end
end
