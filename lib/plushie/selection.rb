# frozen_string_literal: true

module Plushie
  # Selection state for lists and tables. Pure data structure supporting
  # single, multi, and range selection modes.
  #
  # == Modes
  #
  # - +:single+ -- at most one item selected at a time.
  # - +:multi+ -- multiple items selectable; +extend: true+ adds to the set.
  # - +:range+ -- like multi, but +range_select+ selects a contiguous
  #   slice of the +order+ list between the anchor and the target.
  #
  # @example
  #   sel = Plushie::Selection.new(mode: :multi, order: ["a", "b", "c", "d"])
  #   sel = Plushie::Selection.select(sel, "b")
  #   sel = Plushie::Selection.select(sel, "d", extend: true)
  #   Plushie::Selection.selected(sel) #=> Set["b", "d"]
  #
  class Selection
    # Immutable selection state.
    State = ::Data.define(:mode, :selected, :anchor, :order) do
      include Plushie::Model::Extensions
    end

    # Creates a new selection state.
    #
    # @param mode [Symbol] selection mode: +:single+ (default), +:multi+, or +:range+
    # @param order [Array] ordered list of item IDs for range selection
    # @return [State]
    def self.new(mode: :single, order: [])
      State.new(mode: mode, selected: Set.new, anchor: nil, order: order)
    end

    # Selects +id+. In +:single+ mode, replaces the selection. In +:multi+
    # and +:range+ modes, replaces unless +extend: true+ is passed, in which
    # case +id+ is added to the existing selection.
    #
    # Sets the anchor to +id+ for subsequent range selections.
    #
    # @param sel [State]
    # @param id [Object]
    # @param extend [Boolean] add to existing selection (multi/range only)
    # @return [State]
    def self.select(sel, id, extend: false)
      if sel.mode == :single
        sel.with(selected: Set[id], anchor: id)
      elsif extend
        sel.with(selected: sel.selected | Set[id], anchor: id)
      else
        sel.with(selected: Set[id], anchor: id)
      end
    end

    # Toggles +id+ in the selection. If already selected, removes it;
    # otherwise adds it. In +:single+ mode, toggling a selected item
    # clears the selection entirely.
    #
    # @param sel [State]
    # @param id [Object]
    # @return [State]
    def self.toggle(sel, id)
      if sel.mode == :single
        if sel.selected.include?(id)
          sel.with(selected: Set.new, anchor: nil)
        else
          sel.with(selected: Set[id], anchor: id)
        end
      elsif sel.selected.include?(id)
        sel.with(selected: sel.selected - Set[id])
      else
        sel.with(selected: sel.selected | Set[id], anchor: id)
      end
    end

    # Removes +id+ from the selection.
    #
    # @param sel [State]
    # @param id [Object]
    # @return [State]
    def self.deselect(sel, id)
      sel.with(selected: sel.selected - Set[id])
    end

    # Clears all selected items and resets the anchor.
    #
    # @param sel [State]
    # @return [State]
    def self.clear(sel)
      sel.with(selected: Set.new, anchor: nil)
    end

    # Selects all items in +order+ between the current anchor and +id+
    # (inclusive). If there is no anchor, selects only +id+.
    #
    # Requires +order+ to have been set at creation time.
    #
    # @param sel [State]
    # @param id [Object]
    # @return [State]
    def self.range_select(sel, id)
      if sel.anchor.nil?
        return sel.with(selected: Set[id], anchor: id)
      end

      anchor_idx = sel.order.index(sel.anchor)
      id_idx = sel.order.index(id)

      if anchor_idx.nil? || id_idx.nil?
        return sel.with(selected: Set[id], anchor: id)
      end

      lo, hi = [anchor_idx, id_idx].sort
      range_ids = sel.order[lo..hi]
      sel.with(selected: Set.new(range_ids))
    end

    # Returns the Set of currently selected item IDs.
    #
    # @param sel [State]
    # @return [Set]
    def self.selected(sel)
      sel.selected
    end

    # Returns true if +id+ is currently selected.
    #
    # @param sel [State]
    # @param id [Object]
    # @return [Boolean]
    def self.selected?(sel, id)
      sel.selected.include?(id)
    end
  end
end
