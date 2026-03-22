# frozen_string_literal: true

# Keyboard shortcut example.
#
# Demonstrates:
# - Subscription.on_key_press for global keyboard events
# - Pattern matching on Event::Key with modifiers
# - Event log display

require "plushie"

class Shortcuts
  include Plushie::App

  Model = Plushie::Model.define(:log, :count)

  def init(_opts)
    Model.new(log: [], count: 0)
  end

  def subscribe(_model)
    [Subscription.on_key_press(:keys)]
  end

  def update(model, event)
    case event
    in Event::Key[type: :press, key: "s", modifiers: {command: true}]
      add_log(model, "Ctrl+S: Save!")

    in Event::Key[type: :press, key: :escape]
      add_log(model, "Escape: Clear log")
        .with(log: [])

    in Event::Key[type: :press, key:, modifiers:]
      mod_str = modifiers.select { |_, v| v }.keys.join("+")
      key_str = mod_str.empty? ? key.to_s : "#{mod_str}+#{key}"
      add_log(model, "Key: #{key_str}")

    in Event::Widget[type: :click, id: "clear"]
      model.with(log: [], count: 0)

    else
      model
    end
  end

  def view(model)
    window("main", title: "Keyboard Shortcuts") do
      column(padding: 16, spacing: 12, width: :fill) do
        text("title", "Press any key (try Ctrl+S, Escape)", size: 18)
        text("counter", "Events captured: #{model.count}", color: "#888")
        button("clear", "Clear Log")
        scrollable("log_scroll", height: 300) do
          column("log_list", spacing: 4) do
            model.log.last(20).each_with_index do |entry, i|
              text("log_#{i}", entry, size: 13, color: "#666")
            end
          end
        end
      end
    end
  end

  private

  def add_log(model, message)
    model.with(
      log: model.log + [message],
      count: model.count + 1
    )
  end
end

Plushie.run(Shortcuts) if __FILE__ == $PROGRAM_NAME
