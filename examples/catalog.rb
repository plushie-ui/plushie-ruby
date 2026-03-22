# frozen_string_literal: true

# Widget catalog -- showcases available widget types.
#
# Demonstrates:
# - Multiple widget types in a single app
# - Layout composition with nested containers
# - State management for interactive widgets

require "plushie"

class Catalog
  include Plushie::App

  Model = Plushie::Model.define(
    :text_value, :checkbox_on, :toggle_on, :slider_val,
    :selected, :combo_value
  )

  OPTIONS = %w[Option\ A Option\ B Option\ C].freeze

  def init(_opts)
    Model.new(
      text_value: "",
      checkbox_on: false,
      toggle_on: true,
      slider_val: 50,
      selected: nil,
      combo_value: ""
    )
  end

  def update(model, event)
    case event
    in Event::Widget[type: :input, id: "text_demo", value:]
      model.with(text_value: value)
    in Event::Widget[type: :toggle, id: "checkbox_demo", value:]
      model.with(checkbox_on: value)
    in Event::Widget[type: :toggle, id: "toggler_demo", value:]
      model.with(toggle_on: value)
    in Event::Widget[type: :slide, id: "slider_demo", value:]
      model.with(slider_val: value.round)
    in Event::Widget[type: :select, id: "pick_demo", value:]
      model.with(selected: value)
    in Event::Widget[type: :input, id: "combo_demo", value:]
      model.with(combo_value: value)
    else
      model
    end
  end

  def view(model)
    window("main", title: "Widget Catalog", size: [700, 600]) do
      scrollable("scroll", width: :fill, height: :fill) do
        column("content", padding: 24, spacing: 20, width: :fill) do
          text("title", "Widget Catalog", size: 28)
          rule

          section("Buttons") do
            row(spacing: 8) do
              button("btn_default", "Default")
              button("btn_primary", "Primary", style: :primary)
              button("btn_secondary", "Secondary", style: :secondary)
              button("btn_disabled", "Disabled", disabled: true)
            end
          end

          section("Text Input") do
            text_input("text_demo", model.text_value,
              placeholder: "Type something...")
            text("text_echo", "Value: #{model.text_value}", color: "#888")
          end

          section("Checkbox & Toggler") do
            row(spacing: 16) do
              checkbox("checkbox_demo", model.checkbox_on)
              text("cb_label", model.checkbox_on ? "Checked" : "Unchecked")
              toggler("toggler_demo", model.toggle_on)
              text("tg_label", model.toggle_on ? "On" : "Off")
            end
          end

          section("Slider") do
            slider("slider_demo", [0, 100], model.slider_val)
            text("slider_value", "Value: #{model.slider_val}")
          end

          section("Pick List") do
            pick_list("pick_demo", OPTIONS, model.selected)
            text("pick_value", "Selected: #{model.selected || "(none)"}")
          end

          section("Progress Bar") do
            progress_bar("progress_demo", [0, 100], model.slider_val)
          end

          section("Markdown") do
            markdown("md_demo", "**Bold**, *italic*, `code`, [link](https://example.com)")
          end
        end
      end
    end
  end

  private

  def section(title, &block)
    column(spacing: 8, width: :fill) do
      text("section_#{title.downcase}", title, size: 18)
      block.call
    end
  end
end

Plushie.run(Catalog) if __FILE__ == $PROGRAM_NAME
