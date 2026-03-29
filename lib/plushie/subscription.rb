# frozen_string_literal: true

module Plushie
  # Declarative subscription specifications.
  #
  # Return subscriptions from your subscribe method. The runtime diffs
  # the list each cycle and starts/stops subscriptions automatically.
  #
  #   def subscribe(model)
  #     subs = [Subscription.on_key_press(:keys)]
  #     subs << Subscription.every(1000, :tick) if model.timer_running
  #     subs
  #   end
  #
  # Tag semantics differ by type:
  # - Timer subs: tag appears in the Timer event struct
  # - Renderer subs: tag is management-only (NOT in the event struct)
  #
  class Subscription
    # An immutable subscription specification.
    #
    # Created via factory methods on Subscription rather than directly.
    # The runtime uses `#key` to diff subscriptions between cycles,
    # starting new ones and stopping removed ones automatically.
    #
    # @!attribute [r] type [Symbol] subscription type (:every, :on_key_press, etc.)
    # @!attribute [r] tag [Symbol] identifier for subscription management and (for timers) event correlation
    # @!attribute [r] interval [Integer, nil] interval in milliseconds (only for :every)
    # @!attribute [r] max_rate [Integer, nil] maximum events per second (nil = unlimited)
    # @!attribute [r] window_id [String, nil] window scope (nil = all windows)
    Sub = Data.define(:type, :tag, :interval, :max_rate, :window_id) do
      def initialize(type:, tag:, interval: nil, max_rate: nil, window_id: nil)
        super
      end

      # Returns a key that uniquely identifies this subscription.
      # Used by the runtime to diff subscription lists between cycles.
      # Timer subs include the interval so that changing the interval
      # creates a new subscription rather than updating the existing one.
      #
      # @return [Array] unique identity tuple for this subscription
      def key
        if type == :every
          [:every, interval, tag]
        elsif window_id
          [type, tag, window_id]
        else
          [type, tag]
        end
      end

      # Set the maximum event rate (events per second).
      #
      # @param rate [Integer] max events per second
      # @return [Sub] new Sub with the rate applied
      def with_max_rate(rate)
        self.class.new(**to_h.merge(max_rate: rate))
      end
    end

    # Subscribe to a periodic timer.
    # Delivers {Event::Timer}[tag: tag, timestamp: ms] to update at the given interval.
    #
    # @param interval_ms [Integer] interval between ticks in milliseconds
    # @param tag [Symbol] tag that appears in the delivered Timer event
    # @return [Sub]
    def self.every(interval_ms, tag)
      Sub.new(type: :every, tag:, interval: interval_ms)
    end

    # Subscribe to keyboard press events.
    # Delivers {Event::Key}[type: :press, ...] to update.
    # The tag is for subscription management only -- it does NOT appear in the event.
    #
    # @param tag [Symbol] subscription management tag
    # @param max_rate [Integer, nil] max events per second (nil = unlimited)
    # @return [Sub]
    def self.on_key_press(tag, max_rate: nil, window: nil)
      Sub.new(type: :on_key_press, tag:, max_rate:, window_id: window)
    end

    # Subscribe to keyboard release events.
    # Delivers {Event::Key}[type: :release, ...] to update.
    # The tag is for subscription management only -- it does NOT appear in the event.
    #
    # @param tag [Symbol] subscription management tag
    # @param max_rate [Integer, nil] max events per second (nil = unlimited)
    # @return [Sub]
    def self.on_key_release(tag, max_rate: nil, window: nil)
      Sub.new(type: :on_key_release, tag:, max_rate:, window_id: window)
    end

    # Subscribe to modifier key state changes.
    # Delivers Event::Modifiers with the current modifier state to update when
    # shift, control, alt, or command keys change state.
    # The tag is for subscription management only -- it does NOT appear in the event.
    #
    # @param tag [Symbol] subscription management tag
    # @param max_rate [Integer, nil] max events per second (nil = unlimited)
    # @return [Sub]
    def self.on_modifiers_changed(tag, max_rate: nil, window: nil)
      Sub.new(type: :on_modifiers_changed, tag:, max_rate:, window_id: window)
    end

    # Subscribe to mouse movement events.
    # Delivers {Event::Mouse}[type: :moved, x:, y:] to update.
    # The tag is for subscription management only -- it does NOT appear in the event.
    #
    # @param tag [Symbol] subscription management tag
    # @param max_rate [Integer, nil] max events per second (nil = unlimited)
    # @return [Sub]
    def self.on_mouse_move(tag, max_rate: nil, window: nil)
      Sub.new(type: :on_mouse_move, tag:, max_rate:, window_id: window)
    end

    # Subscribe to mouse button press and release events.
    # Delivers {Event::Mouse}[type: :button_pressed/:button_released, ...] to update.
    # The tag is for subscription management only -- it does NOT appear in the event.
    #
    # @param tag [Symbol] subscription management tag
    # @param max_rate [Integer, nil] max events per second (nil = unlimited)
    # @return [Sub]
    def self.on_mouse_button(tag, max_rate: nil, window: nil)
      Sub.new(type: :on_mouse_button, tag:, max_rate:, window_id: window)
    end

    # Subscribe to mouse scroll wheel events.
    # Delivers {Event::Mouse}[type: :wheel_scrolled, delta_x:, delta_y:] to update.
    # The tag is for subscription management only -- it does NOT appear in the event.
    #
    # @param tag [Symbol] subscription management tag
    # @param max_rate [Integer, nil] max events per second (nil = unlimited)
    # @return [Sub]
    def self.on_mouse_scroll(tag, max_rate: nil, window: nil)
      Sub.new(type: :on_mouse_scroll, tag:, max_rate:, window_id: window)
    end

    # Subscribe to window close request events.
    # Delivers {Event::Window}[type: :close_requested, window_id:] to update.
    # The tag is for subscription management only -- it does NOT appear in the event.
    #
    # @param tag [Symbol] subscription management tag
    # @param max_rate [Integer, nil] max events per second (nil = unlimited)
    # @return [Sub]
    def self.on_window_close(tag, max_rate: nil, window: nil)
      Sub.new(type: :on_window_close, tag:, max_rate:, window_id: window)
    end

    # Subscribe to window opened events.
    # Delivers {Event::Window}[type: :opened, window_id:, width:, height:] to update.
    # The tag is for subscription management only -- it does NOT appear in the event.
    #
    # @param tag [Symbol] subscription management tag
    # @param max_rate [Integer, nil] max events per second (nil = unlimited)
    # @return [Sub]
    def self.on_window_open(tag, max_rate: nil, window: nil)
      Sub.new(type: :on_window_open, tag:, max_rate:, window_id: window)
    end

    # Subscribe to window resize events.
    # Delivers {Event::Window}[type: :resized, window_id:, width:, height:] to update.
    # The tag is for subscription management only -- it does NOT appear in the event.
    #
    # @param tag [Symbol] subscription management tag
    # @param max_rate [Integer, nil] max events per second (nil = unlimited)
    # @return [Sub]
    def self.on_window_resize(tag, max_rate: nil, window: nil)
      Sub.new(type: :on_window_resize, tag:, max_rate:, window_id: window)
    end

    # Subscribe to window focus events.
    # Delivers {Event::Window}[type: :focused, window_id:] to update.
    # The tag is for subscription management only -- it does NOT appear in the event.
    #
    # @param tag [Symbol] subscription management tag
    # @param max_rate [Integer, nil] max events per second (nil = unlimited)
    # @return [Sub]
    def self.on_window_focus(tag, max_rate: nil, window: nil)
      Sub.new(type: :on_window_focus, tag:, max_rate:, window_id: window)
    end

    # Subscribe to window unfocus events.
    # Delivers {Event::Window}[type: :unfocused, window_id:] to update.
    # The tag is for subscription management only -- it does NOT appear in the event.
    #
    # @param tag [Symbol] subscription management tag
    # @param max_rate [Integer, nil] max events per second (nil = unlimited)
    # @return [Sub]
    def self.on_window_unfocus(tag, max_rate: nil, window: nil)
      Sub.new(type: :on_window_unfocus, tag:, max_rate:, window_id: window)
    end

    # Subscribe to window move events.
    # Delivers {Event::Window}[type: :moved, window_id:, x:, y:] to update.
    # The tag is for subscription management only -- it does NOT appear in the event.
    #
    # @param tag [Symbol] subscription management tag
    # @param max_rate [Integer, nil] max events per second (nil = unlimited)
    # @return [Sub]
    def self.on_window_move(tag, max_rate: nil, window: nil)
      Sub.new(type: :on_window_move, tag:, max_rate:, window_id: window)
    end

    # Subscribe to touch screen events (finger press, lift, move, lost).
    # Delivers {Event::Touch}[type: :finger_pressed/:finger_lifted/..., ...] to update.
    # The tag is for subscription management only -- it does NOT appear in the event.
    #
    # @param tag [Symbol] subscription management tag
    # @param max_rate [Integer, nil] max events per second (nil = unlimited)
    # @return [Sub]
    def self.on_touch(tag, max_rate: nil, window: nil)
      Sub.new(type: :on_touch, tag:, max_rate:, window_id: window)
    end

    # Subscribe to IME (Input Method Editor) composition events.
    # Delivers {Event::Ime}[type: :enabled/:preedit/:commit/:disabled, ...] to update.
    # The tag is for subscription management only -- it does NOT appear in the event.
    #
    # @param tag [Symbol] subscription management tag
    # @param max_rate [Integer, nil] max events per second (nil = unlimited)
    # @return [Sub]
    def self.on_ime(tag, max_rate: nil, window: nil)
      Sub.new(type: :on_ime, tag:, max_rate:, window_id: window)
    end

    # Subscribe to OS theme changes (light/dark mode).
    # Delivers {Event::System}[type: :theme_changed, data: theme_name] to update.
    # The tag is for subscription management only -- it does NOT appear in the event.
    #
    # @param tag [Symbol] subscription management tag
    # @param max_rate [Integer, nil] max events per second (nil = unlimited)
    # @return [Sub]
    def self.on_theme_change(tag, max_rate: nil, window: nil)
      Sub.new(type: :on_theme_change, tag:, max_rate:, window_id: window)
    end

    # Subscribe to animation frame ticks for smooth animations.
    # Delivers {Event::System}[type: :animation_frame, data: delta_ms] to update.
    # The tag is for subscription management only -- it does NOT appear in the event.
    #
    # @param tag [Symbol] subscription management tag
    # @param max_rate [Integer, nil] max events per second (nil = unlimited)
    # @return [Sub]
    def self.on_animation_frame(tag, max_rate: nil, window: nil)
      Sub.new(type: :on_animation_frame, tag:, max_rate:, window_id: window)
    end

    # Subscribe to file drag and drop events.
    # Delivers {Event::Window}[type: :file_dropped/:file_hovered, path:] to update.
    # The tag is for subscription management only -- it does NOT appear in the event.
    #
    # @param tag [Symbol] subscription management tag
    # @param max_rate [Integer, nil] max events per second (nil = unlimited)
    # @return [Sub]
    def self.on_file_drop(tag, max_rate: nil, window: nil)
      Sub.new(type: :on_file_drop, tag:, max_rate:, window_id: window)
    end

    # Subscribe to all renderer events (catch-all).
    # Delivers the raw event to update without filtering by type.
    # Useful for debugging or handling event types not covered by specific subscriptions.
    # The tag is for subscription management only -- it does NOT appear in the event.
    #
    # @param tag [Symbol] subscription management tag
    # @param max_rate [Integer, nil] max events per second (nil = unlimited)
    # @return [Sub]
    def self.on_event(tag, max_rate: nil, window: nil)
      Sub.new(type: :on_event, tag:, max_rate:, window_id: window)
    end

    # Scope a list of subscriptions to a specific window.
    #
    # Window-scoped subscriptions tell the renderer to only deliver events
    # from the given window. Without a window scope, subscriptions receive
    # events from all windows.
    #
    #   Subscription.for_window("editor", [
    #     Subscription.on_key_press(:editor_keys),
    #     Subscription.on_mouse_move(:editor_mouse, max_rate: 60)
    #   ])
    #
    # @param window_id [String]
    # @param subscriptions [Array<Sub>]
    # @return [Array<Sub>]
    def self.for_window(window_id, subscriptions)
      subscriptions.map { |sub| sub.with(window_id: window_id) }
    end
  end
end
