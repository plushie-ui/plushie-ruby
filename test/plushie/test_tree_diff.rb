# frozen_string_literal: true

require "test_helper"

class TestTreeDiff < Minitest::Test
  N = Plushie::Node

  def node(id, type = "text", props: {}, children: [])
    N.new(id: id, type: type, props: props, children: children)
  end

  # -- Edge cases -----------------------------------------------------------

  def test_diff_nil_nil
    assert_equal [], Plushie::Tree.diff(nil, nil)
  end

  def test_diff_nil_to_tree
    new_tree = node("root", "column")
    ops = Plushie::Tree.diff(nil, new_tree)
    assert_equal 1, ops.length
    assert_equal "replace_node", ops[0]["op"]
    assert_equal [], ops[0]["path"]
    assert_equal "root", ops[0]["node"]["id"]
  end

  def test_diff_tree_to_nil
    old_tree = node("root", "column")
    ops = Plushie::Tree.diff(old_tree, nil)
    assert_equal 1, ops.length
    assert_equal "replace_node", ops[0]["op"]
  end

  # -- Identical trees ------------------------------------------------------

  def test_diff_identical_trees
    tree = node("root", "column", children: [
      node("a", "text", props: {content: "hello"}),
      node("b", "button", props: {label: "click"})
    ])
    ops = Plushie::Tree.diff(tree, tree)
    assert_equal [], ops
  end

  # -- Root changes ---------------------------------------------------------

  def test_diff_different_root_id
    old = node("root1", "column")
    new_tree = node("root2", "column")
    ops = Plushie::Tree.diff(old, new_tree)
    assert_equal 1, ops.length
    assert_equal "replace_node", ops[0]["op"]
  end

  def test_diff_different_type
    old = node("root", "column")
    new_tree = node("root", "row")
    ops = Plushie::Tree.diff(old, new_tree)
    assert_equal 1, ops.length
    assert_equal "replace_node", ops[0]["op"]
  end

  # -- Prop changes ---------------------------------------------------------

  def test_diff_prop_changed
    old = node("msg", "text", props: {content: "hello"})
    new_tree = node("msg", "text", props: {content: "world"})
    ops = Plushie::Tree.diff(old, new_tree)
    assert_equal 1, ops.length
    assert_equal "update_props", ops[0]["op"]
    assert_equal "world", ops[0]["props"]["content"]
  end

  def test_diff_prop_added
    old = node("msg", "text", props: {content: "hi"})
    new_tree = node("msg", "text", props: {content: "hi", color: "red"})
    ops = Plushie::Tree.diff(old, new_tree)
    assert_equal 1, ops.length
    assert_equal "red", ops[0]["props"]["color"]
  end

  def test_diff_prop_removed
    old = node("msg", "text", props: {content: "hi", color: "red"})
    new_tree = node("msg", "text", props: {content: "hi"})
    ops = Plushie::Tree.diff(old, new_tree)
    assert_equal 1, ops.length
    assert_nil ops[0]["props"]["color"]
  end

  # -- Child additions ------------------------------------------------------

  def test_diff_child_added
    old = node("root", "column", children: [
      node("a", "text")
    ])
    new_tree = node("root", "column", children: [
      node("a", "text"),
      node("b", "button")
    ])
    ops = Plushie::Tree.diff(old, new_tree)
    assert_equal 1, ops.length
    assert_equal "insert_child", ops[0]["op"]
    assert_equal 1, ops[0]["index"]
    assert_equal "b", ops[0]["node"]["id"]
  end

  # -- Child removals -------------------------------------------------------

  def test_diff_child_removed
    old = node("root", "column", children: [
      node("a", "text"),
      node("b", "button"),
      node("c", "text")
    ])
    new_tree = node("root", "column", children: [
      node("a", "text"),
      node("c", "text")
    ])
    ops = Plushie::Tree.diff(old, new_tree)
    assert_equal 1, ops.length
    assert_equal "remove_child", ops[0]["op"]
    assert_equal 1, ops[0]["index"]
  end

  def test_diff_multiple_removals_descending_index
    old = node("root", "column", children: [
      node("a"), node("b"), node("c"), node("d")
    ])
    new_tree = node("root", "column", children: [
      node("a"), node("d")
    ])
    ops = Plushie::Tree.diff(old, new_tree)
    remove_ops = ops.select { |o| o["op"] == "remove_child" }
    assert_equal 2, remove_ops.length
    # Must be descending index order
    assert_equal 2, remove_ops[0]["index"]
    assert_equal 1, remove_ops[1]["index"]
  end

  # -- Child updates --------------------------------------------------------

  def test_diff_child_prop_changed
    old = node("root", "column", children: [
      node("msg", "text", props: {content: "old"})
    ])
    new_tree = node("root", "column", children: [
      node("msg", "text", props: {content: "new"})
    ])
    ops = Plushie::Tree.diff(old, new_tree)
    assert_equal 1, ops.length
    assert_equal "update_props", ops[0]["op"]
    assert_equal [0], ops[0]["path"]
    assert_equal "new", ops[0]["props"]["content"]
  end

  # -- Reorder fallback -----------------------------------------------------

  def test_diff_reordered_children
    old = node("root", "column", children: [
      node("a"), node("b"), node("c")
    ])
    new_tree = node("root", "column", children: [
      node("c"), node("a"), node("b")
    ])
    ops = Plushie::Tree.diff(old, new_tree)
    # LIS-based diff: "a" and "b" form the LIS (keep in place),
    # "c" is removed from old position and inserted at new position.
    remove_ops = ops.select { |op| op["op"] == "remove_child" }
    insert_ops = ops.select { |op| op["op"] == "insert_child" }
    assert_equal 1, remove_ops.length, "expected 1 remove for 'c'"
    assert_equal 1, insert_ops.length, "expected 1 insert for 'c'"
    assert_equal "c", insert_ops[0]["node"]["id"]
    assert_equal 0, insert_ops[0]["index"]
  end

  # -- Mixed operations -----------------------------------------------------

  def test_diff_remove_and_insert
    old = node("root", "column", children: [
      node("a"), node("b")
    ])
    new_tree = node("root", "column", children: [
      node("a"), node("c")
    ])
    ops = Plushie::Tree.diff(old, new_tree)
    remove_ops = ops.select { |o| o["op"] == "remove_child" }
    insert_ops = ops.select { |o| o["op"] == "insert_child" }
    assert_equal 1, remove_ops.length
    assert_equal 1, insert_ops.length
    # Remove comes before insert in the ops array
    assert ops.index(remove_ops[0]) < ops.index(insert_ops[0])
  end

  # -- Deep nesting ---------------------------------------------------------

  def test_diff_deeply_nested_change
    old = node("root", "column", children: [
      node("row", "row", children: [
        node("btn", "button", props: {label: "old"})
      ])
    ])
    new_tree = node("root", "column", children: [
      node("row", "row", children: [
        node("btn", "button", props: {label: "new"})
      ])
    ])
    ops = Plushie::Tree.diff(old, new_tree)
    assert_equal 1, ops.length
    assert_equal "update_props", ops[0]["op"]
    # Path should reach the nested button
    assert_equal [0, 0], ops[0]["path"]
  end

  # -- node_to_wire ---------------------------------------------------------

  def test_node_to_wire
    tree = node("root", "column", props: {spacing: 8}, children: [
      node("txt", "text", props: {content: "hi"})
    ])
    wire = Plushie::Tree.node_to_wire(tree)
    assert_equal "root", wire["id"]
    assert_equal "column", wire["type"]
    assert_equal "8", wire["props"]["spacing"].to_s
    assert_equal 1, wire["children"].length
    assert_equal "txt", wire["children"][0]["id"]
  end

  # -- LIS edge cases -------------------------------------------------------

  def test_diff_reverse_order
    old = node("root", "column", children: [
      node("a"), node("b"), node("c"), node("d")
    ])
    new_tree = node("root", "column", children: [
      node("d"), node("c"), node("b"), node("a")
    ])
    ops = Plushie::Tree.diff(old, new_tree)
    # All 4 nodes should appear in the result. LIS of [3,2,1,0] has
    # length 1, so 3 nodes get removed and re-inserted.
    remove_ops = ops.select { |o| o["op"] == "remove_child" }
    insert_ops = ops.select { |o| o["op"] == "insert_child" }
    assert_equal 3, remove_ops.length
    assert_equal 3, insert_ops.length

    # The diff should produce a valid patch sequence
    refute_empty ops
  end

  def test_diff_single_child_reorder
    old = node("root", "column", children: [node("a")])
    new_tree = node("root", "column", children: [node("a")])
    ops = Plushie::Tree.diff(old, new_tree)
    assert_equal [], ops
  end

  def test_diff_all_children_replaced
    old = node("root", "column", children: [
      node("a"), node("b")
    ])
    new_tree = node("root", "column", children: [
      node("x"), node("y")
    ])
    ops = Plushie::Tree.diff(old, new_tree)
    remove_ops = ops.select { |o| o["op"] == "remove_child" }
    insert_ops = ops.select { |o| o["op"] == "insert_child" }
    assert_equal 2, remove_ops.length
    assert_equal 2, insert_ops.length
  end

  def test_diff_all_children_removed
    old = node("root", "column", children: [
      node("a"), node("b"), node("c")
    ])
    new_tree = node("root", "column", children: [])
    ops = Plushie::Tree.diff(old, new_tree)
    remove_ops = ops.select { |o| o["op"] == "remove_child" }
    assert_equal 3, remove_ops.length
    assert_empty ops.select { |o| o["op"] == "insert_child" }
  end

  def test_diff_interleaved_insert_and_keep
    # Old: a, c, e.  New: a, b, c, d, e
    old = node("root", "column", children: [
      node("a"), node("c"), node("e")
    ])
    new_tree = node("root", "column", children: [
      node("a"), node("b"), node("c"), node("d"), node("e")
    ])
    ops = Plushie::Tree.diff(old, new_tree)
    insert_ops = ops.select { |o| o["op"] == "insert_child" }
    assert_equal 2, insert_ops.length
    assert_equal %w[b d], insert_ops.map { |o| o["node"]["id"] }
    assert_empty ops.select { |o| o["op"] == "remove_child" }
  end

  # -- id_keyed_lists_equal? (tested via diff_props) -------------------------

  def test_diff_id_keyed_list_same_content_different_order
    # When prop arrays contain id-keyed hashes with same content but
    # different order, diff should detect no change (id-keyed comparison).
    old = node("root", "table", props: {
      rows: [{id: "r1", name: "Alice"}, {id: "r2", name: "Bob"}]
    })
    new_tree = node("root", "table", props: {
      rows: [{id: "r2", name: "Bob"}, {id: "r1", name: "Alice"}]
    })
    ops = Plushie::Tree.diff(old, new_tree)
    prop_ops = ops.select { |o| o["op"] == "update_props" }
    assert_empty prop_ops, "id-keyed lists with same content should not produce updates"
  end

  def test_diff_id_keyed_list_changed_value
    old = node("root", "table", props: {
      rows: [{id: "r1", name: "Alice"}]
    })
    new_tree = node("root", "table", props: {
      rows: [{id: "r1", name: "Alicia"}]
    })
    ops = Plushie::Tree.diff(old, new_tree)
    prop_ops = ops.select { |o| o["op"] == "update_props" }
    assert_equal 1, prop_ops.length, "changed id-keyed list value should produce update"
  end

  def test_diff_non_id_keyed_list_not_special
    # Regular arrays without :id keys use normal equality
    old = node("root", "text", props: {items: [1, 2, 3]})
    new_tree = node("root", "text", props: {items: [3, 2, 1]})
    ops = Plushie::Tree.diff(old, new_tree)
    assert_equal 1, ops.length
    assert_equal "update_props", ops[0]["op"]
  end

  # -- Index adjustment -----------------------------------------------------

  def test_index_after_removals
    # Private method, test indirectly via diff behavior
    old = node("root", "column", children: [
      node("a"), node("b"), node("c"), node("d")
    ])
    new_tree = node("root", "column", children: [
      node("a"), node("c", "text", props: {content: "updated"}), node("d")
    ])
    ops = Plushie::Tree.diff(old, new_tree)
    # Should have: remove b at index 1, update c (which is now at adjusted index 1)
    remove_ops = ops.select { |o| o["op"] == "remove_child" }
    update_ops = ops.select { |o| o["op"] == "update_props" }
    assert_equal 1, remove_ops.length
    assert_equal 1, remove_ops[0]["index"]
    assert_equal 1, update_ops.length
    assert_equal [1], update_ops[0]["path"]
  end
end
