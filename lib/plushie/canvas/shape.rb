# frozen_string_literal: true

require_relative "shape/dash"
require_relative "shape/stroke"
require_relative "shape/linear_gradient"
require_relative "shape/shape_style"
require_relative "shape/drag_bounds"
require_relative "shape/hit_rect"
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
  # Canvas drawing primitives for the canvas widget.
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

      # Group of shapes. Accepts an optional id as first positional arg.
      #
      # x: and y: kwargs are desugared into a leading Translate in the
      # transforms array.
      #
      # @param id_or_children [String, Array] group id or children array
      # @param children [Array, nil] children array when id is given
      def group(id_or_children = nil, children = nil, x: nil, y: nil, transforms: nil, **opts)
        if id_or_children.is_a?(String)
          id = id_or_children
          children ||= []
        else
          id = opts.delete(:id)
          children = id_or_children || children || []
        end

        xforms = Array(transforms)
        xforms.unshift(Translate.new(x: x, y: y)) if x || y

        Group.new(
          children: children,
          transforms: xforms.empty? ? nil : xforms,
          id: id,
          **opts
        )
      end

      # Wrap a shape with interactive properties. If the shape is a
      # Group, merge the interactive fields directly. If it is a leaf
      # shape, wrap it in a Group as the sole child.
      def interactive(shape, id, **opts)
        if shape.is_a?(Group)
          shape.with(id: id, **opts)
        else
          Group.new(children: [shape], id: id, **opts)
        end
      end

      # -- Path commands --------------------------------------------------------

      def move_to(x, y) = ["move_to", x, y]
      # Line segment to the given point.
      def line_to(x, y) = ["line_to", x, y]

      # Close the current path.
      def close = ["close"]

      # Cubic bezier curve segment.
      def bezier_to(cp1x, cp1y, cp2x, cp2y, x, y)
        ["bezier_to", cp1x, cp1y, cp2x, cp2y, x, y]
      end

      # Quadratic bezier curve segment.
      def quadratic_to(cpx, cpy, x, y)
        ["quadratic_to", cpx, cpy, x, y]
      end

      # Arc path segment.
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

      # -- Transform value constructors ----------------------------------------

      # Translate the coordinate origin.
      def translate(x, y) = Translate.new(x: x, y: y)

      # Rotate the coordinate system (angle in radians).
      def rotate(angle) = Rotate.new(angle: angle)

      # Scale the coordinate system (independent axes).
      def scale(x, y = nil)
        if y
          Scale.new(x: x, y: y)
        else
          Scale.new(factor: x)
        end
      end

      # Uniform scale convenience constructor.
      def scale_uniform(factor) = Scale.new(factor: factor)

      # -- Clipping value constructor ------------------------------------------

      # Clipping rectangle value.
      def clip(x, y, w, h) = Clip.new(x: x, y: y, w: w, h: h)
    end
  end
end
