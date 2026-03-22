# frozen_string_literal: true

module Plushie
  module Type
    # Font specification with family, weight, style, and stretch.
    #
    # Accepts :default, :monospace, a family name string, or a Font struct
    # with detailed properties.
    #
    # @example Simple
    #   text("msg", "Hello", font: :monospace)
    #   text("msg", "Hello", font: "Fira Code")
    #
    # @example Detailed
    #   Font.from_opts(family: "Inter", weight: :bold, style: :italic)
    module Font
      WEIGHTS = %i[thin extra_light light normal medium semi_bold bold extra_bold black].freeze
      STYLES = %i[normal italic oblique].freeze
      STRETCHES = %i[ultra_condensed extra_condensed condensed semi_condensed
        normal semi_expanded expanded extra_expanded ultra_expanded].freeze

      Spec = Data.define(:family, :weight, :style, :stretch) do
        def initialize(family: nil, weight: nil, style: nil, stretch: nil)
          super
        end

        def with(**changes)
          self.class.new(**to_h.merge(changes))
        end
      end

      FIELD_KEYS = %i[family weight style stretch].freeze

      module_function

      # Construct from keyword options.
      # @param opts [Hash] :family, :weight, :style, :stretch
      # @return [Spec]
      def from_opts(opts)
        unknown = opts.keys - FIELD_KEYS
        raise ArgumentError, "unknown font fields: #{unknown.inspect}" if unknown.any?
        Spec.new(**opts.slice(*FIELD_KEYS))
      end

      # Encode a font value for the wire protocol.
      #
      # @param value [Symbol, String, Spec, Hash]
      # @return [String, Hash]
      def encode(value)
        case value
        when :default then "default"
        when :monospace then "monospace"
        when String then {family: value}
        when Spec then encode_spec(value)
        when Hash then encode_spec(Spec.new(**value.slice(*FIELD_KEYS)))
        else raise ArgumentError, "invalid font: #{value.inspect}"
        end
      end

      # Convert a Spec to a wire-ready hash.
      def encode_spec(spec)
        h = {}
        h[:family] = spec.family if spec.family
        h[:weight] = pascal_case(spec.weight) if spec.weight
        h[:style] = pascal_case(spec.style) if spec.style
        h[:stretch] = pascal_case(spec.stretch) if spec.stretch
        h
      end

      # Convert a snake_case symbol to PascalCase string.
      # :extra_bold -> "ExtraBold"
      def pascal_case(sym)
        sym.to_s.split("_").map(&:capitalize).join
      end
    end
  end
end
