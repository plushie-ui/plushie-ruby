# frozen_string_literal: true

module Plushie
  module Type
    # Padding specification with per-side values.
    #
    # Accepts a uniform number, [vertical, horizontal], [top, right, bottom, left],
    # a Hash with :top/:right/:bottom/:left keys, or a Padding struct.
    #
    # @example Uniform
    #   column(padding: 16)
    #
    # @example Vertical/horizontal
    #   column(padding: [8, 16])
    #
    # @example Per-side
    #   column(padding: { top: 8, bottom: 16 })
    #
    # @example Four values
    #   column(padding: [4, 8, 12, 16])
    module Padding
      Pad = Data.define(:top, :right, :bottom, :left) do
        def initialize(top: nil, right: nil, bottom: nil, left: nil)
          super
        end

        # @return [Hash] wire-ready hash with nil fields stripped
        def to_wire
          h = {}
          h[:top] = top unless top.nil?
          h[:right] = right unless right.nil?
          h[:bottom] = bottom unless bottom.nil?
          h[:left] = left unless left.nil?
          h
        end
      end

      FIELD_KEYS = %i[top right bottom left].freeze

      module_function

      # Construct a Padding struct from keyword options.
      #
      # @param opts [Hash] :top, :right, :bottom, :left (all optional)
      # @return [Pad]
      def from_opts(opts)
        unknown = opts.keys - FIELD_KEYS
        raise ArgumentError, "unknown padding fields: #{unknown.inspect}. Valid: #{FIELD_KEYS.inspect}" if unknown.any?
        Pad.new(**opts.slice(*FIELD_KEYS))
      end

      # Normalise any padding input to a canonical four-side hash.
      #
      # @param value [Numeric, Array, Hash, Pad] the padding value
      # @return [Hash] { top:, right:, bottom:, left: }
      def cast(value)
        case value
        when Numeric
          {top: value, right: value, bottom: value, left: value}
        when Array
          case value.length
          when 2 then {top: value[0], right: value[1], bottom: value[0], left: value[1]}
          when 4 then {top: value[0], right: value[1], bottom: value[2], left: value[3]}
          else raise ArgumentError, "padding array must have 2 or 4 elements, got #{value.length}"
          end
        when Pad
          value.to_wire
        when Hash
          value.slice(:top, :right, :bottom, :left).compact
        else
          raise ArgumentError, "invalid padding: #{value.inspect}"
        end
      end

      # Encode a padding value for the wire protocol.
      #
      # @param value [Numeric, Array, Hash, Pad]
      # @return [Numeric, Hash]
      def encode(value)
        case value
        when Numeric then value
        when Pad then cast(value)
        else cast(value)
        end
      end
    end
  end
end
