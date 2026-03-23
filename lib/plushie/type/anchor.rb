# frozen_string_literal: true

module Plushie
  module Type
    # Anchor values for the scrollbar `alignment` prop.
    #
    # @example
    #   scrollable("list", anchor: :end)
    module Anchor
      # Valid anchor values.
      # @api private
      VALID = %i[start end].freeze

      # @param value [Symbol] :start, :end
      # @return [String]
      def self.encode(value)
        raise ArgumentError, "invalid anchor: #{value.inspect}" unless VALID.include?(value)
        value.to_s
      end
    end
  end
end
