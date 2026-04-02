# frozen_string_literal: true

module Plushie
  module Widget
    # Image -- display an image from a file path or URL.
    #
    # @example
    #   img = Plushie::Widget::Image.new("avatar", "/path/to/photo.png",
    #     width: 64, height: 64, content_fit: :cover, border_radius: 32)
    #   node = img.build
    #
    # Props:
    # - source (string) -- image file path or URL.
    # - width (length) -- display width.
    # - height (length) -- display height.
    # - content_fit (symbol) -- how the image fits: :contain, :cover, :fill, etc.
    # - rotation (number) -- rotation angle in degrees.
    # - opacity (number) -- opacity from 0.0 to 1.0.
    # - border_radius (number) -- corner radius in pixels.
    # - filter_method (symbol) -- resampling filter: :nearest, :linear.
    # - expand (boolean) -- expand to fill available space.
    # - scale (number) -- image scale factor.
    # - crop (hash) -- crop region { x, y, width, height }.
    # - alt (string) -- alt text for accessibility.
    # - description (string) -- longer description for accessibility.
    # - decorative (boolean) -- mark as decorative (hidden from a11y tree).
    # - a11y (hash) -- accessibility overrides.
    class Image < BuiltIn
      wire_type :image
      children :none
      positional :source, default: nil
      prop :source, :width, :height, :content_fit, :rotation, :opacity,
        :border_radius, :filter_method, :expand, :scale, :crop,
        :alt, :description, :decorative, :a11y
    end
  end
end
