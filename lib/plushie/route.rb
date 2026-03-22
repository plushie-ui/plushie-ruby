# frozen_string_literal: true

module Plushie
  # Client-side routing for multi-view apps. Pure data structure
  # maintaining a navigation stack of [path, params] entries.
  #
  # The stack is last-in-first-out. +push+ adds a new entry on top;
  # +pop+ removes the top entry (never pops the last one). +current+
  # and +params+ read from the top of the stack.
  #
  # @example
  #   route = Plushie::Route.new(:home)
  #   route = Plushie::Route.push(route, :settings, tab: "general")
  #   Plushie::Route.current(route)   #=> :settings
  #   Plushie::Route.params(route)    #=> { tab: "general" }
  #   route = Plushie::Route.pop(route)
  #   Plushie::Route.current(route)   #=> :home
  #
  class Route
    # Immutable route state.
    State = ::Data.define(:stack) do
      include Plushie::Model::Extensions
    end

    # Creates a new route with +initial_path+ at the bottom of the stack.
    #
    # @param initial_path [Object] the root path
    # @param params [Hash] optional params for the root entry
    # @return [State]
    def self.new(initial_path, **params)
      State.new(stack: [[initial_path, params]].freeze)
    end

    # Pushes a new +path+ (with optional +params+) onto the navigation stack.
    #
    # @param route [State]
    # @param path [Object]
    # @param params [Hash]
    # @return [State]
    def self.push(route, path, **params)
      route.with(stack: [[path, params], *route.stack].freeze)
    end

    # Pops the top entry from the stack. Returns the route unchanged if
    # only one entry remains (the root is never popped).
    #
    # @param route [State]
    # @return [State]
    def self.pop(route)
      return route if route.stack.length <= 1
      route.with(stack: route.stack[1..].freeze)
    end

    # Returns the current (top) path.
    #
    # @param route [State]
    # @return [Object]
    def self.current(route)
      route.stack.first[0]
    end

    # Returns the params associated with the current (top) path.
    #
    # @param route [State]
    # @return [Hash]
    def self.params(route)
      route.stack.first[1]
    end

    # Returns true if there is more than one entry on the stack.
    #
    # @param route [State]
    # @return [Boolean]
    def self.can_go_back?(route)
      route.stack.length > 1
    end

    # Returns a list of all paths in the stack, most recent first.
    #
    # @param route [State]
    # @return [Array]
    def self.history(route)
      route.stack.map(&:first)
    end
  end
end
