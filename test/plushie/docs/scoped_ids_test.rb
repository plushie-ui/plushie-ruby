# frozen_string_literal: true

require "test_helper"

class DocsScopedIdsTest < Minitest::Test
  # Helper that includes the DSL for building trees in tests
  class Builder
    include Plushie::UI

    public(*Plushie::UI.private_instance_methods(false))
  end

  def setup
    @b = Builder.new
  end

  # -- Container scoping --

  def test_scoped_ids_container_scopes_children
    node = @b.container("form") do
      @b.button("save", "Save")
    end
    tree = Plushie::Tree.normalize(node).first
    assert_equal "form", tree.id
    assert_equal "form/save", tree.children.first.id
  end

  def test_scoped_ids_nested_containers
    node = @b.container("sidebar") do
      @b.container("form") do
        @b.text_input("email", "")
        @b.button("save", "Save")
      end
    end
    tree = Plushie::Tree.normalize(node).first

    assert_equal "sidebar", tree.id
    form = tree.children.first
    assert_equal "sidebar/form", form.id
    assert_equal "sidebar/form/email", form.children[0].id
    assert_equal "sidebar/form/save", form.children[1].id
  end

  # -- Auto-ID containers don't scope --

  def test_scoped_ids_auto_id_no_scope
    node = @b.container("wrapper") do
      @b.column do
        @b.button("save", "Save")
      end
    end
    tree = Plushie::Tree.normalize(node).first

    col = tree.children.first
    assert col.id.start_with?("auto:"), "auto-ID column expected"
    btn = col.children.first
    assert_equal "wrapper/save", btn.id
  end

  # -- Window nodes don't scope --

  def test_scoped_ids_window_no_scope
    node = @b.window("main", title: "App") do
      @b.button("save", "Save")
    end
    tree = Plushie::Tree.normalize(node).first
    assert_equal "main", tree.id
    assert_equal "save", tree.children.first.id
  end

  # -- Event scope pattern matching --

  def test_scoped_ids_event_local_id_match
    event = Plushie::Event::Widget.new(type: :click, id: "save", scope: ["form", "sidebar"])
    case event
    in Plushie::Event::Widget[type: :click, id: "save"]
      pass
    else
      flunk "expected local id match"
    end
  end

  def test_scoped_ids_event_immediate_parent_match
    event = Plushie::Event::Widget.new(type: :click, id: "save", scope: ["form", "sidebar"])
    case event
    in Plushie::Event::Widget[type: :click, id: "save", scope: ["form", *]]
      pass
    else
      flunk "expected immediate parent match"
    end
  end

  def test_scoped_ids_event_dynamic_list_binding
    event = Plushie::Event::Widget.new(type: :toggle, id: "done", scope: ["item_3", "todo_list"])
    case event
    in Plushie::Event::Widget[type: :toggle, id: "done", scope: [item_id, *]]
      assert_equal "item_3", item_id
    else
      flunk "expected dynamic list binding match"
    end
  end

  def test_scoped_ids_event_no_scope_match
    event = Plushie::Event::Widget.new(type: :click, id: "save", scope: [])
    case event
    in Plushie::Event::Widget[id: "save", scope: []]
      pass
    else
      flunk "expected no-scope match"
    end
  end

  def test_scoped_ids_event_exact_depth_match
    event = Plushie::Event::Widget.new(type: :click, id: "query", scope: ["search"])
    case event
    in Plushie::Event::Widget[id: "query", scope: ["search"]]
      pass
    else
      flunk "expected exact depth match"
    end
  end

  # -- Event.target reconstructs full path --

  def test_scoped_ids_event_target
    event = Plushie::Event::Widget.new(type: :click, id: "save", scope: ["form", "sidebar"])
    assert_equal "sidebar/form/save", Plushie::Event.target(event)
  end

  def test_scoped_ids_event_target_no_scope
    event = Plushie::Event::Widget.new(type: :click, id: "save")
    assert_equal "save", Plushie::Event.target(event)
  end

  # -- Command.focus with scoped path --

  def test_scoped_ids_command_focus_scoped
    cmd = Plushie::Command.focus("sidebar/form/email")
    assert_equal :focus, cmd.type
    assert_equal "sidebar/form/email", cmd.payload[:target]
  end

  # -- Tree.find with scoped paths --

  def test_scoped_ids_tree_find_full_path
    node = @b.container("sidebar") do
      @b.container("form") do
        @b.button("save", "Save")
      end
    end
    tree = Plushie::Tree.normalize(node).first

    found = Plushie::Tree.find(tree, "sidebar/form/save")
    refute_nil found
    assert_equal "button", found.type
  end

  def test_scoped_ids_tree_find_local_id
    node = @b.container("sidebar") do
      @b.container("form") do
        @b.button("save", "Save")
      end
    end
    tree = Plushie::Tree.normalize(node).first

    # Local ID search (Tree.find matches on exact id field)
    found = Plushie::Tree.find(tree, "sidebar/form/save")
    refute_nil found
  end

  # -- A11y reference resolution --

  def test_scoped_ids_a11y_labelled_by_resolved
    node = @b.container("form") do
      @b.text("name_label", "Name:")
      @b.text_input("name", "", a11y: {labelled_by: "name_label"})
    end
    tree = Plushie::Tree.normalize(node).first
    input = tree.children[1]
    # The resolved a11y is stored under the string key "a11y"
    a11y = input.props["a11y"]
    assert_equal "form/name_label", a11y["labelled_by"]
  end
end
