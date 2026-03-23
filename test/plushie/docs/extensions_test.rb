# frozen_string_literal: true

require "test_helper"

class DocsExtensionsTest < Minitest::Test
  # -- Extension widget declaration from extensions.md --

  class MySparkline
    include Plushie::Extension

    widget :sparkline

    prop :data, :number, default: 0
    prop :color, :color, default: "#4CAF50"
    prop :capacity, :number, default: 100

    command :push, value: :number
  end

  def test_extension_widget_type_names
    assert_equal [:sparkline], MySparkline.type_names
  end

  def test_extension_prop_names_include_declared_and_auto
    names = MySparkline.prop_names
    assert_includes names, :data
    assert_includes names, :color
    assert_includes names, :capacity
    assert_includes names, :a11y
    assert_includes names, :event_rate
  end

  # -- Extension new with defaults from extensions.md --

  def test_extension_new_with_defaults
    widget = MySparkline.new("spark-1")
    assert_equal "spark-1", widget.id
    assert_equal "#4CAF50", widget.color
    assert_equal 100, widget.capacity
  end

  def test_extension_new_with_overrides
    widget = MySparkline.new("spark-1", color: "#ff0000", capacity: 50)
    assert_equal "#ff0000", widget.color
    assert_equal 50, widget.capacity
  end

  # -- Extension build produces Node from extensions.md --

  def test_extension_build_produces_node
    widget = MySparkline.new("spark-1", data: 42)
    node = widget.build
    assert_instance_of Plushie::Node, node
    assert_equal "sparkline", node.type
    assert_equal "spark-1", node.id
    assert_equal 42, node.props[:data]
  end

  def test_extension_build_includes_color
    widget = MySparkline.new("spark-1", color: "#ff0000")
    node = widget.build
    assert_equal "#ff0000", node.props[:color]
  end

  # -- Extension setter chain from extensions.md --

  def test_extension_setter_chain
    widget = MySparkline.new("spark-1")
    updated = widget.set_color("#0000ff").set_capacity(200)

    # Original unchanged (immutable)
    assert_equal "#4CAF50", widget.color
    assert_equal 100, widget.capacity

    # Updated has new values
    assert_equal "#0000ff", updated.color
    assert_equal 200, updated.capacity
  end

  def test_extension_a11y_setter
    widget = MySparkline.new("spark-1")
    with_a11y = widget.set_a11y({role: :img, label: "CPU usage"})
    assert_nil widget.a11y
    assert_equal({role: :img, label: "CPU usage"}, with_a11y.a11y)
  end

  def test_extension_event_rate_setter
    widget = MySparkline.new("spark-1")
    with_rate = widget.set_event_rate(30)
    assert_nil widget.event_rate
    assert_equal 30, with_rate.event_rate
  end

  # -- Pure Ruby composite extension from extensions.md --

  class CardExtension
    include Plushie::Extension
    include Plushie::UI

    widget :card, kind: :widget, container: true

    prop :title, :string
    prop :subtitle, :string, default: nil

    def render(id, props, _children = [])
      # Simplified render -- just return a node tree
      Plushie::Node.new(
        id: id,
        type: "column",
        props: {padding: 16, spacing: 8},
        children: [
          Plushie::Node.new(id: "ext_title", type: "text", props: {content: props[:title], size: 20})
        ]
      )
    end
  end

  def test_pure_ruby_extension_container
    assert CardExtension.container?
  end

  def test_pure_ruby_extension_type_names
    assert_equal [:card], CardExtension.type_names
  end

  def test_pure_ruby_extension_build_calls_render
    card = CardExtension.new("info", title: "Details")
    node = card.build
    assert_equal "column", node.type
    assert_equal "info", node.id
  end

  # -- Unsupported prop type raises from extensions.md --

  def test_extension_rejects_unknown_prop_type
    assert_raises(ArgumentError) do
      Class.new do
        include Plushie::Extension
        widget :bad
        prop :value, :unknown_type
      end
    end
  end

  # -- Reserved prop name raises from extensions.md --

  def test_extension_rejects_reserved_prop_name
    assert_raises(ArgumentError) do
      Class.new do
        include Plushie::Extension
        widget :bad
        prop :id, :string
      end
    end
  end
end
