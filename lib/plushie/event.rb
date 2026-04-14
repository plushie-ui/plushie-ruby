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
    # All widget interaction events.
    #
    # Covers standard widget events (:click, :input, :submit, etc.),
    # unified pointer events (:press, :release, :move, :scroll, :enter,
    # :exit, :double_click, :resize), generic element events (:focused,
    # :blurred, :drag, :drag_end, :key_press, :key_release), pane events
    # (:pane_resized, :pane_dragged, :pane_clicked), animation events
    # (:transition_complete), and subscription pointer events.
    #
    # The +value+ field carries the event payload. For single-value
    # events (input text, slider position, toggle state) it holds
    # the scalar. For multi-field events (pointer coordinates, pane
    # operations, key data) it holds a symbol-keyed Hash.
    #
    # The +scope+ array lists ancestor container IDs from immediate
    # parent to outermost. The window_id is appended as the last
    # element (outermost ancestor). Use Event.target to reconstruct
    # the forward-order path (window_id is stripped).
    #
    # @!attribute [r] type [Symbol] event kind
    # @!attribute [r] id [String] widget ID that produced the event
    # @!attribute [r] value [Object, nil] event payload (scalar or symbol-keyed Hash)
    # @!attribute [r] window_id [String, nil] window that produced the event
    # @!attribute [r] scope [Array<String>] reversed ancestor scope chain (immediate parent first, window_id last)
    #
    # @example Click
    #   in Event::Widget[type: :click, id: "save"]
    # @example Input with value
    #   in Event::Widget[type: :input, id: "search", value:]
    # @example Pointer press
    #   in Event::Widget[type: :press, id: "canvas", value: {x:, y:, button: :left}]
    # @example Enter (cursor hover or touch enter)
    #   in Event::Widget[type: :enter, id: "hover_zone"]
    # @example Resize (sensor)
    #   in Event::Widget[type: :resize, id: "content", value: {width:, height:}]
    # @example Pane resized
    #   in Event::Widget[type: :pane_resized, id: "editor", value: {ratio:}]
    Widget = Data.define(:type, :id, :value, :window_id, :scope) do
      def initialize(type:, id:, value: nil, window_id: nil, scope: [])
        super
      end
    end

    # Keyboard events delivered when keys are pressed or released.
    # Triggered by keyboard input while the window has focus.
    # Subscribe via Subscription.on_key_press or Subscription.on_key_release.
    #
    # @!attribute [r] type [Symbol] :press or :release
    # @!attribute [r] key [Symbol, String] logical key name (:escape, :enter, "a", "s", etc.)
    # @!attribute [r] modified_key [Symbol, String, nil] key with modifiers applied
    # @!attribute [r] physical_key [Symbol, String, nil] hardware scan code name
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

    # IME (Input Method Editor) events for international text input.
    # Triggered by IME composition sessions (CJK input, accent composition, etc.).
    # Subscribe via Subscription.on_ime.
    #
    # @!attribute [r] type [Symbol] :opened, :preedit, :commit, :closed
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
    # The tag matches the symbol passed when creating the effect command.
    #
    # @!attribute [r] tag [Symbol] the tag from the originating effect command
    # @!attribute [r] result [Object] operation result: [:ok, data], :cancelled, or [:error, reason]
    #
    # @example File dialog result
    #   in Event::Effect[tag: :import, result: [:ok, result]]
    # @example Cancelled
    #   in Event::Effect[tag: :import, result: :cancelled]
    Effect = Data.define(:tag, :result)

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
    # @!attribute [r] value [Object, nil] event payload (theme name for :theme_changed, delta ms for :animation_frame)
    #
    # @example Theme changed
    #   in Event::System[type: :theme_changed, value: theme]
    # @example Animation frame
    #   in Event::System[type: :animation_frame, value: delta_ms]
    System = Data.define(:type, :tag, :value) do
      def initialize(type:, tag: nil, value: nil)
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
    # Strips the window_id from scope (it appears at the end of the
    # scope list but is not part of the container path).
    #
    #   Event.target(widget_event) # => "sidebar/form/save"
    #
    def self.target(event)
      scope = event.respond_to?(:scope) ? event.scope : []
      window_id = event.respond_to?(:window_id) ? event.window_id : nil

      scope = strip_window_scope(scope, window_id)

      return event.id if scope.empty?
      (scope.reverse + [event.id]).join("/")
    end

    # Remove window_id from the end of a scope array.
    # @api private
    def self.strip_window_scope(scope, window_id)
      return scope if window_id.nil? || scope.empty?
      (scope.last == window_id) ? scope[0...-1] : scope
    end
  end
end
