# frozen_string_literal: true

module Plushie
  module Type
    # Theme selection for windows and the application.
    #
    # 22 built-in themes, :system for OS preference, or a custom palette map.
    #
    # @example Built-in theme
    #   window("main", theme: :dark)
    #   window("main", theme: :catppuccin_mocha)
    #
    # @example System preference
    #   window("main", theme: :system)
    module Theme
      # Built-in theme names.
      # @api private
      BUILTIN = %i[
        light dark
        dracula nord
        solarized_light solarized_dark
        gruvbox_light gruvbox_dark
        catppuccin_latte catppuccin_frappe catppuccin_macchiato catppuccin_mocha
        tokyo_night tokyo_night_storm tokyo_night_light
        kanagawa_wave kanagawa_dragon kanagawa_lotus
        moonfly nightfly
        oxocarbon ferra
      ].freeze

      module_function

      # Encode a theme value for the wire protocol.
      #
      # @param value [Symbol, Hash] built-in theme name, :system, or custom palette
      # @return [String, Hash]
      def encode(value)
        case value
        when :system then "system"
        when Symbol
          raise ArgumentError, "unknown theme: #{value.inspect}" unless BUILTIN.include?(value)
          value.to_s
        when Hash then value
        when String then value
        else raise ArgumentError, "invalid theme: #{value.inspect}"
        end
      end
    end
  end
end
