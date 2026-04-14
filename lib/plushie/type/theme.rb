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
    #
    # @example Custom theme
    #   Theme.custom("My Theme", base: :dark, primary: "#3b82f6", danger: "#ef4444")
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

      # Core palette seeds.
      CORE_SEEDS = %i[background text primary success danger warning].freeze

      # Color families with base/weak/strong shades.
      COLOR_FAMILIES = %i[primary secondary success warning danger].freeze

      # Background shade levels.
      BACKGROUND_SHADES = %i[
        background_base
        background_weakest background_weaker background_weak
        background_neutral
        background_strong background_stronger background_strongest
      ].freeze

      # All valid custom theme keys (computed once).
      VALID_CUSTOM_KEYS = begin
        shade_keys = COLOR_FAMILIES.flat_map { |f|
          %w[base weak strong].flat_map { |s|
            [:"#{f}_#{s}", :"#{f}_#{s}_text"]
          }
        }
        bg_keys = BACKGROUND_SHADES.flat_map { |s| [s, :"#{s}_text"] }
        (CORE_SEEDS + shade_keys + bg_keys).freeze
      end

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

      # Create a custom theme from a base and color overrides.
      #
      # All keys are validated against the known set of core seeds and
      # shade overrides. Unknown keys raise ArgumentError to catch typos.
      #
      # Note: :secondary is not a core seed. It is auto-derived from
      # :background and :text by iced's palette generator. Use shade
      # overrides (secondary_base, secondary_weak, secondary_strong
      # plus _text variants) for fine-grained control.
      #
      # @param name [String] theme display name
      # @param base [Symbol, nil] built-in theme to extend
      # @param overrides [Hash] color overrides (keys from VALID_CUSTOM_KEYS)
      # @return [Hash] wire-ready theme map
      def custom(name, base: nil, **overrides)
        validate_custom_keys!(overrides)

        result = {name: name}
        result[:base] = base.to_s if base

        overrides.each do |key, value|
          result[key] = Color.cast(value)
        end

        result
      end

      # @return [Array<Symbol>] all valid keys for custom theme overrides
      def valid_custom_keys = VALID_CUSTOM_KEYS

      # @api private
      def validate_custom_keys!(overrides)
        unknown = overrides.keys - VALID_CUSTOM_KEYS
        return if unknown.empty?

        raise ArgumentError,
          "unknown custom theme keys: #{unknown.map(&:inspect).join(", ")}. " \
          "Valid keys: core seeds (#{CORE_SEEDS.map(&:inspect).join(", ")}), " \
          "shade overrides ({family}_{base|weak|strong}[_text]), " \
          "background shades (background_{level}[_text])"
      end
      private_class_method :validate_custom_keys!
    end
  end
end
