# frozen_string_literal: true

require "test_helper"

# A simple extension for testing: a gauge widget.
class TestGauge
  include Plushie::Widget

  widget :gauge
  prop :value, :number, default: 0
  prop :max, :number, default: 100
  prop :color, :color, default: :blue
end

# A composite extension that defines render.
class TestLabeledValue
  include Plushie::Widget
  include Plushie::UI

  widget :labeled_value
  prop :label, :string, default: ""
  prop :content, :string, default: ""

  def render(id, props)
    column(id, spacing: 4) do
      text("#{id}/label", props[:label] || "", size: 12)
      text("#{id}/value", props[:content] || "", size: 16)
    end
  end
end

class TestExtension < Minitest::Test
  def test_type_names
    assert_equal [:gauge], TestGauge.type_names
  end

  def test_prop_names
    names = TestGauge.prop_names
    assert_includes names, :value
    assert_includes names, :max
    assert_includes names, :color
    assert_includes names, :a11y
    assert_includes names, :event_rate
  end

  def test_initialize_with_defaults
    g = TestGauge.new("g1")
    assert_equal "g1", g.id
    assert_equal 0, g.value
    assert_equal 100, g.max
    assert_equal :blue, g.color
  end

  def test_initialize_with_overrides
    g = TestGauge.new("g2", value: 42, max: 200, color: :red)
    assert_equal 42, g.value
    assert_equal 200, g.max
    assert_equal :red, g.color
  end

  def test_setter_returns_new_instance
    g1 = TestGauge.new("g3", value: 10)
    g2 = g1.set_value(20)
    assert_equal 10, g1.value
    assert_equal 20, g2.value
  end

  def test_build_without_render_returns_node
    g = TestGauge.new("g4", value: 75, max: 100)
    node = g.build
    assert_instance_of Plushie::Node, node
    assert_equal "g4", node.id
    assert_equal "gauge", node.type
    assert_equal 75, node.props[:value]
    assert_equal 100, node.props[:max]
    assert_equal :blue, node.props[:color]
  end

  def test_build_skips_nil_props
    g = TestGauge.new("g5")
    node = g.build
    refute node.props.key?(:a11y)
    refute node.props.key?(:event_rate)
  end

  def test_a11y_and_event_rate
    g = TestGauge.new("g6", a11y: {role: "progressbar"}, event_rate: 30)
    node = g.build
    assert_equal({role: "progressbar"}, node.props[:a11y])
    assert_equal 30, node.props[:event_rate]
  end

  def test_composite_render
    lv = TestLabeledValue.new("stats", label: "Score", content: "42")
    node = lv.build
    # render returns a column node
    assert_equal "column", node.type
    assert_equal "stats", node.id
    assert_equal 2, node.children.length
    assert_equal "Score", node.children[0].props[:content]
    assert_equal "42", node.children[1].props[:content]
  end

  def test_reserved_prop_name_raises
    assert_raises(ArgumentError) do
      Class.new do
        include Plushie::Widget

        widget :bad
        prop :id, :string
      end
    end
  end

  def test_unsupported_prop_type_raises
    assert_raises(ArgumentError) do
      Class.new do
        include Plushie::Widget

        widget :bad
        prop :thing, :unicorn
      end
    end
  end

  def test_stateful_widget_without_render_raises
    assert_raises(ArgumentError, /requires.*def self.render/) do
      klass = Class.new do
        include Plushie::Widget

        widget :broken
        state :count, default: 0
      end
      klass.finalize!
    end
  end

  # -- Stateful widgets --------------------------------------------------------

  def test_state_declaration_makes_widget_stateful
    klass = Class.new do
      include Plushie::Widget

      widget :counter
      prop :label, :string, default: ""
      state :count, default: 0

      def self.render(id, _props, _state) = Plushie::Node.new(id: id, type: "text")
    end
    klass.finalize!
    assert klass.stateful?
  end

  def test_stateful_widget_build_returns_placeholder
    klass = Class.new do
      include Plushie::Widget

      widget :counter
      state :count, default: 0

      def self.init = {count: 0}

      def self.render(id, _props, state)
        Plushie::Node.new(id: id, type: "text", props: {content: state[:count].to_s})
      end
    end

    node = klass.new("c1").build
    assert_instance_of Plushie::Node, node
    assert_equal "widget_placeholder", node.type
    assert node.meta.key?(Plushie::CanvasWidget::META_KEY)
    assert_equal klass, node.meta[Plushie::CanvasWidget::META_KEY]
  end

  def test_stateful_widget_auto_init_from_state_fields
    klass = Class.new do
      include Plushie::Widget

      widget :toggle
      state :on, default: false
      state :count, default: 0

      def self.render(id, _props, _state) = Plushie::Node.new(id: id, type: "text")
    end
    klass.finalize!
    assert_equal({on: false, count: 0}, klass.init)
  end

  def test_stateful_widget_default_handle_event_with_events
    klass = Class.new do
      include Plushie::Widget

      widget :toggle
      state :on, default: false
      event :toggled

      def self.render(id, _props, _state) = Plushie::Node.new(id: id, type: "text")
    end
    klass.finalize!
    # Widgets with event declarations default to :consumed
    result = klass.handle_event(:some_event, {on: false})
    assert_equal [:consumed, {on: false}], result
  end

  def test_stateful_widget_default_handle_event_without_events
    klass = Class.new do
      include Plushie::Widget

      widget :wrapper
      state :expanded, default: true

      def self.render(id, _props, _state) = Plushie::Node.new(id: id, type: "text")
    end
    klass.finalize!
    # Widgets without event declarations default to :ignored
    result = klass.handle_event(:some_event, {expanded: true})
    assert_equal [:ignored, {expanded: true}], result
  end

  def test_event_declaration
    klass = Class.new do
      include Plushie::Widget

      widget :picker
      event :select
      event :change

      def self.render(id, _props, _state) = Plushie::Node.new(id: id, type: "text")
    end
    klass.finalize!
    assert_equal [:select, :change], klass.widget_events
    assert klass.stateful?
  end

  def test_render_only_widget_is_not_stateful
    refute TestGauge.stateful?
    refute TestLabeledValue.stateful?
  end

  def test_handle_event_makes_widget_stateful
    klass = Class.new do
      include Plushie::Widget

      widget :interceptor

      def self.handle_event(_event, state)
        [:ignored, state]
      end

      def self.render(id, _props, _state) = Plushie::Node.new(id: id, type: "text")
    end
    klass.finalize!
    assert klass.stateful?
  end
end
