# frozen_string_literal: true

module Plushie
  # Undo/redo stack for reversible commands. Pure data structure, no threads.
  #
  # Each command provides an +apply+ proc and an +undo+ proc. The stack
  # tracks entries so that undo moves an entry to the redo stack (calling
  # the undo proc) and redo moves it back (calling the apply proc).
  #
  # == Max size
  #
  # The undo stack is bounded by +:max_size+ (default 100). When a push
  # exceeds the limit, the oldest entries are dropped. The redo stack is
  # unbounded (it can only shrink or be cleared, never grow past the undo
  # stack size).
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
  #   u = Plushie::Undo.push(u, cmd)
  #   Plushie::Undo.current(u)  #=> 1
  #   u = Plushie::Undo.undo(u)
  #   Plushie::Undo.current(u)  #=> 0
  #
  class Undo
    # Default maximum undo stack entries before oldest are dropped.
    DEFAULT_MAX_SIZE = 100

    # Immutable undo state.
    State = ::Data.define(:current, :max_size, :undo_size, :undo_stack, :redo_stack) do
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
    # @param max_size [Integer] maximum undo entries (default 100). Oldest
    #   entries are dropped silently when exceeded.
    # @return [State]
    def self.new(model, max_size: DEFAULT_MAX_SIZE)
      unless max_size.is_a?(Integer) && max_size > 0
        raise ArgumentError, "expected max_size to be a positive integer, got: #{max_size.inspect}"
      end

      State.new(current: model, max_size: max_size, undo_size: 0, undo_stack: [], redo_stack: [])
    end

    # Push a command onto the undo stack, updating the current model.
    # Clears the redo stack.
    #
    # If the command carries a +:coalesce+ key that matches the top of the
    # undo stack and the time delta is within +:coalesce_window_ms+, the
    # entry is merged rather than pushed.
    #
    # The command must be a Hash with +:apply+ and +:undo+ keys (both
    # callable). Optional keys: +:label+, +:coalesce+, +:coalesce_window_ms+.
    #
    # @param u [State]
    # @param command [Hash] must have :apply and :undo procs
    # @return [State]
    def self.push(u, command)
      callable = command[:apply]
      raise ArgumentError, "command :apply must be callable" unless callable.respond_to?(:call)
      raise ArgumentError, "command :undo must be callable" unless command[:undo].respond_to?(:call)

      now = timestamp
      new_model = callable.call(u.current)

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
        new_stack = [entry, *u.undo_stack]
        new_size = u.undo_size + 1

        # Trim oldest entries if over max_size
        if new_size > u.max_size
          new_stack = new_stack[0, u.max_size]
          new_size = u.max_size
        end

        u.with(
          current: new_model,
          undo_stack: new_stack,
          undo_size: new_size,
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
        undo_size: u.undo_size - 1,
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
        undo_stack: [entry, *u.undo_stack],
        undo_size: u.undo_size + 1
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
