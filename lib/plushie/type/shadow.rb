# frozen_string_literal: true

module Plushie
  module Type
    # Shadow specification for widget styling.
    #
    # Wire format: { color: "#00000080", offset: [4, 4], blur_radius: 8.0 }
    #
    # @example Builder pattern
    #   Shadow.new.color("#00000040").offset(2, 2).blur_radius(6)
    #
    # @example DSL block form
    #   container("card") do
    #     shadow do
    #       color "#00000022"
    #       offset_y 2
    #       blur_radius 4
    #     end
    #   end
    module Shadow
      Spec = Data.define(:color, :offset_x, :offset_y, :blur_radius) do
        def initialize(color: "#000000", offset_x: 0, offset_y: 0, blur_radius: 0)
          super
        end

        def with(**changes)
          self.class.new(**to_h.merge(changes))
        end

        # @return [Hash] wire-ready map
        def to_wire
          {color: color, offset: [offset_x, offset_y], blur_radius: blur_radius}
        end
      end

      FIELD_KEYS = %i[color offset offset_x offset_y blur_radius].freeze

      module_function

      # Create a new shadow with defaults.
      # @return [Spec]
      def new
        Spec.new
      end

      # Construct from keyword options.
      # @param opts [Hash] :color, :offset (array), :offset_x, :offset_y, :blur_radius
      # @return [Spec]
      def from_opts(opts)
        spec = Spec.new
        spec = spec.with(color: Color.cast(opts[:color])) if opts[:color]
        if opts[:offset]
          x, y = opts[:offset]
          spec = spec.with(offset_x: x, offset_y: y)
        end
        spec = spec.with(offset_x: opts[:offset_x]) if opts[:offset_x]
        spec = spec.with(offset_y: opts[:offset_y]) if opts[:offset_y]
        spec = spec.with(blur_radius: opts[:blur_radius]) if opts[:blur_radius]
        spec
      end

      # Encode for the wire protocol.
      # @param value [Spec, Hash, nil]
      # @return [Hash, nil]
      def encode(value)
        case value
        when Spec then value.to_wire
        when Hash then value
        when nil then nil
        else raise ArgumentError, "invalid shadow: #{value.inspect}"
        end
      end
    end
  end
end
