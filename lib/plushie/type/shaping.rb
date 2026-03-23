# frozen_string_literal: true

module Plushie
  module Type
    # Text shaping strategy for the text `shaping` prop.
    #
    # @example
    #   text("greeting", "Hello", shaping: :advanced)
    module Shaping
      # Valid text shaping modes.
      # @api private
      VALID = %i[basic advanced auto].freeze

      # @param value [Symbol] :basic, :advanced, :auto
      # @return [String]
      def self.encode(value)
        raise ArgumentError, "invalid shaping: #{value.inspect}" unless VALID.include?(value)
        value.to_s
      end
    end
  end
end
