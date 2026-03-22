# frozen_string_literal: true

require_relative "shape/dash"
require_relative "shape/stroke"
require_relative "shape/linear_gradient"
require_relative "shape/shape_style"
require_relative "shape/drag_bounds"
require_relative "shape/hit_rect"
require_relative "shape/interactive"
require_relative "shape/rect"
require_relative "shape/circle"
require_relative "shape/line"
require_relative "shape/canvas_text"
require_relative "shape/path"
require_relative "shape/group"
require_relative "shape/canvas_image"
require_relative "shape/canvas_svg"
require_relative "shape/transform"
require_relative "shape/clip"

module Plushie
  module Canvas
    # Pure builder functions for canvas shape descriptors.
    #
    # Returns typed Data structs with #to_wire methods for wire
    # transport. Use these inside canvas DSL blocks or pass to
    # Widget::Canvas#set_shapes / #add_layer.
    module Shape
      module_function

      # Rectangle shape.
      def rect(x, y, w, h, **opts)
        Rect.new(x: x, y: y, w: w, h: h, **opts)
      end

      # Circle shape.
      def circle(x, y, r, **opts)
        Circle.new(x: x, y: y, r: r, **opts)
      end

      # Line shape.
      def line(x1, y1, x2, y2, **opts)
        Line.new(x1: x1, y1: y1, x2: x2, y2: y2, **opts)
      end

      # Text shape (canvas context).
      def canvas_text(x, y, content, **opts)
        CanvasText.new(x: x, y: y, content: content, **opts)
      end

      # Arbitrary path shape built from path commands.
      def path(commands, **opts)
        Path.new(commands: commands, **opts)
      end

      # Canvas image shape.
      def canvas_image(source, x, y, w, h, **opts)
        CanvasImage.new(source: source, x: x, y: y, w: w, h: h, **opts)
      end

      # Canvas SVG shape.
      def canvas_svg(source, x, y, w, h, **opts)
        CanvasSvg.new(source: source, x: x, y: y, w: w, h: h, **opts)
      end

      # Group of shapes.
      def group(shapes, **opts)
        Group.new(shapes: shapes, **opts)
      end

      # -- Path commands --------------------------------------------------------

      def move_to(x, y) = ["move_to", x, y]
      def line_to(x, y) = ["line_to", x, y]
      def close = ["close"]

      def bezier_to(cp1x, cp1y, cp2x, cp2y, x, y)
        ["bezier_to", cp1x, cp1y, cp2x, cp2y, x, y]
      end

      def quadratic_to(cpx, cpy, x, y)
        ["quadratic_to", cpx, cpy, x, y]
      end

      def arc(cx, cy, r, start_angle, end_angle)
        ["arc", cx, cy, r, start_angle, end_angle]
      end

      # -- Style helpers --------------------------------------------------------

      # Stroke descriptor. Returns a typed Stroke struct.
      def stroke(color, width, **opts)
        Stroke.new(color: color, width: width, **opts)
      end

      # Linear gradient descriptor. Returns a typed LinearGradient struct.
      def linear_gradient(from, to, stops)
        LinearGradient.new(from: from, to: to, stops: stops)
      end

      # -- Transform commands ---------------------------------------------------

      # Push (save) the current transform state onto the stack.
      def push_transform = PushTransform.new

      # Pop (restore) the previously saved transform state from the stack.
      def pop_transform = PopTransform.new

      # Translate the coordinate origin.
      def translate(x, y) = Translate.new(x: x, y: y)

      # Rotate the coordinate system (angle in radians).
      def rotate(angle) = Rotate.new(angle: angle)

      # Scale the coordinate system.
      def scale(x, y) = Scale.new(x: x, y: y)

      # -- Clipping commands ----------------------------------------------------

      # Push a clipping rectangle onto the clip stack.
      def push_clip(x, y, w, h) = PushClip.new(x: x, y: y, w: w, h: h)

      # Pop the most recent clipping rectangle.
      def pop_clip = PopClip.new
    end
  end
end
