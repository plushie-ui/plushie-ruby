# frozen_string_literal: true

module Plushie
  # Block-based DSL for building UI trees.
  #
  # Included automatically by Plushie::App. All widget methods are private
  # to avoid polluting the app's public interface.
  #
  #   def view(model)
  #     window("main", title: "Counter") do
  #       column(padding: 16, spacing: 8) do
  #         text("count", "Count: #{model.count}")
  #         row(spacing: 8) do
  #           button("increment", "+")
  #           button("decrement", "-")
  #         end
  #       end
  #     end
  #   end
  #
  # The DSL uses a thread-local context stack to track parent-child
  # relationships. Blocks run in the caller's binding (no instance_eval),
  # so self remains the app instance and private helpers work normally.
  #
  module UI
    # Thread-local context for nesting DSL calls.
    module Context
      def self.current = (Thread.current[:_plushie_ctx_stack] || []).last
      def self.push(children) = (Thread.current[:_plushie_ctx_stack] ||= []).push(children)

      def self.pop
        stack = Thread.current[:_plushie_ctx_stack]
        stack&.pop
      end

      def self.clear
        Thread.current[:_plushie_ctx_stack] = nil
      end
    end

    private

    # -- Windows ---------------------------------------------------------------

    def window(id, **props, &block)
      _plushie_container("window", id, props, &block)
    end

    # -- Layout containers -----------------------------------------------------

    def column(id = nil, **props, &block)
      _plushie_container("column", id || _plushie_auto_id, props, &block)
    end

    def row(id = nil, **props, &block)
      _plushie_container("row", id || _plushie_auto_id, props, &block)
    end

    def container(id, **props, &block)
      _plushie_container("container", id, props, &block)
    end

    def stack(id = nil, **props, &block)
      _plushie_container("stack", id || _plushie_auto_id, props, &block)
    end

    def scrollable(id, **props, &block)
      _plushie_container("scrollable", id, props, &block)
    end

    def responsive(id, **props, &block)
      _plushie_container("responsive", id, props, &block)
    end

    # -- Leaf widgets ----------------------------------------------------------

    # Text display.
    #   text("greeting", "Hello")           # id, content
    #   text("Hello")                       # auto-id, content
    #   text("greeting", "Hello", size: 20) # id, content, props
    def text(id_or_content, content = nil, **props)
      if content.nil?
        _plushie_leaf("text", _plushie_auto_id, props.merge(content: id_or_content))
      else
        _plushie_leaf("text", id_or_content, props.merge(content:))
      end
    end

    # Button.
    #   button("save", "Save")
    #   button("save", "Save", style: :primary)
    def button(id, label = nil, **props)
      _plushie_leaf("button", id, props.merge(label:))
    end

    # Text input field.
    def text_input(id, value = "", **props)
      _plushie_leaf("text_input", id, props.merge(value:))
    end

    # Multi-line text editor.
    def text_editor(id, content = "", **props)
      _plushie_leaf("text_editor", id, props.merge(content:))
    end

    # Checkbox.
    def checkbox(id, checked = false, **props)
      _plushie_leaf("checkbox", id, props.merge(checked:))
    end

    # Toggler (on/off switch).
    def toggler(id, active = false, **props)
      _plushie_leaf("toggler", id, props.merge(active:))
    end

    # Slider.
    #   slider("volume", [0, 100], 50)
    def slider(id, range, value, **props)
      min, max = range
      _plushie_leaf("slider", id, props.merge(min:, max:, value:))
    end

    # Vertical slider.
    def vertical_slider(id, range, value, **props)
      min, max = range
      _plushie_leaf("vertical_slider", id, props.merge(min:, max:, value:))
    end

    # Pick list (dropdown select).
    def pick_list(id, options, selected = nil, **props)
      _plushie_leaf("pick_list", id, props.merge(options:, selected:))
    end

    # Combo box (searchable dropdown).
    def combo_box(id, options, value = "", **props)
      _plushie_leaf("combo_box", id, props.merge(options:, value:))
    end

    # Radio button group.
    def radio(id, options, selected = nil, **props)
      _plushie_leaf("radio", id, props.merge(options:, selected:))
    end

    # Progress bar.
    #   progress_bar("loading", [0, 100], 42)
    def progress_bar(id, range, value, **props)
      min, max = range
      _plushie_leaf("progress_bar", id, props.merge(min:, max:, value:))
    end

    # Image display.
    def image(id, source, **props)
      _plushie_leaf("image", id, props.merge(source:))
    end

    # SVG display.
    def svg(id, data, **props)
      _plushie_leaf("svg", id, props.merge(data:))
    end

    # Markdown renderer.
    def markdown(id, content, **props)
      _plushie_leaf("markdown", id, props.merge(content:))
    end

    # Space (empty filler).
    def space(id = nil, **props)
      _plushie_leaf("space", id || _plushie_auto_id, props)
    end

    # Horizontal rule.
    def rule(id = nil, **props)
      _plushie_leaf("rule", id || _plushie_auto_id, props)
    end

    # QR code.
    def qr_code(id, data, **props)
      _plushie_leaf("qr_code", id, props.merge(data:))
    end

    # Tooltip wrapper.
    def tooltip(id, content, **props, &block)
      _plushie_container("tooltip", id, props.merge(content:), &block)
    end

    # -- Additional containers -------------------------------------------------

    # Grid layout.
    def grid(id = nil, **props, &block)
      _plushie_container("grid", id || _plushie_auto_id, props, &block)
    end

    # Column with keyed children (stable reordering).
    def keyed_column(id = nil, **props, &block)
      _plushie_container("keyed_column", id || _plushie_auto_id, props, &block)
    end

    # Pin (absolute positioning within parent).
    def pin(id = nil, **props, &block)
      _plushie_container("pin", id || _plushie_auto_id, props, &block)
    end

    # Floating overlay container.
    def floating(id = nil, **props, &block)
      _plushie_container("floating", id || _plushie_auto_id, props, &block)
    end

    # Mouse area (tracks mouse events over children).
    def mouse_area(id, **props, &block)
      _plushie_container("mouse_area", id, props, &block)
    end

    # Sensor (tracks layout/size changes).
    def sensor(id, **props, &block)
      _plushie_container("sensor", id, props, &block)
    end

    # Themer (applies theme overrides to children).
    def themer(id = nil, **props, &block)
      _plushie_container("themer", id || _plushie_auto_id, props, &block)
    end

    # Pane grid (resizable panes).
    def pane_grid(id, **props, &block)
      _plushie_container("pane_grid", id, props, &block)
    end

    # Overlay container.
    def overlay(id = nil, **props, &block)
      _plushie_container("overlay", id || _plushie_auto_id, props, &block)
    end

    # -- Additional leaf widgets -----------------------------------------------

    # Rich text display.
    def rich_text(id, spans, **props)
      _plushie_leaf("rich_text", id, props.merge(spans:))
    end

    # -- Canvas DSL ------------------------------------------------------------

    # Canvas widget with optional layer blocks.
    #   canvas("chart", width: 400, height: 300) do
    #     layer("grid") do
    #       rect(0, 0, 400, 300, stroke: "#eee")
    #     end
    #   end
    def canvas(id, **props, &block)
      if block
        layers = {}
        shapes = []
        old_canvas_ctx = Thread.current[:_plushie_canvas_ctx]
        Thread.current[:_plushie_canvas_ctx] = {layers: layers, shapes: shapes}
        begin
          block.call
        ensure
          Thread.current[:_plushie_canvas_ctx] = old_canvas_ctx
        end
        props = props.merge(layers: layers) unless layers.empty?
        props = props.merge(shapes: shapes) unless shapes.empty?
      end
      _plushie_leaf("canvas", id, props)
    end

    # Layer inside a canvas block.
    def layer(name, &block)
      ctx = Thread.current[:_plushie_canvas_ctx]
      raise "layer must be called inside a canvas block" unless ctx
      shape_list = []
      old = Thread.current[:_plushie_canvas_shapes]
      Thread.current[:_plushie_canvas_shapes] = shape_list
      begin
        block.call
      ensure
        Thread.current[:_plushie_canvas_shapes] = old
      end
      ctx[:layers][name] = shape_list
    end

    # Group inside a canvas/layer block.
    def canvas_group(**opts, &block)
      shape_list = []
      old = Thread.current[:_plushie_canvas_shapes]
      Thread.current[:_plushie_canvas_shapes] = shape_list
      begin
        block.call
      ensure
        Thread.current[:_plushie_canvas_shapes] = old
      end
      shape = {type: "group", shapes: shape_list}.merge(opts)
      _plushie_add_canvas_shape(shape)
      shape
    end

    # Canvas shape: rectangle.
    def canvas_rect(x, y, w, h, **opts)
      shape = Canvas::Shape.rect(x, y, w, h, **opts)
      _plushie_add_canvas_shape(shape)
      shape
    end

    # Canvas shape: circle.
    def canvas_circle(x, y, r, **opts)
      shape = Canvas::Shape.circle(x, y, r, **opts)
      _plushie_add_canvas_shape(shape)
      shape
    end

    # Canvas shape: line.
    def canvas_line(x1, y1, x2, y2, **opts)
      shape = Canvas::Shape.line(x1, y1, x2, y2, **opts)
      _plushie_add_canvas_shape(shape)
      shape
    end

    # Canvas shape: text.
    def canvas_text(x, y, content, **opts)
      shape = Canvas::Shape.canvas_text(x, y, content, **opts)
      _plushie_add_canvas_shape(shape)
      shape
    end

    # Canvas shape: path.
    def canvas_path(commands, **opts)
      shape = Canvas::Shape.path(commands, **opts)
      _plushie_add_canvas_shape(shape)
      shape
    end

    # Canvas shape: image.
    def canvas_image(source, x, y, w, h, **opts)
      shape = Canvas::Shape.canvas_image(source, x, y, w, h, **opts)
      _plushie_add_canvas_shape(shape)
      shape
    end

    # Canvas shape: SVG.
    def canvas_svg(source, x, y, w, h, **opts)
      shape = Canvas::Shape.canvas_svg(source, x, y, w, h, **opts)
      _plushie_add_canvas_shape(shape)
      shape
    end

    # Table widget (container with column/row data).
    def table(id, **props, &block)
      _plushie_container("table", id, props, &block)
    end

    # -- Internals -------------------------------------------------------------

    def _plushie_container(type, id, props, &block)
      children = if block
        child_list = []
        UI::Context.push(child_list)
        begin
          block.call
        ensure
          UI::Context.pop
        end
        child_list
      else
        props.delete(:children) || []
      end

      node = Node.new(id:, type:, props:, children:)

      parent = UI::Context.current
      parent << node if parent

      node
    end

    def _plushie_leaf(type, id, props)
      node = Node.new(id:, type:, props:)

      parent = UI::Context.current
      parent << node if parent

      node
    end

    def _plushie_auto_id
      loc = caller_locations(2, 1)&.first
      "auto:#{loc&.label}:#{loc&.lineno}"
    end

    def _plushie_add_canvas_shape(shape)
      target = Thread.current[:_plushie_canvas_shapes]
      if target
        target << shape
      else
        ctx = Thread.current[:_plushie_canvas_ctx]
        ctx[:shapes] << shape if ctx
      end
    end
  end
end
