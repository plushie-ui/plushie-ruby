# frozen_string_literal: true

# Notes application demonstrating all 5 state helpers working together.
#
# Demonstrates:
# - Plushie::State for nested state management
# - Plushie::Undo for reversible edits with labels
# - Plushie::Selection for multi-select with toggle
# - Plushie::Route for stack-based view navigation
# - Plushie::DataQuery for full-text search across fields

require "plushie"

class Notes
  include Plushie::App

  Model = Plushie::Model.define(:state, :selection, :undo, :route)

  # -- init ------------------------------------------------------------------

  def init(_opts)
    Model.new(
      state: Plushie::State.new(
        notes: [],
        next_id: 1,
        search_query: "",
        editing_id: nil
      ),
      selection: Plushie::Selection.new(mode: :multi),
      undo: Plushie::Undo.new({text: "", title: ""}),
      route: Plushie::Route.new("/list")
    )
  end

  # -- update ----------------------------------------------------------------

  def update(model, event)
    case event
    in Event::Widget[type: :click, id: "new_note"]
      state = model.state
      id = Plushie::State.get(state, [:next_id])

      note = {id: id, title: "", body: ""}

      state = Plushie::State.update(state, [:notes]) { |notes| notes + [note] }
      state = Plushie::State.put(state, [:next_id], id + 1)
      state = Plushie::State.put(state, [:editing_id], id)

      model.with(
        state: state,
        undo: Plushie::Undo.new({title: "", text: ""}),
        route: Plushie::Route.push(model.route, "/edit")
      )

    in Event::Widget[type: :click, id: /\Anote:(\d+)\z/ => matched_id]
      id = matched_id.delete_prefix("note:").to_i
      notes = Plushie::State.get(model.state, [:notes])
      note = notes.find { |n| n[:id] == id }

      if note
        state = Plushie::State.put(model.state, [:editing_id], id)

        model.with(
          state: state,
          undo: Plushie::Undo.new({title: note[:title], text: note[:body]}),
          route: Plushie::Route.push(model.route, "/edit")
        )
      else
        model
      end

    in Event::Widget[type: :click, id: "back"]
      model = save_current_edit(model)
      state = Plushie::State.put(model.state, [:editing_id], nil)

      model.with(state: state, route: Plushie::Route.pop(model.route))

    in Event::Widget[type: :click, id: "delete_selected"]
      selected = Plushie::Selection.selected(model.selection)

      state = Plushie::State.update(model.state, [:notes]) do |notes|
        notes.reject { |n| selected.include?(n[:id]) }
      end

      model.with(state: state, selection: Plushie::Selection.clear(model.selection))

    in Event::Widget[type: :input, id: "search", value:]
      model.with(state: Plushie::State.put(model.state, [:search_query], value))

    in Event::Widget[type: :input, id: "title", value:]
      old_title = Plushie::Undo.current(model.undo)[:title]

      cmd = {
        apply: ->(current) { current.merge(title: value) },
        undo: ->(current) { current.merge(title: old_title) },
        label: "edit title"
      }

      model.with(undo: Plushie::Undo.apply(model.undo, cmd))

    in Event::Widget[type: :input, id: "body", value:]
      old_text = Plushie::Undo.current(model.undo)[:text]

      cmd = {
        apply: ->(current) { current.merge(text: value) },
        undo: ->(current) { current.merge(text: old_text) },
        label: "edit body"
      }

      model.with(undo: Plushie::Undo.apply(model.undo, cmd))

    in Event::Widget[type: :click, id: "undo"]
      model.with(undo: Plushie::Undo.undo(model.undo))

    in Event::Widget[type: :click, id: "redo"]
      model.with(undo: Plushie::Undo.redo(model.undo))

    in Event::Widget[type: :toggle, id: /\Anote_select:(\d+)\z/ => matched_id]
      id = matched_id.delete_prefix("note_select:").to_i
      model.with(selection: Plushie::Selection.toggle(model.selection, id))

    else
      model
    end
  end

  # -- view ------------------------------------------------------------------

  def view(model)
    case Plushie::Route.current(model.route)
    when "/list" then view_list(model)
    when "/edit" then view_edit(model)
    end
  end

  private

  def view_list(model)
    search_query = Plushie::State.get(model.state, [:search_query])
    notes = Plushie::State.get(model.state, [:notes])

    filtered = if search_query == ""
      notes
    else
      result = Plushie::DataQuery.query(notes, search: [[:title, :body], search_query])
      result[:entries]
    end

    window("main", title: "Notes") do
      column(padding: 16, spacing: 12, width: :fill) do
        text("heading", "Notes", size: 24)

        text_input("search", search_query, placeholder: "Search notes...")

        scrollable("notes_list", height: :fill) do
          column(spacing: 4, width: :fill) do
            filtered.each do |note|
              row("note_row:#{note[:id]}", spacing: 8, width: :fill) do
                checkbox(
                  "note_select:#{note[:id]}",
                  Plushie::Selection.selected?(model.selection, note[:id]),
                  label: note[:title]
                )

                button("note:#{note[:id]}", "Edit")
              end
            end
          end
        end

        row(spacing: 8) do
          button("new_note", "New Note")
          button("delete_selected", "Delete Selected")
        end
      end
    end
  end

  def view_edit(model)
    current = Plushie::Undo.current(model.undo)

    window("main", title: "Edit Note") do
      column(padding: 16, spacing: 12, width: :fill) do
        row(spacing: 8) do
          button("back", "Back")
          button("undo", "Undo")
          button("redo", "Redo")
        end

        text_input("title", current[:title], placeholder: "Note title")
        text_editor("body", current[:text], width: :fill, height: :fill)
      end
    end
  end

  def save_current_edit(model)
    editing_id = Plushie::State.get(model.state, [:editing_id])

    if editing_id
      current = Plushie::Undo.current(model.undo)

      state = Plushie::State.update(model.state, [:notes]) do |notes|
        notes.map do |note|
          if note[:id] == editing_id
            note.merge(title: current[:title], body: current[:text])
          else
            note
          end
        end
      end

      model.with(state: state)
    else
      model
    end
  end
end

Plushie.run(Notes) if __FILE__ == $PROGRAM_NAME
