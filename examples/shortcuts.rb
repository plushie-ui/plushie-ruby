# frozen_string_literal: true

# Keyboard shortcuts example showing a scrollable log of key presses.
#
# Demonstrates:
# - Subscription.on_key_press for global keyboard events
# - Pattern matching on Event::Key with modifier inspection
# - scrollable for overflow content with dynamic list items
# - Capped log buffer (MAX_LOG_ENTRIES)

require "plushie"

class Shortcuts
  include Plushie::App

  MAX_LOG_ENTRIES = 50

  Model = Plushie::Model.define(:log, :count)

  def init(_opts)
    Model.new(log: [], count: 0)
  end

  def update(model, event)
    case event
    in Event::Key[type: :press, key:, modifiers:]
      entry = format_key_event(key, modifiers, model.count + 1)
      model.with(
        log: [entry, *model.log].first(MAX_LOG_ENTRIES),
        count: model.count + 1
      )
    else
      model
    end
  end

  def subscribe(_model)
    [Subscription.on_key_press(:keys)]
  end

  def view(model)
    window("main", title: "Keyboard Shortcuts") do
      column(padding: 16, spacing: 12, width: :fill) do
        text("header", "Press any key", size: 20)
        text("count", "#{model.count} key events captured", size: 12, color: "#888888")

        rule()

        scrollable("log", height: :fill) do
          column(spacing: 2, width: :fill) do
            model.log.each_with_index do |entry, index|
              text("log_#{index}", entry, size: 13)
            end
          end
        end
      end
    end
  end

  private

  def format_key_event(key, modifiers, n)
    mods = format_modifiers(modifiers)
    key_str = key.to_s.inspect
    prefix = mods.empty? ? "" : "#{mods}+"
    "##{n}: #{prefix}#{key_str}"
  end

  def format_modifiers(modifiers)
    parts = []
    parts << "Ctrl" if modifiers[:command] || modifiers[:ctrl]
    parts << "Alt" if modifiers[:alt]
    parts << "Shift" if modifiers[:shift]
    parts << "Super" if modifiers[:logo]
    parts.join("+")
  end
end

Plushie.run(Shortcuts) if __FILE__ == $PROGRAM_NAME
