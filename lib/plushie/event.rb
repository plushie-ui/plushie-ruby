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
    # All widget interaction events: clicks, input, toggles, canvas interactions,
    # mouse area events, sensor resizes, pane events, and custom widget events.
    #
    # Built-in types include standard widget events (:click, :input, :submit, etc.),
    # canvas events (:canvas_press, :canvas_move, etc.), mouse area events
    # (:mouse_enter, :mouse_exit, etc.), sensor events (:sensor_resize), and
    # pane events (:pane_resized, :pane_dragged, :pane_clicked).
    #
    # The `data` field carries type-specific payload as a Hash with symbol keys.
    # For example, :canvas_press has `data: {x:, y:, button:}` and :sensor_resize
    # has `data: {width:, height:}`.
    #
    # @!attribute [r] type [Symbol] event kind
    # @!attribute [r] id [String] widget ID that produced the event
    # @!attribute [r] value [Object, nil] event value (text for :input, boolean for :toggle, etc.)
    # @!attribute [r] window_id [String, nil] window that produced the event
    # @!attribute [r] scope [Array<String>] reversed ancestor scope chain (immediate parent first)
    # @!attribute [r] data [Hash, nil] type-specific event data
    #
    # @example Click
    #   in Event::Widget[type: :click, id: "save"]
    # @example Input with value
    #   in Event::Widget[type: :input, id: "search", value:]
    # @example Canvas press
    #   in Event::Widget[type: :canvas_press, id: "chart", data: {x:, y:}]
    # @example Mouse area enter
    #   in Event::Widget[type: :mouse_enter, id: "hover_zone"]
    # @example Sensor resize
    #   in Event::Widget[type: :sensor_resize, id: "content", data: {width:, height:}]
    # @example Pane resized
    #   in Event::Widget[type: :pane_resized, id: "editor", data: {ratio:}]
    Widget = Data.define(:type, :id, :value, :window_id, :scope, :data) do
      def initialize(type:, id:, value: nil, window_id: nil, scope: [], data: nil)
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
    # @!attribute [r] window_id [String, nil] window that was focused when the event fired
    #
    # @example Key press with modifier
    #   in Event::Key[type: :press, key: "s", modifiers: { command: true }]
    # @example Any key release
    #   in Event::Key[type: :release, key:]
    Key = Data.define(:type, :key, :modified_key, :physical_key,
      :location, :modifiers, :text, :repeat, :captured, :window_id) do
      def initialize(type:, key:, modified_key: nil, physical_key: nil,
        location: :standard, modifiers: {}, text: nil, repeat: false,
        captured: false, window_id: nil)
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
    # @!attribute [r] window_id [String, nil] window that was focused when the event fired
    #
    # @example Mouse button press
    #   in Event::Mouse[type: :button_pressed, button: :left, x:, y:]
    # @example Scroll wheel
    #   in Event::Mouse[type: :wheel_scrolled, delta_y:]
    Mouse = Data.define(:type, :x, :y, :button, :delta_x, :delta_y, :unit, :captured, :window_id) do
      def initialize(type:, x: nil, y: nil, button: nil,
        delta_x: nil, delta_y: nil, unit: nil, captured: false, window_id: nil)
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
    # @!attribute [r] window_id [String, nil] window that was focused when the event fired
    #
    # @example Finger press
    #   in Event::Touch[type: :finger_pressed, finger_id:, x:, y:]
    # @example Finger lifted
    #   in Event::Touch[type: :finger_lifted, finger_id:]
    Touch = Data.define(:type, :finger_id, :x, :y, :captured, :window_id) do
      def initialize(type:, finger_id: nil, x: nil, y: nil, captured: false, window_id: nil)
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
    # @!attribute [r] window_id [String, nil] window that was focused when the event fired
    #
    # @example IME commit
    #   in Event::Ime[type: :commit, text:]
    # @example Preedit composition
    #   in Event::Ime[type: :preedit, text:, cursor:]
    Ime = Data.define(:type, :id, :scope, :text, :cursor, :captured, :window_id) do
      def initialize(type:, id: nil, scope: [], text: nil, cursor: nil,
        captured: false, window_id: nil)
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

    # Modifier key state change events.
    # Triggered when modifier keys (shift, ctrl, alt, command) change state.
    # Subscribe via Subscription.on_modifiers_changed.
    #
    # @!attribute [r] modifiers [Hash] current modifier state ({shift: true, control: false, alt: false, command: false})
    # @!attribute [r] captured [Boolean] true if a widget consumed this event
    # @!attribute [r] window_id [String, nil] window that was focused when the event fired
    #
    # @example Modifiers changed
    #   in Event::Modifiers[modifiers: { shift: true }]
    Modifiers = Data.define(:modifiers, :captured, :window_id) do
      def initialize(modifiers:, captured: false, window_id: nil)
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

    # Renderer error for a widget command.
    #
    # @!attribute [r] reason [String] machine-readable error reason
    # @!attribute [r] node_id [String, nil] target widget node ID
    # @!attribute [r] op [String, nil] command operation name
    # @!attribute [r] widget_type [String, nil] widget type name
    # @!attribute [r] message [String, nil] human-readable error text
    WidgetCommandError = Data.define(:reason, :node_id, :op, :widget_type, :message) do
      def initialize(reason:, node_id: nil, op: nil, widget_type: nil, message: nil)
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
