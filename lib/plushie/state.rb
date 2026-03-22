# frozen_string_literal: true

module Plushie
  # Path-based state management with revision tracking and transactions.
  #
  # A lightweight wrapper around a plain hash that tracks a monotonically
  # increasing revision number on every mutation. Useful for detecting
  # changes and implementing optimistic concurrency.
  #
  # == Transactions
  #
  # +begin_transaction+ captures a snapshot of the current data and revision.
  # Subsequent mutations increment the revision as usual. +commit_transaction+
  # finalises the transaction (bumping the revision once from the pre-transaction
  # value). +rollback_transaction+ restores the snapshot exactly.
  #
  # @example
  #   state = Plushie::State.new(count: 0)
  #   state = Plushie::State.put(state, [:count], 5)
  #   Plushie::State.get(state, [:count])   #=> 5
  #   Plushie::State.revision(state)        #=> 1
  #
  class State
    # Immutable state container.
    Container = ::Data.define(:data, :revision, :transaction) do
      include Plushie::Model::Extensions
    end

    # Creates a new state container wrapping +data+.
    # The initial revision is 0.
    #
    # @param data [Hash] initial state data
    # @return [Container]
    def self.new(**data)
      Container.new(data: data, revision: 0, transaction: nil)
    end

    # Creates a new state from an existing hash.
    #
    # @param data [Hash]
    # @return [Container]
    def self.from_hash(data)
      Container.new(data: data, revision: 0, transaction: nil)
    end

    # Reads the value at +path+ in the state data.
    # An empty path returns the entire data hash.
    #
    # @param state [Container]
    # @param path [Array] key path
    # @return [Object]
    def self.get(state, path)
      return state.data if path.empty?
      state.data.dig(*path)
    end

    # Sets the value at +path+ to +value+, incrementing the revision.
    #
    # @param state [Container]
    # @param path [Array] key path (must have at least one element)
    # @param value [Object]
    # @return [Container]
    def self.put(state, path, value)
      new_data = deep_put(state.data, path, value)
      state.with(data: new_data, revision: state.revision + 1)
    end

    # Applies +block+ to the value at +path+, incrementing the revision.
    # The block receives the current value and must return the new value.
    #
    # @param state [Container]
    # @param path [Array] key path
    # @yield [current_value] the current value at path
    # @yieldreturn [Object] the new value
    # @return [Container]
    def self.update(state, path, &block)
      current = get(state, path)
      put(state, path, block.call(current))
    end

    # Returns the current revision number.
    #
    # @param state [Container]
    # @return [Integer]
    def self.revision(state) = state.revision

    # Begins a transaction by capturing the current data and revision.
    #
    # @param state [Container]
    # @return [Container, Array(:error, Symbol)]
    def self.begin_transaction(state)
      if state.transaction
        [:error, :transaction_already_active]
      else
        state.with(transaction: {data: state.data, revision: state.revision})
      end
    end

    # Commits the active transaction, setting the revision to one past the
    # pre-transaction value.
    #
    # @param state [Container]
    # @return [Container]
    def self.commit_transaction(state)
      old_rev = state.transaction[:revision]
      state.with(transaction: nil, revision: old_rev + 1)
    end

    # Rolls back the active transaction, restoring the data and revision
    # to their pre-transaction values.
    #
    # @param state [Container]
    # @return [Container]
    def self.rollback_transaction(state)
      snapshot = state.transaction
      state.with(data: snapshot[:data], revision: snapshot[:revision], transaction: nil)
    end

    # -- Private ------------------------------------------------------------

    # @api private
    def self.deep_put(hash, path, value)
      return value if path.empty?

      key = path.first
      if path.length == 1
        hash.merge(key => value)
      else
        nested = hash.fetch(key, {})
        hash.merge(key => deep_put(nested, path[1..], value))
      end
    end

    private_class_method :deep_put
  end
end
