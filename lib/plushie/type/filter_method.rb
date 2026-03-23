# frozen_string_literal: true

module Plushie
  module Type
    # Interpolation mode for the image `filter_method` prop.
    #
    # @example
    #   image("pixel_art", src, filter_method: :nearest)
    module FilterMethod
      # Valid filter methods.
      # @api private
      VALID = %i[nearest linear].freeze

      # @param value [Symbol] :nearest, :linear
      # @return [String]
      def self.encode(value)
        raise ArgumentError, "invalid filter_method: #{value.inspect}" unless VALID.include?(value)
        value.to_s
      end
    end
  end
end
