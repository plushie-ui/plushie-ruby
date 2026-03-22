# frozen_string_literal: true

module Plushie
  # Undo/redo stack for reversible commands. Pure data structure, no threads.
  #
  # Each command provides an +apply+ proc and an +undo+ proc. The stack
  # tracks entries so that undo moves an entry to the redo stack (calling
  # the undo proc) and redo moves it back (calling the apply proc).
  #
  # == Coalescing
  #
  # Commands with the same +:coalesce+ key that arrive within
  # +:coalesce_window_ms+ of each other are merged into a single undo entry.
  # The merged entry keeps the *original* undo proc (so one undo reverses
  # all coalesced changes) and composes the apply procs.
  #
  # @example
  #   u = Plushie::Undo.new(0)
  #   cmd = { apply: ->(n) { n + 1 }, undo: ->(n) { n - 1 } }
  #   u = Plushie::Undo.apply(u, cmd)
  #   Plushie::Undo.current(u)  #=> 1
  #   u = Plushie::Undo.undo(u)
  #   Plushie::Undo.current(u)  #=> 0
  #
  class Undo
    # Immutable undo state.
    State = ::Data.define(:current, :undo_stack, :redo_stack) do
      include Plushie::Model::Extensions
    end

    # Immutable undo entry.
    Entry = ::Data.define(:apply_fn, :undo_fn, :label, :coalesce, :timestamp) do
      include Plushie::Model::Extensions
    end

    # Timestamp source. Override via thread-local for deterministic tests.
    # @api private
    def self.timestamp
      Thread.current[:plushie_undo_timestamp] || Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
    end

    # Create a new undo stack with +model+ as the initial state.
    #
    # @param model [Object] initial state
    # @return [State]
    def self.new(model)
      State.new(current: model, undo_stack: [], redo_stack: [])
    end

    # Apply a command, updating the current model and pushing an entry onto
    # the undo stack. Clears the redo stack.
    #
    # If the command carries a +:coalesce+ key that matches the top of the
    # undo stack and the time delta is within +:coalesce_window_ms+, the
    # entry is merged rather than pushed.
    #
    # @param u [State]
    # @param command [Hash] must have :apply and :undo procs; optional :label,
    #   :coalesce, :coalesce_window_ms
    # @return [State]
    def self.apply(u, command)
      now = timestamp
      new_model = command[:apply].call(u.current)

      coalesced = maybe_coalesce(u, command, now)

      if coalesced
        u.with(
          current: new_model,
          undo_stack: [coalesced, *u.undo_stack[1..]],
          redo_stack: []
        )
      else
        entry = Entry.new(
          apply_fn: command[:apply],
          undo_fn: command[:undo],
          label: command[:label],
          coalesce: command[:coalesce],
          timestamp: now
        )
        u.with(
          current: new_model,
          undo_stack: [entry, *u.undo_stack],
          redo_stack: []
        )
      end
    end

    # Undo the last command. Returns unchanged if the undo stack is empty.
    #
    # @param u [State]
    # @return [State]
    def self.undo(u)
      return u if u.undo_stack.empty?

      entry = u.undo_stack.first
      old_model = entry.undo_fn.call(u.current)

      u.with(
        current: old_model,
        undo_stack: u.undo_stack[1..],
        redo_stack: [entry, *u.redo_stack]
      )
    end

    # Redo the last undone command. Returns unchanged if the redo stack is empty.
    #
    # @param u [State]
    # @return [State]
    def self.redo(u)
      return u if u.redo_stack.empty?

      entry = u.redo_stack.first
      new_model = entry.apply_fn.call(u.current)

      u.with(
        current: new_model,
        redo_stack: u.redo_stack[1..],
        undo_stack: [entry, *u.undo_stack]
      )
    end

    # Return the current model.
    #
    # @param u [State]
    # @return [Object]
    def self.current(u) = u.current

    # Return true if there are entries on the undo stack.
    #
    # @param u [State]
    # @return [Boolean]
    def self.can_undo?(u)
      !u.undo_stack.empty?
    end

    # Return true if there are entries on the redo stack.
    #
    # @param u [State]
    # @return [Boolean]
    def self.can_redo?(u)
      !u.redo_stack.empty?
    end

    # Return the labels from the undo stack, most recent first.
    #
    # @param u [State]
    # @return [Array<String, nil>]
    def self.history(u)
      u.undo_stack.map(&:label)
    end

    # -- Private ------------------------------------------------------------

    # @api private
    def self.maybe_coalesce(u, command, now)
      return nil if u.undo_stack.empty?

      top = u.undo_stack.first
      coalesce_key = command[:coalesce]
      window = command[:coalesce_window_ms] || 0

      if coalesce_key && coalesce_key == top.coalesce && now - top.timestamp <= window
        top.with(
          apply_fn: ->(model) { command[:apply].call(top.apply_fn.call(model)) },
          undo_fn: ->(model) { top.undo_fn.call(command[:undo].call(model)) },
          timestamp: now
        )
      end
    end

    private_class_method :maybe_coalesce
  end
end
