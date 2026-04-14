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
    QrCode = Plushie::Widget.define(:qr_code) do
      children :none
      positional :data, default: nil
      prop :data, :cell_size, :total_size, :cell_color, :background,
        :error_correction, :alt, :description
      default_a11y role: :image
    end
  end
end
