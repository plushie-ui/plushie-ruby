# frozen_string_literal: true

require "test_helper"

class TestRoute < Minitest::Test
  R = Plushie::Route

  def test_new_with_initial_path
    route = R.new(:home)
    assert_equal :home, R.current(route)
    assert_equal({}, R.params(route))
  end

  def test_new_with_params
    route = R.new(:home, tab: "main")
    assert_equal :home, R.current(route)
    assert_equal({tab: "main"}, R.params(route))
  end

  def test_push
    route = R.new(:home)
    route = R.push(route, :settings, tab: "general")
    assert_equal :settings, R.current(route)
    assert_equal({tab: "general"}, R.params(route))
  end

  def test_pop
    route = R.new(:home)
    route = R.push(route, :settings)
    route = R.pop(route)
    assert_equal :home, R.current(route)
  end

  def test_pop_does_not_remove_root
    route = R.new(:home)
    route = R.pop(route)
    assert_equal :home, R.current(route)
  end

  def test_can_go_back
    route = R.new(:home)
    refute R.can_go_back?(route)

    route = R.push(route, :settings)
    assert R.can_go_back?(route)

    route = R.pop(route)
    refute R.can_go_back?(route)
  end

  def test_history
    route = R.new(:home)
    route = R.push(route, :settings)
    route = R.push(route, :profile)
    assert_equal [:profile, :settings, :home], R.history(route)
  end

  def test_push_preserves_existing_stack
    route = R.new(:home)
    route = R.push(route, :a)
    route = R.push(route, :b)
    assert_equal [:b, :a, :home], R.history(route)
  end

  def test_multiple_pops_stop_at_root
    route = R.new(:home)
    route = R.push(route, :a)
    route = R.push(route, :b)
    route = R.pop(route)
    route = R.pop(route)
    route = R.pop(route) # should be no-op
    assert_equal :home, R.current(route)
    assert_equal [:home], R.history(route)
  end
end
