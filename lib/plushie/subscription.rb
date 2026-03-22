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
    Sub = Data.define(:type, :tag, :interval, :max_rate) do
      def initialize(type:, tag:, interval: nil, max_rate: nil)
        super
      end

      # Returns a key that uniquely identifies this subscription.
      def key
        if type == :every
          [:every, interval, tag]
        else
          [type, tag]
        end
      end

      # Set the maximum event rate (events per second).
      def with_max_rate(rate)
        self.class.new(**to_h.merge(max_rate: rate))
      end
    end

    # Timer that fires every interval_ms milliseconds.
    # Delivers Event::Timer[tag: tag, timestamp: ms] to update.
    def self.every(interval_ms, tag)
      Sub.new(type: :every, tag:, interval: interval_ms)
    end

    # Keyboard press events. Delivers Event::Key[type: :press, ...].
    def self.on_key_press(tag, max_rate: nil)
      Sub.new(type: :on_key_press, tag:, max_rate:)
    end

    # Keyboard release events. Delivers Event::Key[type: :release, ...].
    def self.on_key_release(tag, max_rate: nil)
      Sub.new(type: :on_key_release, tag:, max_rate:)
    end

    # Modifier key state changes. Delivers Event::Modifiers.
    def self.on_modifiers_changed(tag, max_rate: nil)
      Sub.new(type: :on_modifiers_changed, tag:, max_rate:)
    end

    # Mouse movement. Delivers Event::Mouse[type: :moved, ...].
    def self.on_mouse_move(tag, max_rate: nil)
      Sub.new(type: :on_mouse_move, tag:, max_rate:)
    end

    # Mouse button events. Delivers Event::Mouse[type: :button_pressed/:button_released, ...].
    def self.on_mouse_button(tag, max_rate: nil)
      Sub.new(type: :on_mouse_button, tag:, max_rate:)
    end

    # Mouse scroll events. Delivers Event::Mouse[type: :wheel_scrolled, ...].
    def self.on_mouse_scroll(tag, max_rate: nil)
      Sub.new(type: :on_mouse_scroll, tag:, max_rate:)
    end

    # Window close requested. Delivers Event::Window[type: :close_requested, ...].
    def self.on_window_close(tag, max_rate: nil)
      Sub.new(type: :on_window_close, tag:, max_rate:)
    end

    # Window opened. Delivers Event::Window[type: :opened, ...].
    def self.on_window_open(tag, max_rate: nil)
      Sub.new(type: :on_window_open, tag:, max_rate:)
    end

    # Window resized. Delivers Event::Window[type: :resized, ...].
    def self.on_window_resize(tag, max_rate: nil)
      Sub.new(type: :on_window_resize, tag:, max_rate:)
    end

    # Window focused. Delivers Event::Window[type: :focused, ...].
    def self.on_window_focus(tag, max_rate: nil)
      Sub.new(type: :on_window_focus, tag:, max_rate:)
    end

    # Window unfocused. Delivers Event::Window[type: :unfocused, ...].
    def self.on_window_unfocus(tag, max_rate: nil)
      Sub.new(type: :on_window_unfocus, tag:, max_rate:)
    end

    # Window moved. Delivers Event::Window[type: :moved, ...].
    def self.on_window_move(tag, max_rate: nil)
      Sub.new(type: :on_window_move, tag:, max_rate:)
    end

    # Touch events. Delivers Event::Touch.
    def self.on_touch(tag, max_rate: nil)
      Sub.new(type: :on_touch, tag:, max_rate:)
    end

    # IME events. Delivers Event::Ime.
    def self.on_ime(tag, max_rate: nil)
      Sub.new(type: :on_ime, tag:, max_rate:)
    end

    # OS theme changes. Delivers Event::System[type: :theme_changed, ...].
    def self.on_theme_change(tag, max_rate: nil)
      Sub.new(type: :on_theme_change, tag:, max_rate:)
    end

    # Animation frame ticks. Delivers Event::System[type: :animation_frame, ...].
    def self.on_animation_frame(tag, max_rate: nil)
      Sub.new(type: :on_animation_frame, tag:, max_rate:)
    end

    # File drag and drop. Delivers Event::Window[type: :file_dropped/:file_hovered, ...].
    def self.on_file_drop(tag, max_rate: nil)
      Sub.new(type: :on_file_drop, tag:, max_rate:)
    end

    # All renderer events (catch-all).
    def self.on_event(tag, max_rate: nil)
      Sub.new(type: :on_event, tag:, max_rate:)
    end
  end
end
