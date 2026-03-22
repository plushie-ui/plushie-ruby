# frozen_string_literal: true

module Plushie
  module Type
    # Per-instance widget style overrides.
    #
    # A StyleMap crosses the IPC boundary as a plain map with optional
    # base preset and per-state overrides (hovered, pressed, disabled, focused).
    #
    # @example Extend a preset
    #   style: { base: :secondary, background: "#ff0000" }
    #
    # @example Full custom
    #   StyleMap.new
    #     .background("#333")
    #     .text_color("#fff")
    #     .border(Border.new.width(1).color("#555"))
    #     .hovered(background: "#444")
    #
    # @example In DSL
    #   button("save", "Save", style: :primary)
    #   button("save", "Save", style: { base: :primary, text_color: "#fff" })
    module StyleMap
      Spec = Data.define(:base, :background, :text_color, :border, :shadow,
        :hovered, :pressed, :disabled, :focused) do
        def initialize(base: nil, background: nil, text_color: nil,
          border: nil, shadow: nil, hovered: nil, pressed: nil,
          disabled: nil, focused: nil)
          super
        end

        def with(**changes)
          self.class.new(**to_h.merge(changes))
        end

        # @return [Hash] wire-ready map with nil fields stripped
        def to_wire
          h = {}
          h[:base] = base.to_s if base
          h[:background] = background if background
          h[:text_color] = text_color if text_color
          h[:border] = Border.encode(border) if border
          h[:shadow] = Shadow.encode(shadow) if shadow
          h[:hovered] = encode_state(hovered) if hovered
          h[:pressed] = encode_state(pressed) if pressed
          h[:disabled] = encode_state(disabled) if disabled
          h[:focused] = encode_state(focused) if focused
          h
        end

        private

        def encode_state(state)
          return nil unless state
          state.each_with_object({}) do |(k, v), h|
            h[k] = case k
            when :border then Border.encode(v)
            when :shadow then Shadow.encode(v)
            else v
            end
          end
        end
      end

      FIELD_KEYS = %i[base background text_color border shadow hovered pressed disabled focused].freeze

      module_function

      # Construct from keyword options.
      # @param opts [Hash]
      # @return [Spec]
      def from_opts(opts)
        Spec.new(**opts.slice(*FIELD_KEYS))
      end

      # Encode a style value for the wire protocol.
      # Accepts a symbol (preset name), a Hash, or a Spec.
      #
      # @param value [Symbol, Hash, Spec, String, nil]
      # @return [String, Hash, nil]
      def encode(value)
        case value
        when Symbol then value.to_s
        when String then value
        when Spec then value.to_wire
        when Hash then value
        when nil then nil
        else raise ArgumentError, "invalid style: #{value.inspect}"
        end
      end
    end
  end
end
