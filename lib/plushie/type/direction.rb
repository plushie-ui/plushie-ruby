# frozen_string_literal: true

module Plushie
  module Type
    # Orientation for the scrollable `direction` prop and rule widget.
    #
    # @example
    #   scrollable("content", direction: :vertical)
    #   rule(direction: :horizontal)
    module Direction
      # Valid direction values.
      # @api private
      VALID = %i[horizontal vertical both].freeze

      # @param value [Symbol] :horizontal, :vertical, :both
      # @return [String]
      def self.encode(value)
        raise ArgumentError, "invalid direction: #{value.inspect}" unless VALID.include?(value)
        value.to_s
      end
    end
  end
end
