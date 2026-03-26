# frozen_string_literal: true

module Plushie
  # Event types delivered to update/2.
  #
  # All event types are immutable Data classes. Pattern match on them
  # in your update method:
  #
  #   case event
  #   in Event::Widget[type: :click, id: "save"]
  #     model.with(saved: true)
  #   in Event::Key[type: :press, key: "s", modifiers: { command: true }]
  #     [model, Command.async(-> { save(model) }, :save_result)]
  #   end
  #
  module Event
    # Widget interaction events (clicks, input, toggles, selects, etc.)
    # Delivered to update when users interact with widgets.
    #
    # @!attribute [r] type [Symbol] event kind (:click, :input, :submit, :toggle, :select, :slide, etc.)
    # @!attribute [r] id [String] widget ID that produced the event
    # @!attribute [r] value [Object, nil] event value (text for :input, boolean for :toggle, etc.)
    # @!attribute [r] scope [Array<String>] reversed ancestor scope chain (immediate parent first)
    # @!attribute [r] data [Hash, nil] additional event data
    #
    # @example Click
    #   in Event::Widget[type: :click, id: "save"]
    # @example Input with value
    #   in Event::Widget[type: :input, id: "search", value:]
    Widget = Data.define(:type, :id, :value, :scope, :data) do
      def initialize(type:, id:, value: nil, scope: [], data: nil)
        super
      end
    end

    # Keyboard events delivered when keys are pressed or released.
    # Triggered by keyboard input while the window has focus.
    # Subscribe via Subscription.on_key_press or Subscription.on_key_release.
    #
    # @!attribute [r] type [Symbol] :press or :release
    # @!attribute [r] key [String] logical key name ("a", "Enter", "ArrowUp", etc.)
    # @!attribute [r] modified_key [String, nil] key with modifiers applied (e.g. "S" for shift+s)
    # @!attribute [r] physical_key [String, nil] hardware scan code name
    # @!attribute [r] location [Symbol] key location (:standard, :left, :right, :numpad)
    # @!attribute [r] modifiers [Hash] active modifier state ({shift: true, command: false, ...})
    # @!attribute [r] text [String, nil] text produced by the key event (nil for non-printable keys)
    # @!attribute [r] repeat [Boolean] true if this is a key-repeat event
    # @!attribute [r] captured [Boolean] true if a widget consumed this event
    #
    # @example Key press with modifier
    #   in Event::Key[type: :press, key: "s", modifiers: { command: true }]
    # @example Any key release
    #   in Event::Key[type: :release, key:]
    Key = Data.define(:type, :key, :modified_key, :physical_key,
      :location, :modifiers, :text, :repeat, :captured) do
      def initialize(type:, key:, modified_key: nil, physical_key: nil,
        location: :standard, modifiers: {}, text: nil, repeat: false, captured: false)
        super
      end
    end

    # Mouse events delivered globally via subscription.
    # Triggered by mouse movement, button presses, or scroll wheel activity.
    # Subscribe via Subscription.on_mouse_move, on_mouse_button, or on_mouse_scroll.
    #
    # @!attribute [r] type [Symbol] :moved, :button_pressed, :button_released, :wheel_scrolled, :cursor_entered, :cursor_left
    # @!attribute [r] x [Float, nil] cursor x position
    # @!attribute [r] y [Float, nil] cursor y position
    # @!attribute [r] button [Symbol, nil] mouse button (:left, :right, :middle, etc.)
    # @!attribute [r] delta_x [Float, nil] scroll delta x (for :wheel_scrolled)
    # @!attribute [r] delta_y [Float, nil] scroll delta y (for :wheel_scrolled)
    # @!attribute [r] unit [Symbol, nil] scroll unit (:line, :pixel)
    # @!attribute [r] captured [Boolean] true if a widget consumed this event
    #
    # @example Mouse button press
    #   in Event::Mouse[type: :button_pressed, button: :left, x:, y:]
    # @example Scroll wheel
    #   in Event::Mouse[type: :wheel_scrolled, delta_y:]
    Mouse = Data.define(:type, :x, :y, :button, :delta_x, :delta_y, :unit, :captured) do
      def initialize(type:, x: nil, y: nil, button: nil,
        delta_x: nil, delta_y: nil, unit: nil, captured: false)
        super
      end
    end

    # Touch screen events delivered via subscription.
    # Triggered by finger interactions on touch-capable displays.
    # Subscribe via Subscription.on_touch.
    #
    # @!attribute [r] type [Symbol] :finger_pressed, :finger_lifted, :finger_moved, :finger_lost
    # @!attribute [r] finger_id [Integer, nil] unique identifier for the finger
    # @!attribute [r] x [Float, nil] touch x position
    # @!attribute [r] y [Float, nil] touch y position
    # @!attribute [r] captured [Boolean] true if a widget consumed this event
    #
    # @example Finger press
    #   in Event::Touch[type: :finger_pressed, finger_id:, x:, y:]
    # @example Finger lifted
    #   in Event::Touch[type: :finger_lifted, finger_id:]
    Touch = Data.define(:type, :finger_id, :x, :y, :captured) do
      def initialize(type:, finger_id: nil, x: nil, y: nil, captured: false)
        super
      end
    end

    # IME (Input Method Editor) events for international text input.
    # Triggered by IME composition sessions (CJK input, accent composition, etc.).
    # Subscribe via Subscription.on_ime.
    #
    # @!attribute [r] type [Symbol] :enabled, :preedit, :commit, :disabled
    # @!attribute [r] id [String, nil] widget ID that has IME focus
    # @!attribute [r] scope [Array<String>] reversed ancestor scope chain
    # @!attribute [r] text [String, nil] composed or committed text
    # @!attribute [r] cursor [Array<Integer>, nil] cursor position within preedit
    # @!attribute [r] captured [Boolean] true if a widget consumed this event
    #
    # @example IME commit
    #   in Event::Ime[type: :commit, text:]
    # @example Preedit composition
    #   in Event::Ime[type: :preedit, text:, cursor:]
    Ime = Data.define(:type, :id, :scope, :text, :cursor, :captured) do
      def initialize(type:, id: nil, scope: [], text: nil, cursor: nil, captured: false)
        super
      end
    end

    # Window lifecycle events (open, close, resize, move, focus, etc.).
    # Triggered by window manager actions or user interaction with window chrome.
    # Subscribe via Subscription.on_window_close, on_window_open, on_window_resize, etc.
    #
    # @!attribute [r] type [Symbol] :opened, :close_requested, :resized, :moved, :focused, :unfocused, :file_dropped, :file_hovered
    # @!attribute [r] window_id [String, nil] ID of the affected window
    # @!attribute [r] x [Float, nil] window x position (for :moved)
    # @!attribute [r] y [Float, nil] window y position (for :moved)
    # @!attribute [r] width [Float, nil] window width (for :resized, :opened)
    # @!attribute [r] height [Float, nil] window height (for :resized, :opened)
    # @!attribute [r] scale_factor [Float, nil] display scale factor
    # @!attribute [r] path [String, nil] file path (for :file_dropped, :file_hovered)
    #
    # @example Window close requested
    #   in Event::Window[type: :close_requested, window_id:]
    # @example Window resized
    #   in Event::Window[type: :resized, width:, height:]
    Window = Data.define(:type, :window_id, :x, :y, :width, :height,
      :scale_factor, :path) do
      def initialize(type:, window_id: nil, x: nil, y: nil,
        width: nil, height: nil, scale_factor: nil, path: nil)
        super
      end
    end

    # Canvas interaction events for shapes drawn in canvas/layer blocks.
    # Triggered by mouse interactions with canvas shapes that have IDs.
    #
    # @!attribute [r] type [Symbol] :click, :press, :release, :enter, :exit, :move, :scroll
    # @!attribute [r] id [String] canvas shape ID that produced the event
    # @!attribute [r] x [Float, nil] interaction x position within the canvas
    # @!attribute [r] y [Float, nil] interaction y position within the canvas
    # @!attribute [r] button [Symbol, nil] mouse button (:left, :right, :middle)
    # @!attribute [r] delta_x [Float, nil] scroll delta x
    # @!attribute [r] delta_y [Float, nil] scroll delta y
    # @!attribute [r] scope [Array<String>] reversed ancestor scope chain
    #
    # @example Canvas shape click
    #   in Event::Canvas[type: :click, id: "my_circle", x:, y:]
    # @example Canvas scroll
    #   in Event::Canvas[type: :scroll, id:, delta_y:]
    Canvas = Data.define(:type, :id, :x, :y, :button, :delta_x, :delta_y, :scope) do
      def initialize(type:, id:, x: nil, y: nil, button: nil,
        delta_x: nil, delta_y: nil, scope: [])
        super
      end
    end

    # Mouse area events for regions defined by the mouse_area widget.
    # Triggered by mouse interactions within a mouse_area boundary.
    #
    # @!attribute [r] type [Symbol] :enter, :exit, :move, :press, :release
    # @!attribute [r] id [String] mouse area widget ID
    # @!attribute [r] x [Float, nil] mouse x position relative to the area
    # @!attribute [r] y [Float, nil] mouse y position relative to the area
    # @!attribute [r] delta_x [Float, nil] movement delta x (for :move)
    # @!attribute [r] delta_y [Float, nil] movement delta y (for :move)
    # @!attribute [r] scope [Array<String>] reversed ancestor scope chain
    #
    # @example Mouse entered area
    #   in Event::MouseArea[type: :enter, id: "hover_zone"]
    # @example Mouse moved within area
    #   in Event::MouseArea[type: :move, id:, x:, y:]
    MouseArea = Data.define(:type, :id, :x, :y, :delta_x, :delta_y, :scope) do
      def initialize(type:, id:, x: nil, y: nil, delta_x: nil, delta_y: nil, scope: [])
        super
      end
    end

    # Pane grid events for split-pane container interactions.
    # Triggered by drag-to-resize, pane splits, and pane close actions.
    #
    # @!attribute [r] type [Symbol] :dragged, :dropped, :resized, :clicked, :split, :close
    # @!attribute [r] id [String] pane grid widget ID
    # @!attribute [r] pane [Object, nil] source pane identifier
    # @!attribute [r] target [Object, nil] target pane identifier (for drop/split)
    # @!attribute [r] split [Symbol, nil] split direction (:horizontal, :vertical)
    # @!attribute [r] ratio [Float, nil] resize ratio
    # @!attribute [r] scope [Array<String>] reversed ancestor scope chain
    # @!attribute [r] action [Symbol, nil] pane action type
    # @!attribute [r] region [Symbol, nil] drop region (:center, :left, :right, :top, :bottom)
    # @!attribute [r] edge [Symbol, nil] resize edge
    #
    # @example Pane resized
    #   in Event::Pane[type: :resized, id: "editor_panes", ratio:]
    # @example Pane split
    #   in Event::Pane[type: :split, pane:, split: :horizontal]
    Pane = Data.define(:type, :id, :pane, :target, :split, :ratio, :scope,
      :action, :region, :edge) do
      def initialize(type:, id:, pane: nil, target: nil, split: nil, ratio: nil,
        scope: [], action: nil, region: nil, edge: nil)
        super
      end
    end

    # Sensor events for detecting widget size changes.
    # Triggered when a sensor widget's measured dimensions change.
    #
    # @!attribute [r] type [Symbol] :resized
    # @!attribute [r] id [String] sensor widget ID
    # @!attribute [r] width [Float, nil] measured width
    # @!attribute [r] height [Float, nil] measured height
    # @!attribute [r] scope [Array<String>] reversed ancestor scope chain
    #
    # @example Sensor resized
    #   in Event::Sensor[type: :resized, id: "content_area", width:, height:]
    Sensor = Data.define(:type, :id, :width, :height, :scope) do
      def initialize(type:, id:, width: nil, height: nil, scope: [])
        super
      end
    end

    # Modifier key state change events.
    # Triggered when modifier keys (shift, ctrl, alt, command) change state.
    # Subscribe via Subscription.on_modifiers_changed.
    #
    # @!attribute [r] modifiers [Hash] current modifier state ({shift: true, control: false, alt: false, command: false})
    # @!attribute [r] captured [Boolean] true if a widget consumed this event
    #
    # @example Modifiers changed
    #   in Event::Modifiers[modifiers: { shift: true }]
    Modifiers = Data.define(:modifiers, :captured) do
      def initialize(modifiers:, captured: false)
        super
      end
    end

    # Effect result events for platform operations (file dialogs, clipboard, notifications).
    # Triggered when an asynchronous platform effect completes.
    # The request_id correlates to the Command that initiated the effect.
    #
    # @!attribute [r] request_id [String] ID matching the originating effect command
    # @!attribute [r] result [Object] operation result (file path, clipboard text, etc.)
    #
    # @example File dialog result
    #   in Event::Effect[request_id: "open_file", result:]
    Effect = Data.define(:request_id, :result)

    # Renderer error for an extension command.
    #
    # @!attribute [r] reason [String] machine-readable error reason
    # @!attribute [r] node_id [String, nil] target widget node ID
    # @!attribute [r] op [String, nil] command operation name
    # @!attribute [r] extension [String, nil] extension widget type
    # @!attribute [r] message [String, nil] human-readable error text
    ExtensionCommandError = Data.define(:reason, :node_id, :op, :extension, :message) do
      def initialize(reason:, node_id: nil, op: nil, extension: nil, message: nil)
        super
      end
    end

    # System events for theme changes, animation frames, and other runtime signals.
    # Triggered by OS-level changes or renderer lifecycle events.
    # Subscribe via Subscription.on_theme_change or on_animation_frame.
    #
    # @!attribute [r] type [Symbol] :theme_changed, :animation_frame
    # @!attribute [r] tag [Symbol, nil] subscription tag (for :animation_frame)
    # @!attribute [r] data [Object, nil] event payload (theme name for :theme_changed, delta ms for :animation_frame)
    #
    # @example Theme changed
    #   in Event::System[type: :theme_changed, data: theme]
    # @example Animation frame
    #   in Event::System[type: :animation_frame, data: delta_ms]
    System = Data.define(:type, :tag, :data) do
      def initialize(type:, tag: nil, data: nil)
        super
      end
    end

    # Timer events from interval subscriptions.
    # Triggered periodically by Subscription.every at the specified interval.
    #
    # @!attribute [r] tag [Symbol] the tag specified in Subscription.every
    # @!attribute [r] timestamp [Integer] monotonic timestamp in milliseconds
    #
    # @example Timer tick
    #   in Event::Timer[tag: :tick, timestamp:]
    Timer = Data.define(:tag, :timestamp)

    # Async command result events.
    # Triggered when a Command.async lambda completes execution.
    #
    # @!attribute [r] tag [Symbol] the tag specified in Command.async
    # @!attribute [r] result [Object] return value of the async lambda
    #
    # @example Async result
    #   in Event::Async[tag: :fetch_data, result:]
    Async = Data.define(:tag, :result)

    # Stream command chunk events.
    # Triggered for each value emitted by a Command.stream source.
    #
    # @!attribute [r] tag [Symbol] the tag specified in Command.stream
    # @!attribute [r] value [Object] the emitted chunk value
    #
    # @example Stream chunk
    #   in Event::Stream[tag: :download, value:]
    Stream = Data.define(:tag, :value)

    # Reconstruct the full scoped path as a forward-order string.
    #
    #   Event.target(widget_event) # => "sidebar/form/save"
    #
    def self.target(event)
      return event.id if event.scope.empty?
      (event.scope.reverse + [event.id]).join("/")
    end
  end
end
