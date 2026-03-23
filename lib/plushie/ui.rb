# frozen_string_literal: true

module Plushie
  # Block-based DSL for building UI trees.
  #
  # Included automatically by {Plushie::App}. All widget methods are private
  # to avoid polluting the app's public interface.
  #
  # == Auto-IDs
  #
  # Widgets without explicit IDs get auto-generated IDs derived from the
  # call site (e.g. +"auto:view:42"+). These are unstable across code
  # changes -- any refactor that moves the call to a different line will
  # change the ID. Always use explicit IDs for stateful widgets
  # (+text_input+, +text_editor+, +scrollable+, +combo_box+, +pane_grid+).
  #
  # == Usage
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

    # =========================================================================
    # Windows
    # =========================================================================

    # Top-level window container.
    #
    # Every app must have at least one window. The window ID is used for
    # window-level events and commands.
    #
    # @param id [String] window ID
    # @param props [Hash] window options (:title, :size, :position, :theme, :resizable, etc.)
    # @yield children to render inside the window
    # @return [Node]
    # @example
    #   window("main", title: "My App", size: [800, 600]) do
    #     column { text("Hello, world!") }
    #   end
    def window(id, **props, &block)
      _plushie_container("window", id, props, &block)
    end

    # =========================================================================
    # Layout containers
    # =========================================================================

    # Vertical layout container. Children are stacked top to bottom.
    #
    # @param id [String, nil] widget ID (auto-generated if nil)
    # @param props [Hash] layout options (:spacing, :padding, :width, :height, :align_x, :clip, etc.)
    # @yield children to add inside the container
    # @return [Node]
    # @example
    #   column(padding: 16, spacing: 8) do
    #     text("greeting", "Hello")
    #     button("save", "Save")
    #   end
    def column(id = nil, **props, &block)
      _plushie_container("column", id || _plushie_auto_id, props, &block)
    end

    # Horizontal layout container. Children are placed left to right.
    #
    # @param id [String, nil] widget ID (auto-generated if nil)
    # @param props [Hash] layout options (:spacing, :padding, :width, :height, :align_y, :clip, etc.)
    # @yield children to add inside the container
    # @return [Node]
    # @example
    #   row(spacing: 8) do
    #     button("ok", "OK")
    #     button("cancel", "Cancel")
    #   end
    def row(id = nil, **props, &block)
      _plushie_container("row", id || _plushie_auto_id, props, &block)
    end

    # Generic single-child container for styling and positioning.
    #
    # @param id [String] widget ID
    # @param props [Hash] container options (:padding, :width, :height, :align_x, :align_y, :style, :clip, etc.)
    # @yield child to wrap
    # @return [Node]
    # @example
    #   container("card", padding: 12, style: :card) do
    #     text("content", "Card body")
    #   end
    def container(id, **props, &block)
      _plushie_container("container", id, props, &block)
    end

    # Layered container. Children are stacked on top of each other (z-axis).
    #
    # @param id [String, nil] widget ID (auto-generated if nil)
    # @param props [Hash] layout options (:width, :height, etc.)
    # @yield children to layer
    # @return [Node]
    # @example
    #   stack do
    #     image("bg", "background.png", width: :fill)
    #     column(align_x: :center) { text("overlay", "On top") }
    #   end
    def stack(id = nil, **props, &block)
      _plushie_container("stack", id || _plushie_auto_id, props, &block)
    end

    # Scrollable container. Wraps children in a scrollable viewport.
    #
    # Always use an explicit ID -- scroll position is tied to the ID.
    #
    # @param id [String] widget ID
    # @param props [Hash] scroll options (:direction, :width, :height, etc.)
    # @yield children to scroll
    # @return [Node]
    # @example
    #   scrollable("log", direction: :vertical) do
    #     column { messages.each { |m| text(m.id, m.body) } }
    #   end
    def scrollable(id, **props, &block)
      _plushie_container("scrollable", id, props, &block)
    end

    # Responsive container. Receives the available width in the block.
    #
    # @param id [String] widget ID
    # @param props [Hash] responsive options
    # @yield children to render responsively
    # @return [Node]
    # @example
    #   responsive("layout") do
    #     column { text("info", "Responsive content") }
    #   end
    def responsive(id, **props, &block)
      _plushie_container("responsive", id, props, &block)
    end

    # =========================================================================
    # Leaf widgets
    # =========================================================================

    # Text display widget.
    #
    # Supports two call forms:
    #   text("Hello")                       # auto-id, content
    #   text("greeting", "Hello", size: 20) # explicit id, content, props
    #
    # @param id_or_content [String] widget ID (if content also given) or text content (auto-id)
    # @param content [String, nil] text content (when first arg is the ID)
    # @param props [Hash] text options (:size, :color, :font, :wrapping, :shaping, etc.)
    # @return [Node]
    # @example Auto-id form
    #   text("Hello, world!")
    # @example Explicit id with options
    #   text("greeting", "Hello", size: 24, color: "#333")
    def text(id_or_content, content = nil, **props)
      if content.nil?
        _plushie_leaf("text", _plushie_auto_id, props.merge(content: id_or_content))
      else
        _plushie_leaf("text", id_or_content, props.merge(content:))
      end
    end

    # Clickable button widget.
    #
    # @param id [String] widget ID (also used as the event ID on click)
    # @param label [String, nil] button label text
    # @param props [Hash] button options (:style, :padding, :width, :height, etc.)
    # @return [Node]
    # @example
    #   button("submit", "Submit", style: :primary)
    def button(id, label = nil, **props)
      _plushie_leaf("button", id, props.merge(label:))
    end

    # Single-line text input field.
    #
    # Always use an explicit ID -- input state is tied to the ID.
    #
    # @param id [String] widget ID
    # @param value [String] current text value
    # @param props [Hash] input options (:placeholder, :password, :on_input, :on_submit, :size, etc.)
    # @return [Node]
    # @example
    #   text_input("email", model.email, placeholder: "you@example.com")
    def text_input(id, value = "", **props)
      _plushie_leaf("text_input", id, props.merge(value:))
    end

    # Multi-line text editor.
    #
    # Always use an explicit ID -- editor state is tied to the ID.
    #
    # @param id [String] widget ID
    # @param content [String] current editor content
    # @param props [Hash] editor options (:on_action, :highlight, :wrapping, etc.)
    # @return [Node]
    # @example
    #   text_editor("notes", model.notes)
    def text_editor(id, content = "", **props)
      _plushie_leaf("text_editor", id, props.merge(content:))
    end

    # Checkbox toggle widget.
    #
    # @param id [String] widget ID
    # @param checked [Boolean] current checked state
    # @param props [Hash] checkbox options (:label, :size, :spacing, etc.)
    # @return [Node]
    # @example
    #   checkbox("agree", model.agreed, label: "I agree to the terms")
    def checkbox(id, checked = false, **props)
      _plushie_leaf("checkbox", id, props.merge(checked:))
    end

    # Toggle switch widget.
    #
    # @param id [String] widget ID
    # @param active [Boolean] current toggle state
    # @param props [Hash] toggler options (:label, :size, :spacing, etc.)
    # @return [Node]
    # @example
    #   toggler("dark_mode", model.dark_mode, label: "Dark mode")
    def toggler(id, active = false, **props)
      _plushie_leaf("toggler", id, props.merge(active:))
    end

    # Horizontal slider for numeric input.
    #
    # @param id [String] widget ID
    # @param range [Array(Numeric, Numeric)] min and max values as a two-element array
    # @param value [Numeric] current slider value
    # @param props [Hash] slider options (:step, :width, :height, etc.)
    # @return [Node]
    # @example
    #   slider("volume", [0, 100], model.volume, step: 5)
    def slider(id, range, value, **props)
      min, max = range
      _plushie_leaf("slider", id, props.merge(min:, max:, value:))
    end

    # Vertical slider for numeric input.
    #
    # @param id [String] widget ID
    # @param range [Array(Numeric, Numeric)] min and max values as a two-element array
    # @param value [Numeric] current slider value
    # @param props [Hash] slider options (:step, :width, :height, etc.)
    # @return [Node]
    # @example
    #   vertical_slider("eq_band_1", [0, 100], 75)
    def vertical_slider(id, range, value, **props)
      min, max = range
      _plushie_leaf("vertical_slider", id, props.merge(min:, max:, value:))
    end

    # Dropdown select widget.
    #
    # @param id [String] widget ID
    # @param options [Array<String>] list of selectable options
    # @param selected [String, nil] currently selected option
    # @param props [Hash] pick list options (:placeholder, :text_size, :padding, etc.)
    # @return [Node]
    # @example
    #   pick_list("color", ["Red", "Green", "Blue"], model.color)
    def pick_list(id, options, selected = nil, **props)
      _plushie_leaf("pick_list", id, props.merge(options:, selected:))
    end

    # Searchable dropdown widget.
    #
    # Always use an explicit ID -- combo box state is tied to the ID.
    #
    # @param id [String] widget ID
    # @param options [Array<String>] list of selectable options
    # @param value [String] current search/input value
    # @param props [Hash] combo box options (:placeholder, :on_input, :on_option_hovered, etc.)
    # @return [Node]
    # @example
    #   combo_box("country", countries, model.country_search, placeholder: "Search...")
    def combo_box(id, options, value = "", **props)
      _plushie_leaf("combo_box", id, props.merge(options:, value:))
    end

    # Radio button group for single-select choices.
    #
    # @param id [String] widget ID
    # @param options [Array<String>] list of radio options
    # @param selected [String, nil] currently selected option
    # @param props [Hash] radio options (:spacing, :size, :text_size, etc.)
    # @return [Node]
    # @example
    #   radio("size", ["S", "M", "L", "XL"], model.size)
    def radio(id, options, selected = nil, **props)
      _plushie_leaf("radio", id, props.merge(options:, selected:))
    end

    # Progress bar widget.
    #
    # @param id [String] widget ID
    # @param range [Array(Numeric, Numeric)] min and max values as a two-element array
    # @param value [Numeric] current progress value
    # @param props [Hash] progress bar options (:width, :height, :style, etc.)
    # @return [Node]
    # @example
    #   progress_bar("upload", [0, 100], model.upload_pct)
    def progress_bar(id, range, value, **props)
      min, max = range
      _plushie_leaf("progress_bar", id, props.merge(min:, max:, value:))
    end

    # Image display widget.
    #
    # @param id [String] widget ID
    # @param source [String] image path or URL
    # @param props [Hash] image options (:width, :height, :content_fit, :filter_method, etc.)
    # @return [Node]
    # @example
    #   image("avatar", "assets/avatar.png", width: 64, height: 64)
    def image(id, source, **props)
      _plushie_leaf("image", id, props.merge(source:))
    end

    # SVG display widget.
    #
    # @param id [String] widget ID
    # @param data [String] SVG content string or file path
    # @param props [Hash] SVG options (:width, :height, :content_fit, etc.)
    # @return [Node]
    # @example
    #   svg("icon", File.read("icon.svg"), width: 24, height: 24)
    def svg(id, data, **props)
      _plushie_leaf("svg", id, props.merge(data:))
    end

    # Markdown rendering widget.
    #
    # @param id [String] widget ID
    # @param content [String] markdown text to render
    # @param props [Hash] markdown options (:text_size, :code_size, etc.)
    # @return [Node]
    # @example
    #   markdown("docs", "# Welcome\n\nHello **world**.")
    def markdown(id, content, **props)
      _plushie_leaf("markdown", id, props.merge(content:))
    end

    # Empty space filler widget.
    #
    # @param id [String, nil] widget ID (auto-generated if nil)
    # @param props [Hash] space options (:width, :height, etc.)
    # @return [Node]
    # @example
    #   row do
    #     text("left", "Left")
    #     space
    #     text("right", "Right")
    #   end
    def space(id = nil, **props)
      _plushie_leaf("space", id || _plushie_auto_id, props)
    end

    # Horizontal rule (divider line).
    #
    # @param id [String, nil] widget ID (auto-generated if nil)
    # @param props [Hash] rule options (:style, etc.)
    # @return [Node]
    # @example
    #   column do
    #     text("above", "Section A")
    #     rule
    #     text("below", "Section B")
    #   end
    def rule(id = nil, **props)
      _plushie_leaf("rule", id || _plushie_auto_id, props)
    end

    # QR code display widget.
    #
    # @param id [String] widget ID
    # @param data [String] data to encode as a QR code
    # @param props [Hash] QR code options (:cell_size, :color, etc.)
    # @return [Node]
    # @example
    #   qr_code("link", "https://example.com")
    def qr_code(id, data, **props)
      _plushie_leaf("qr_code", id, props.merge(data:))
    end

    # Tooltip wrapper. Displays a tooltip over its child widget.
    #
    # @param id [String] widget ID
    # @param content [String] tooltip text
    # @param props [Hash] tooltip options (:position, :gap, :style, etc.)
    # @yield the child widget to attach the tooltip to
    # @return [Node]
    # @example
    #   tooltip("help_tip", "Click to save your work", position: :top) do
    #     button("save", "Save")
    #   end
    def tooltip(id, content, **props, &block)
      _plushie_container("tooltip", id, props.merge(content:), &block)
    end

    # =========================================================================
    # Additional containers
    # =========================================================================

    # Grid layout container. Children are arranged in a grid.
    #
    # @param id [String, nil] widget ID (auto-generated if nil)
    # @param props [Hash] grid options (:columns, :column_spacing, :row_spacing, :padding, etc.)
    # @yield children to arrange in the grid
    # @return [Node]
    # @example
    #   grid(columns: 3, column_spacing: 8, row_spacing: 8) do
    #     9.times { |i| button("cell_#{i}", "#{i}") }
    #   end
    def grid(id = nil, **props, &block)
      _plushie_container("grid", id || _plushie_auto_id, props, &block)
    end

    # Column with keyed children for stable reordering.
    #
    # Uses child IDs as keys so the renderer can animate reorders
    # and preserve widget state across list changes.
    #
    # @param id [String, nil] widget ID (auto-generated if nil)
    # @param props [Hash] layout options (:spacing, :padding, :width, :height, :align_x, etc.)
    # @yield keyed children
    # @return [Node]
    # @example
    #   keyed_column(spacing: 4) do
    #     model.items.each { |item| text(item.id, item.name) }
    #   end
    def keyed_column(id = nil, **props, &block)
      _plushie_container("keyed_column", id || _plushie_auto_id, props, &block)
    end

    # Absolute positioning container. Children are placed at explicit coordinates.
    #
    # @param id [String, nil] widget ID (auto-generated if nil)
    # @param props [Hash] pin options (:width, :height, etc.)
    # @yield children to position
    # @return [Node]
    # @example
    #   pin do
    #     container("badge", x: 100, y: 50) { text("!", "!") }
    #   end
    def pin(id = nil, **props, &block)
      _plushie_container("pin", id || _plushie_auto_id, props, &block)
    end

    # Floating overlay container.
    #
    # @param id [String, nil] widget ID (auto-generated if nil)
    # @param props [Hash] floating options (:anchor, :offset, etc.)
    # @yield children to float
    # @return [Node]
    def floating(id = nil, **props, &block)
      _plushie_container("floating", id || _plushie_auto_id, props, &block)
    end

    # Mouse area container. Tracks mouse events over its children.
    #
    # @param id [String] widget ID
    # @param props [Hash] mouse area options (:on_press, :on_release, :on_move, :on_enter, :on_exit, etc.)
    # @yield children to track mouse events over
    # @return [Node]
    # @example
    #   mouse_area("canvas_area", on_press: true, on_move: true) do
    #     canvas("drawing", width: 400, height: 300)
    #   end
    def mouse_area(id, **props, &block)
      _plushie_container("mouse_area", id, props, &block)
    end

    # Sensor container. Tracks layout and size changes of its children.
    #
    # @param id [String] widget ID
    # @param props [Hash] sensor options
    # @yield children to monitor
    # @return [Node]
    # @example
    #   sensor("measure") do
    #     column { text("content", "Measured content") }
    #   end
    def sensor(id, **props, &block)
      _plushie_container("sensor", id, props, &block)
    end

    # Theme override container. Applies theme changes to its children.
    #
    # @param id [String, nil] widget ID (auto-generated if nil)
    # @param props [Hash] theme options (:theme, etc.)
    # @yield children to theme
    # @return [Node]
    # @example
    #   themer(theme: :dark) do
    #     column { text("msg", "Dark-themed section") }
    #   end
    def themer(id = nil, **props, &block)
      _plushie_container("themer", id || _plushie_auto_id, props, &block)
    end

    # Resizable pane grid container.
    #
    # Always use an explicit ID -- pane state is tied to the ID.
    #
    # @param id [String] widget ID
    # @param props [Hash] pane grid options (:spacing, :on_resize, :on_drag, etc.)
    # @yield pane children
    # @return [Node]
    # @example
    #   pane_grid("editor_panes") do
    #     container("left") { text("nav", "Navigation") }
    #     container("right") { text("content", "Content") }
    #   end
    def pane_grid(id, **props, &block)
      _plushie_container("pane_grid", id, props, &block)
    end

    # Overlay container. Renders children above the normal widget tree.
    #
    # @param id [String, nil] widget ID (auto-generated if nil)
    # @param props [Hash] overlay options
    # @yield children to render as overlay
    # @return [Node]
    def overlay(id = nil, **props, &block)
      _plushie_container("overlay", id || _plushie_auto_id, props, &block)
    end

    # =========================================================================
    # Additional leaf widgets
    # =========================================================================

    # Rich text display with styled spans.
    #
    # @param id [String] widget ID
    # @param spans [Array<Hash>] list of span hashes with :content, :color, :size, :font, etc.
    # @param props [Hash] rich text options (:wrapping, :spacing, etc.)
    # @return [Node]
    # @example
    #   rich_text("status", [
    #     { content: "Status: ", size: 14 },
    #     { content: "OK", size: 14, color: "#0a0" }
    #   ])
    def rich_text(id, spans, **props)
      _plushie_leaf("rich_text", id, props.merge(spans:))
    end

    # =========================================================================
    # Canvas DSL
    # =========================================================================

    # Canvas widget for vector drawing with optional layers.
    #
    # Shapes and layers defined inside the block are collected and sent
    # as canvas data. Use {#layer} to organize shapes into named groups.
    #
    # @param id [String] widget ID
    # @param props [Hash] canvas options (:width, :height, :background, :on_press, etc.)
    # @yield layers and shapes to draw
    # @return [Node]
    # @example
    #   canvas("chart", width: 400, height: 300) do
    #     layer("grid") do
    #       canvas_rect(0, 0, 400, 300, stroke: "#eee")
    #     end
    #     layer("data") do
    #       canvas_circle(200, 150, 40, fill: "#07f")
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

    # Named layer inside a canvas block.
    #
    # Layers are drawn in declaration order. Each layer gets its own
    # cache, so unchanged layers skip re-rendering.
    #
    # @param name [String] layer name
    # @yield shapes to draw in this layer
    # @return [void]
    # @raise [RuntimeError] if called outside a canvas block
    # @example
    #   canvas("scene", width: 200, height: 200) do
    #     layer("background") { canvas_rect(0, 0, 200, 200, fill: "#fff") }
    #     layer("foreground") { canvas_circle(100, 100, 20, fill: "#f00") }
    #   end
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

    # Group of shapes inside a canvas or layer block.
    #
    # Groups can apply shared transforms and clipping to their children.
    #
    # @param opts [Hash] group options (:transform, :clip, :opacity, etc.)
    # @yield shapes to include in the group
    # @return [Hash] the group shape descriptor
    # @example
    #   canvas("grouped", width: 200, height: 200) do
    #     layer("main") do
    #       canvas_group(transform: { translate: [50, 50] }) do
    #         canvas_rect(0, 0, 100, 100, fill: "#0f0")
    #         canvas_circle(50, 50, 30, fill: "#00f")
    #       end
    #     end
    #   end
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

    # Draw a rectangle on the canvas.
    #
    # @param x [Numeric] x-coordinate of the top-left corner
    # @param y [Numeric] y-coordinate of the top-left corner
    # @param w [Numeric] width
    # @param h [Numeric] height
    # @param opts [Hash] shape options (:fill, :stroke, :stroke_width, :radius, etc.)
    # @return [Hash] the shape descriptor
    # @example
    #   canvas_rect(10, 10, 80, 40, fill: "#07f", radius: 4)
    def canvas_rect(x, y, w, h, **opts)
      shape = Canvas::Shape.rect(x, y, w, h, **opts)
      _plushie_add_canvas_shape(shape)
      shape
    end

    # Draw a circle on the canvas.
    #
    # @param x [Numeric] x-coordinate of the center
    # @param y [Numeric] y-coordinate of the center
    # @param r [Numeric] radius
    # @param opts [Hash] shape options (:fill, :stroke, :stroke_width, etc.)
    # @return [Hash] the shape descriptor
    # @example
    #   canvas_circle(100, 100, 50, fill: "#f00")
    def canvas_circle(x, y, r, **opts)
      shape = Canvas::Shape.circle(x, y, r, **opts)
      _plushie_add_canvas_shape(shape)
      shape
    end

    # Draw a line on the canvas.
    #
    # @param x1 [Numeric] x-coordinate of the start point
    # @param y1 [Numeric] y-coordinate of the start point
    # @param x2 [Numeric] x-coordinate of the end point
    # @param y2 [Numeric] y-coordinate of the end point
    # @param opts [Hash] shape options (:stroke, :stroke_width, :dash, etc.)
    # @return [Hash] the shape descriptor
    # @example
    #   canvas_line(0, 0, 100, 100, stroke: "#000", stroke_width: 2)
    def canvas_line(x1, y1, x2, y2, **opts)
      shape = Canvas::Shape.line(x1, y1, x2, y2, **opts)
      _plushie_add_canvas_shape(shape)
      shape
    end

    # Draw text on the canvas.
    #
    # @param x [Numeric] x-coordinate of the text origin
    # @param y [Numeric] y-coordinate of the text origin
    # @param content [String] text content to render
    # @param opts [Hash] shape options (:size, :color, :font, :align, etc.)
    # @return [Hash] the shape descriptor
    # @example
    #   canvas_text(10, 20, "Hello", size: 16, color: "#333")
    def canvas_text(x, y, content, **opts)
      shape = Canvas::Shape.canvas_text(x, y, content, **opts)
      _plushie_add_canvas_shape(shape)
      shape
    end

    # Draw a path on the canvas from a list of SVG-style commands.
    #
    # @param commands [Array, String] path commands (e.g. [[:M, 0, 0], [:L, 100, 100]])
    # @param opts [Hash] shape options (:fill, :stroke, :stroke_width, :close, etc.)
    # @return [Hash] the shape descriptor
    # @example
    #   canvas_path([[:M, 0, 0], [:L, 50, 80], [:L, 100, 0], [:Z]], fill: "#0a0")
    def canvas_path(commands, **opts)
      shape = Canvas::Shape.path(commands, **opts)
      _plushie_add_canvas_shape(shape)
      shape
    end

    # Draw an image on the canvas.
    #
    # @param source [String] image path or URL
    # @param x [Numeric] x-coordinate of the top-left corner
    # @param y [Numeric] y-coordinate of the top-left corner
    # @param w [Numeric] width
    # @param h [Numeric] height
    # @param opts [Hash] shape options (:opacity, :filter_method, etc.)
    # @return [Hash] the shape descriptor
    # @example
    #   canvas_image("sprite.png", 10, 10, 32, 32)
    def canvas_image(source, x, y, w, h, **opts)
      shape = Canvas::Shape.canvas_image(source, x, y, w, h, **opts)
      _plushie_add_canvas_shape(shape)
      shape
    end

    # Draw an SVG on the canvas.
    #
    # @param source [String] SVG content string or file path
    # @param x [Numeric] x-coordinate of the top-left corner
    # @param y [Numeric] y-coordinate of the top-left corner
    # @param w [Numeric] width
    # @param h [Numeric] height
    # @param opts [Hash] shape options (:opacity, etc.)
    # @return [Hash] the shape descriptor
    # @example
    #   canvas_svg("<svg>...</svg>", 0, 0, 100, 100)
    def canvas_svg(source, x, y, w, h, **opts)
      shape = Canvas::Shape.canvas_svg(source, x, y, w, h, **opts)
      _plushie_add_canvas_shape(shape)
      shape
    end

    # =========================================================================
    # Table
    # =========================================================================

    # Table widget container with column and row data.
    #
    # @param id [String] widget ID
    # @param props [Hash] table options (:columns, :rows, :on_sort, :on_select, etc.)
    # @yield column definitions and row content
    # @return [Node]
    # @example
    #   table("users", columns: [:name, :email]) do
    #     text("row1_name", "Alice")
    #     text("row1_email", "alice@example.com")
    #   end
    def table(id, **props, &block)
      _plushie_container("table", id, props, &block)
    end

    # =========================================================================
    # Internals
    # =========================================================================

    # Build a container node, collecting children from the block.
    #
    # @api private
    # @param type [String] widget type name
    # @param id [String] widget ID
    # @param props [Hash] widget properties
    # @yield children to collect
    # @return [Node]
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

    # Build a leaf node (no children).
    #
    # @api private
    # @param type [String] widget type name
    # @param id [String] widget ID
    # @param props [Hash] widget properties
    # @return [Node]
    def _plushie_leaf(type, id, props)
      node = Node.new(id:, type:, props:)

      parent = UI::Context.current
      parent << node if parent

      node
    end

    # Generate an auto-ID from the caller's source location.
    #
    # @api private
    # @return [String] an ID like +"auto:view:42"+
    def _plushie_auto_id
      loc = caller_locations(2, 1)&.first
      "auto:#{loc&.label}:#{loc&.lineno}"
    end

    # Append a shape to the current canvas shape target.
    #
    # Shapes are added to the innermost layer's shape list if inside a
    # {#layer} block, or to the canvas's top-level shapes list otherwise.
    #
    # @api private
    # @param shape [Hash] shape descriptor
    # @return [void]
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
