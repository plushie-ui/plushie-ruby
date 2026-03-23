# frozen_string_literal: true

module Plushie
  module Type
    # Line-break strategy for the text `wrapping` prop.
    #
    # @example
    #   text("content", long_text, wrapping: :word)
    module Wrapping
      # Valid text wrapping modes.
      # @api private
      VALID = %i[none word glyph word_or_glyph].freeze

      # @param value [Symbol] :none, :word, :glyph, :word_or_glyph
      # @return [String]
      def self.encode(value)
        raise ArgumentError, "invalid wrapping: #{value.inspect}" unless VALID.include?(value)
        value.to_s
      end
    end
  end
end
