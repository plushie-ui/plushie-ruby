# frozen_string_literal: true

module Plushie
  module Type
    # Alignment values for `align_x` and `align_y` widget props.
    #
    # Horizontal: :left, :center, :right (aliases: :start = :left, :end = :right)
    # Vertical: :top, :center, :bottom (aliases: :start = :top, :end = :bottom)
    #
    # @example
    #   column(align_x: :center)
    #   text("hello", align_x: :right)
    module Alignment
      VALID = %i[left center right top bottom start end].freeze

      # Encode an alignment value to the wire format.
      #
      # @param value [Symbol] :left, :center, :right, :top, :bottom, :start, :end
      # @return [String]
      def self.encode(value)
        raise ArgumentError, "invalid alignment: #{value.inspect}" unless VALID.include?(value)
        value.to_s
      end
    end
  end
end
