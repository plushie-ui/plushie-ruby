# frozen_string_literal: true

module Plushie
  module Type
    # Scaling mode for the `content_fit` prop on image and SVG widgets.
    #
    # @example
    #   image("photo", "/path/to/img.png", content_fit: :cover)
    module ContentFit
      VALID = %i[contain cover fill none scale_down].freeze

      # @param value [Symbol] :contain, :cover, :fill, :none, :scale_down
      # @return [String]
      def self.encode(value)
        raise ArgumentError, "invalid content_fit: #{value.inspect}" unless VALID.include?(value)
        value.to_s
      end
    end
  end
end
