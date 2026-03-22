# frozen_string_literal: true

module Plushie
  # Keyboard modifier state at the time of a key event.
  #
  # Each field is a boolean indicating whether that modifier was held.
  # Wraps a hash of modifier flags with query methods.
  #
  # == Fields
  #
  # - +ctrl+ -- Control key (Ctrl on Windows/Linux).
  # - +shift+ -- Shift key.
  # - +alt+ -- Alt key (Option on macOS).
  # - +logo+ -- Logo/Super key (Windows key, Command symbol on macOS).
  # - +command+ -- Platform command key (Ctrl on Windows/Linux, Cmd on macOS).
  #
  # @example
  #   mods = Plushie::KeyModifiers.new(ctrl: true, shift: false)
  #   mods.ctrl?    #=> true
  #   mods.shift?   #=> false
  #   mods.command?  #=> false
  #
  class KeyModifiers
    Mods = ::Data.define(:ctrl, :shift, :alt, :logo, :command)

    # Create a new KeyModifiers with the given flags.
    # All flags default to false.
    #
    # @param ctrl [Boolean]
    # @param shift [Boolean]
    # @param alt [Boolean]
    # @param logo [Boolean]
    # @param command [Boolean]
    # @return [KeyModifiers]
    def initialize(ctrl: false, shift: false, alt: false, logo: false, command: false)
      @mods = Mods.new(ctrl: ctrl, shift: shift, alt: alt, logo: logo, command: command)
    end

    # Create from a hash (e.g. from decoded event data).
    #
    # @param hash [Hash] modifier flags
    # @return [KeyModifiers]
    def self.from_hash(hash)
      new(
        ctrl: !!hash[:ctrl],
        shift: !!hash[:shift],
        alt: !!hash[:alt],
        logo: !!hash[:logo],
        command: !!hash[:command]
      )
    end

    # Returns true if the Ctrl modifier is active.
    # @return [Boolean]
    def ctrl? = @mods.ctrl

    # Returns true if the Shift modifier is active.
    # @return [Boolean]
    def shift? = @mods.shift

    # Returns true if the Alt modifier is active.
    # @return [Boolean]
    def alt? = @mods.alt

    # Returns true if the Logo/Super modifier is active.
    # @return [Boolean]
    def logo? = @mods.logo

    # Returns true if the platform Command modifier is active.
    # @return [Boolean]
    def command? = @mods.command

    # Return the modifiers as a hash.
    # @return [Hash]
    def to_h = @mods.to_h

    def ==(other)
      other.is_a?(KeyModifiers) && to_h == other.to_h
    end
    alias_method :eql?, :==

    def hash
      to_h.hash
    end

    def inspect
      flags = to_h.select { |_, v| v }.keys.join(", ")
      "#<Plushie::KeyModifiers #{flags.empty? ? "(none)" : flags}>"
    end
  end
end
