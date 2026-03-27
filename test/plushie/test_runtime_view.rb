# frozen_string_literal: true

require "test_helper"

class TestRuntimeView < Minitest::Test
  include Plushie::UI

  class ViewApp
    def initialize(view_tree)
      @view_tree = view_tree
    end

    def view(_model) = @view_tree
  end

  def runtime_for(view_tree)
    Plushie::Runtime.new(app: ViewApp.new(view_tree), transport: :spawn)
  end

  def test_normalize_view_tree_requires_window_nodes
    runtime = runtime_for(column("content") { text("msg", "hi") })

    error = assert_raises(ArgumentError) do
      runtime.send(:normalize_view_tree, runtime.instance_variable_get(:@app).view(nil))
    end

    assert_equal "view must return a window node or an array of window nodes", error.message
  end

  def test_normalize_view_tree_wraps_single_window_in_root
    runtime = runtime_for(window("main", title: "Main") { text("msg", "hi") })

    tree = runtime.send(:normalize_view_tree, runtime.instance_variable_get(:@app).view(nil))

    assert_equal "root", tree.id
    assert_equal "root", tree.type
    assert_equal ["main"], tree.children.map(&:id)
  end

  def test_normalize_view_tree_keeps_multiple_windows
    runtime = runtime_for([
      window("main", title: "Main") { text("msg", "hi") },
      window("inspector", title: "Inspector") { text("meta", "details") }
    ])

    tree = runtime.send(:normalize_view_tree, runtime.instance_variable_get(:@app).view(nil))

    assert_equal "root", tree.id
    assert_equal %w[main inspector], tree.children.map(&:id)
    assert tree.children.all? { |node| node.type == "window" }
  end
end
