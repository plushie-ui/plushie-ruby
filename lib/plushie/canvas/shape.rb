# frozen_string_literal: true

module Plushie
  module Canvas
    # Pure builder functions for canvas shape descriptors.
    #
    # Returns plain hashes with string-keyed type fields, matching the
    # wire protocol shape format. Use these inside canvas DSL blocks or
    # pass to Widget::Canvas#set_shapes / #add_layer.
    module Shape
      module_function

      # Rectangle shape.
      def rect(x, y, w, h, **opts)
        shape = {type: "rect", x: x, y: y, w: w, h: h}
        merge_common(shape, opts)
      end

      # Circle shape.
      def circle(x, y, r, **opts)
        shape = {type: "circle", x: x, y: y, r: r}
        merge_common(shape, opts)
      end

      # Line shape.
      def line(x1, y1, x2, y2, **opts)
        shape = {type: "line", x1: x1, y1: y1, x2: x2, y2: y2}
        merge_common(shape, opts)
      end

      # Text shape (canvas context).
      def canvas_text(x, y, content, **opts)
        shape = {type: "text", x: x, y: y, content: content}
        merge_common(shape, opts)
      end

      # Arbitrary path shape built from path commands.
      def path(commands, **opts)
        shape = {type: "path", commands: commands}
        merge_common(shape, opts)
      end

      # Canvas image shape.
      def canvas_image(source, x, y, w, h, **opts)
        shape = {type: "image", source: source, x: x, y: y, w: w, h: h}
        merge_common(shape, opts)
      end

      # Canvas SVG shape.
      def canvas_svg(source, x, y, w, h, **opts)
        shape = {type: "svg", source: source, x: x, y: y, w: w, h: h}
        merge_common(shape, opts)
      end

      # Group of shapes.
      def group(shapes, **opts)
        shape = {type: "group", shapes: shapes}
        merge_common(shape, opts)
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

      # Stroke descriptor.
      def stroke(color, width, **opts)
        s = {color: color, width: width}
        s[:line_cap] = opts[:line_cap] if opts.key?(:line_cap)
        s[:line_join] = opts[:line_join] if opts.key?(:line_join)
        s[:dash] = opts[:dash] if opts.key?(:dash)
        s
      end

      # Linear gradient descriptor.
      def linear_gradient(from, to, stops)
        {type: "linear", from: from, to: to, stops: stops}
      end

      # -- Internal -------------------------------------------------------------

      def merge_common(shape, opts)
        shape[:fill] = opts[:fill] if opts.key?(:fill)
        shape[:stroke] = opts[:stroke] if opts.key?(:stroke)
        shape[:interactive] = opts[:interactive] if opts.key?(:interactive)
        shape[:transform] = opts[:transform] if opts.key?(:transform)
        shape[:clip] = opts[:clip] if opts.key?(:clip)
        shape[:border_radius] = opts[:border_radius] if opts.key?(:border_radius)
        shape[:opacity] = opts[:opacity] if opts.key?(:opacity)
        shape
      end
      private_class_method :merge_common
    end
  end
end
