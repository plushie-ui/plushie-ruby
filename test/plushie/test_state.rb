# frozen_string_literal: true

require "test_helper"

class TestState < Minitest::Test
  S = Plushie::State

  def test_new_and_get
    state = S.new(count: 0, name: "test")
    assert_equal 0, S.get(state, [:count])
    assert_equal "test", S.get(state, [:name])
  end

  def test_get_empty_path_returns_all_data
    state = S.new(count: 0)
    assert_equal({count: 0}, S.get(state, []))
  end

  def test_get_nested
    state = S.from_hash({user: {name: "Alice", age: 30}})
    assert_equal "Alice", S.get(state, [:user, :name])
  end

  def test_get_missing_returns_nil
    state = S.new(count: 0)
    assert_nil S.get(state, [:missing])
  end

  def test_put_updates_and_increments_revision
    state = S.new(count: 0)
    state = S.put(state, [:count], 5)
    assert_equal 5, S.get(state, [:count])
    assert_equal 1, S.revision(state)
  end

  def test_put_nested
    state = S.from_hash({user: {name: "Alice"}})
    state = S.put(state, [:user, :name], "Bob")
    assert_equal "Bob", S.get(state, [:user, :name])
  end

  def test_update_with_block
    state = S.new(count: 10)
    state = S.update(state, [:count]) { |v| v + 5 }
    assert_equal 15, S.get(state, [:count])
    assert_equal 1, S.revision(state)
  end

  def test_revision_starts_at_zero
    state = S.new(x: 1)
    assert_equal 0, S.revision(state)
  end

  def test_revision_increments
    state = S.new(x: 1)
    state = S.put(state, [:x], 2)
    state = S.put(state, [:x], 3)
    assert_equal 2, S.revision(state)
  end

  # -- Transactions --------------------------------------------------------

  def test_begin_and_commit_transaction
    state = S.new(count: 0)
    state = S.begin_transaction(state)

    state = S.put(state, [:count], 10)
    state = S.put(state, [:count], 20)
    # Revision has been incrementing within the transaction
    assert_equal 2, S.revision(state)

    state = S.commit_transaction(state)
    assert_equal 20, S.get(state, [:count])
    # Commit sets revision to old_rev + 1
    assert_equal 1, S.revision(state)
  end

  def test_rollback_transaction
    state = S.new(count: 0)
    state = S.begin_transaction(state)

    state = S.put(state, [:count], 99)
    state = S.rollback_transaction(state)

    assert_equal 0, S.get(state, [:count])
    assert_equal 0, S.revision(state)
  end

  def test_nested_transaction_returns_error
    state = S.new(count: 0)
    state = S.begin_transaction(state)
    result = S.begin_transaction(state)
    assert_equal [:error, :transaction_already_active], result
  end

  def test_transaction_preserves_data_on_rollback
    state = S.new(a: 1, b: 2)
    state = S.put(state, [:a], 10)
    state = S.begin_transaction(state)
    state = S.put(state, [:a], 100)
    state = S.put(state, [:b], 200)
    state = S.rollback_transaction(state)

    assert_equal 10, S.get(state, [:a])
    assert_equal 2, S.get(state, [:b])
    assert_equal 1, S.revision(state)
  end
end
