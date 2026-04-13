# frozen_string_literal: true

module Plushie
  module Widget
    # QR Code: renders a QR code from a data string.
    #
    # @example
    #   qr = Plushie::Widget::QrCode.new("link", "https://example.com",
    #     cell_size: 6, error_correction: :high)
    #   node = qr.build
    #
    # Props:
    # - data (string): the data to encode.
    # - cell_size (number): size of each QR module in pixels.
    # - cell_color (string): color of dark modules.
    # - background (string): color of light modules.
    # - error_correction (symbol): :low, :medium, :quartile, :high.
    # - alt (string): accessible label.
    # - description (string): extended accessible description.
    # - a11y (hash): accessibility overrides.
    class QrCode < BuiltIn
      wire_type :qr_code
      children :none
      positional :data, default: nil
      prop :data, :cell_size, :cell_color, :background, :error_correction,
        :alt, :description, :a11y
    end
  end
end
