# frozen_string_literal: true

module Plushie
  module Type
    # Border specification for container and widget styling.
    #
    # A border has color, width, and radius (uniform or per-corner).
    #
    # @example Builder pattern
    #   Border.new.color("#3366ff").width(2).rounded(8)
    #
    # @example DSL block form
    #   container("box") do
    #     border do
    #       color "#3366ff"
    #       width 2
    #       rounded 8
    #     end
    #   end
    #
    # @example Per-corner radius
    #   Border.new.width(1).radius(top_left: 8, top_right: 8, bottom_right: 0, bottom_left: 0)
    module Border
      Spec = Data.define(:color, :width, :radius) do
        def initialize(color: nil, width: 0, radius: 0)
          super
        end

        def with(**changes)
          self.class.new(**to_h.merge(changes))
        end

        # @return [Hash] wire-ready map
        def to_wire
          h = {width: width, radius: encode_radius}
          h[:color] = color unless color.nil?
          h
        end

        private

        def encode_radius
          case radius
          when Hash then radius.slice(:top_left, :top_right, :bottom_right, :bottom_left)
          else radius
          end
        end
      end

      FIELD_KEYS = %i[color width rounded radius].freeze

      module_function

      # Create a new border with defaults (no color, zero width, zero radius).
      # @return [Spec]
      def new
        Spec.new
      end

      # Construct from keyword options.
      # @param opts [Hash] :color, :width, :rounded, :radius
      # @return [Spec]
      def from_opts(opts)
        spec = Spec.new
        spec = spec.with(color: Color.cast(opts[:color])) if opts[:color]
        spec = spec.with(width: opts[:width]) if opts[:width]
        spec = spec.with(radius: opts[:rounded]) if opts[:rounded]
        spec = spec.with(radius: opts[:radius]) if opts[:radius]
        spec
      end

      # Encode a border value for the wire protocol.
      # @param value [Spec, Hash, nil]
      # @return [Hash, nil]
      def encode(value)
        case value
        when Spec then value.to_wire
        when Hash then value
        when nil then nil
        else raise ArgumentError, "invalid border: #{value.inspect}"
        end
      end
    end
  end
end
