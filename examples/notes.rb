# frozen_string_literal: true

# Notes app with text editor and live markdown preview.
#
# Demonstrates:
# - text_editor widget for multi-line editing
# - markdown widget for rendering
# - Side-by-side layout with row + fill width

require "plushie"

class Notes
  include Plushie::App

  Model = Plushie::Model.define(:content)

  def init(_opts)
    Model.new(content: "# Welcome\n\nStart typing to see a **live preview**.")
  end

  def update(model, event)
    case event
    in Event::Widget[type: :input, id: "editor", value:]
      model.with(content: value)
    else
      model
    end
  end

  def view(model)
    window("main", title: "Notes", size: [900, 600]) do
      row(padding: 16, spacing: 16) do
        text_editor("editor", model.content, width: :fill, height: :fill)
        scrollable("preview_scroll", width: :fill, height: :fill) do
          markdown("preview", model.content, width: :fill)
        end
      end
    end
  end
end

Plushie.run(Notes) if __FILE__ == $PROGRAM_NAME
