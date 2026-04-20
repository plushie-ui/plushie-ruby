# frozen_string_literal: true

require_relative "event/specs"

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
  #     [model, Command.task(-> { save(model) }, :save_result)]
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

      # Category predicates for event type families.

      # Pointer events (press, release, move, scroll, enter, exit, double_click).
      def pointer? = Specs::POINTER_TYPES.include?(type)

      # Widget-scoped keyboard events (key_press, key_release).
      def keyboard? = Specs::KEYBOARD_TYPES.include?(type)

      # Pane grid events (pane_resized, pane_dragged, pane_clicked, pane_focus_cycle).
      def pane? = Specs::PANE_TYPES.include?(type)

      # Focus lifecycle events (focused, blurred).
      def focus? = Specs::FOCUS_TYPES.include?(type)

      # Drag events (drag, drag_end).
      def drag? = Specs::DRAG_TYPES.include?(type)

      # Look up the spec for this event's type.
      # @return [Hash, nil]
      def spec = Specs.for(type)
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
    # @!attribute [r] type [Symbol] :opened, :close_requested, :closed,
    #   :resized, :rescaled, :moved, :focused, :unfocused, :file_dropped,
    #   :file_hovered, :files_hovered_left
    # @!attribute [r] window_id [String, nil] ID of the affected window
    # @!attribute [r] x [Float, nil] window x position (for :moved)
    # @!attribute [r] y [Float, nil] window y position (for :moved)
    # @!attribute [r] width [Float, nil] window width (for :resized, :opened)
    # @!attribute [r] height [Float, nil] window height (for :resized, :opened)
    # @!attribute [r] scale_factor [Float, nil] display scale factor (for :rescaled)
    # @!attribute [r] path [String, nil] file path (for :file_dropped, :file_hovered)
    #
    # @example Window close requested
    #   in Event::Window[type: :close_requested, window_id:]
    # @example Window resized
    #   in Event::Window[type: :resized, width:, height:]
    # @example Display scale changed
    #   in Event::Window[type: :rescaled, scale_factor:]
    # @example File drop cancelled (cursor left the window while hovering)
    #   in Event::Window[type: :files_hovered_left, window_id:]
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

    # Effect result events for platform operations (file dialogs,
    # clipboard, notifications). Triggered when an asynchronous platform
    # effect completes. The tag matches the symbol passed when creating
    # the effect command. The `result` field is a typed per-kind
    # Data class from Event::Effect::Result (FileOpened, ClipboardText,
    # Cancelled, Timeout, Error, etc.) rather than a generic tuple.
    #
    # @!attribute [r] tag [Symbol] the tag from the originating effect command
    # @!attribute [r] result [Event::Effect::Result] typed outcome
    #
    # @example File dialog result
    #   in Event::Effect[tag: :import, result: Event::Effect::Result::FileOpened[path:]]
    # @example Cancelled
    #   in Event::Effect[tag: :import, result: Event::Effect::Result::Cancelled[]]
    Effect = Data.define(:tag, :result)

    # Typed per-kind outcomes nested under Event::Effect.
    #
    # Matches the Rust SDK's EffectResult enum. Host SDKs share the
    # concept across language-idiomatic shapes; Ruby uses Data.define
    # classes so apps can pattern-match on the class with Ruby's
    # native `case/in` syntax.
    module Effect::Result
      FileOpened = Data.define(:path)
      FilesOpened = Data.define(:paths)
      FileSaved = Data.define(:path)
      DirectorySelected = Data.define(:path)
      DirectoriesSelected = Data.define(:paths)
      ClipboardText = Data.define(:text)
      ClipboardHtml = Data.define(:html, :alt_text) do
        def initialize(html:, alt_text: nil)
          super
        end
      end
      ClipboardWritten = Data.define
      ClipboardCleared = Data.define
      NotificationShown = Data.define
      Cancelled = Data.define
      Timeout = Data.define
      Error = Data.define(:message)
      Unsupported = Data.define
      RendererRestarted = Data.define

      # Decode a renderer-supplied (kind, status, payload) triple
      # into the appropriate Data.define instance.
      #
      # @param kind [String] effect kind, e.g. "file_open"
      # @param status [String] wire status: "ok", "cancelled",
      #   "error", "unsupported"
      # @param payload [Object, nil] result payload on "ok" or the
      #   error reason on "error"
      # @return [Object] typed result instance
      def self.decode(kind, status, payload)
        case status
        when "cancelled" then Cancelled.new
        when "unsupported" then Unsupported.new
        when "error" then Error.new(message: payload.to_s)
        when "ok" then decode_ok(kind, payload.is_a?(Hash) ? payload : {})
        else Error.new(message: "unknown effect status: #{status}")
        end
      end

      def self.decode_ok(kind, payload)
        case kind
        when "file_open"
          FileOpened.new(path: fetch_string(payload, :path))
        when "file_open_multiple"
          FilesOpened.new(paths: fetch_paths(payload, :paths))
        when "file_save"
          FileSaved.new(path: fetch_string(payload, :path))
        when "directory_select"
          DirectorySelected.new(path: fetch_string(payload, :path))
        when "directory_select_multiple"
          DirectoriesSelected.new(paths: fetch_paths(payload, :paths))
        when "clipboard_read", "clipboard_read_primary"
          ClipboardText.new(text: fetch_string(payload, :text))
        when "clipboard_read_html"
          ClipboardHtml.new(
            html: fetch_string(payload, :html),
            alt_text: fetch_optional_string(payload, :alt_text)
          )
        when "clipboard_write", "clipboard_write_html", "clipboard_write_primary"
          ClipboardWritten.new
        when "clipboard_clear"
          ClipboardCleared.new
        when "notification"
          NotificationShown.new
        else
          Error.new(message: "unknown effect kind: #{kind}")
        end
      end

      def self.fetch_string(hash, key)
        v = hash[key] || hash[key.to_s]
        v.is_a?(String) ? v : ""
      end

      def self.fetch_optional_string(hash, key)
        v = hash[key] || hash[key.to_s]
        v.is_a?(String) ? v : nil
      end

      def self.fetch_paths(hash, key)
        v = hash[key] || hash[key.to_s]
        v.is_a?(Array) ? v.select { _1.is_a?(String) } : []
      end

      private_class_method :decode_ok, :fetch_string, :fetch_optional_string, :fetch_paths
    end

    # Renderer error for a command.
    #
    # Emitted when the renderer cannot deliver or execute a command.
    #
    # @!attribute [r] reason [String] machine-readable error reason
    # @!attribute [r] id [String, nil] target widget ID
    # @!attribute [r] family [String, nil] command family name
    # @!attribute [r] widget_type [String, nil] widget type name
    # @!attribute [r] message [String, nil] human-readable error text
    #
    # @example
    #   in Event::CommandError[family:, id:, message:]
    #     logger.warn("command #{family} failed on #{id}: #{message}")
    CommandError = Data.define(:reason, :id, :family, :widget_type, :message) do
      def initialize(reason:, id: nil, family: nil, widget_type: nil, message: nil)
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
