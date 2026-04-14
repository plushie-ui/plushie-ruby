# frozen_string_literal: true

module Plushie
  class Command
    # Image handle management commands.
    #
    # @example
    #   Command::Image.create_image("sprite", png_data)
    #   Command.create_image("sprite", png_data)  # also works via delegation
    #
    module Image
      module_function

      # Create an image from encoded data (PNG/JPEG) or raw RGBA pixels.
      # @param handle [String] image handle name
      # @param data [String, nil] encoded image bytes
      # @param width [Integer, nil] pixel width (for raw pixels)
      # @param height [Integer, nil] pixel height (for raw pixels)
      # @param pixels [String, nil] raw RGBA pixel data
      # @return [Cmd]
      def create_image(handle, data = nil, width: nil, height: nil, pixels: nil)
        if pixels
          Cmd.new(type: :image_op, payload: {op: "create_image", handle:, pixels:, width:, height:})
        else
          Cmd.new(type: :image_op, payload: {op: "create_image", handle:, data:})
        end
      end

      # Update an existing image handle.
      # @param handle [String]
      # @param data [String, nil] encoded image bytes
      # @param width [Integer, nil] pixel width (for raw pixels)
      # @param height [Integer, nil] pixel height (for raw pixels)
      # @param pixels [String, nil] raw RGBA pixel data
      # @return [Cmd]
      def update_image(handle, data = nil, width: nil, height: nil, pixels: nil)
        if pixels
          Cmd.new(type: :image_op, payload: {op: "update_image", handle:, pixels:, width:, height:})
        else
          Cmd.new(type: :image_op, payload: {op: "update_image", handle:, data:})
        end
      end

      # Delete an image handle.
      # @param handle [String]
      # @return [Cmd]
      def delete_image(handle) = Cmd.new(type: :image_op, payload: {op: "delete_image", handle:})

      # List all image handles. Result via Event::System.
      # @param tag [Symbol]
      # @return [Cmd]
      def list_images(tag) = Cmd.new(type: :widget_op, payload: {op: "list_images", tag: tag.to_s})

      # Remove all image handles.
      # @return [Cmd]
      def clear_images = Cmd.new(type: :widget_op, payload: {op: "clear_images"})
    end
  end
end
