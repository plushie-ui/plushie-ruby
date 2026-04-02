# frozen_string_literal: true

module Plushie
  # Property type modules for widget configuration.
  module Type
    # Alignment values for `align_x` and `align_y` widget props.
    #
    # Horizontal: :left, :center, :right.
    # Vertical: :top, :center, :bottom.
    #
    # @example
    #   column(align_x: :center)
    #   text("hello", align_x: :right)
    module Alignment
      # Valid alignment values.
      # @api private
      VALID = %i[left center right top bottom].freeze

      # Encode an alignment value to the wire format.
      #
      # @param value [Symbol] :left, :center, :right, :top, :bottom
      # @return [String]
      def self.encode(value)
        raise ArgumentError, "invalid alignment: #{value.inspect}" unless VALID.include?(value)
        value.to_s
      end
    end
  end
end
