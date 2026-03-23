# frozen_string_literal: true

module Plushie
  module Type
    # Placement value for the tooltip `position` prop.
    #
    # @example
    #   tooltip("tip", "Helpful text", position: :bottom)
    module Position
      # Valid position values.
      # @api private
      VALID = %i[top bottom left right follow_cursor].freeze

      # @param value [Symbol] :top, :bottom, :left, :right, :follow_cursor
      # @return [String]
      def self.encode(value)
        raise ArgumentError, "invalid position: #{value.inspect}" unless VALID.include?(value)
        value.to_s
      end
    end
  end
end
