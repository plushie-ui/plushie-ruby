# frozen_string_literal: true

# Comprehensive widget catalog exercising every real iced widget type in Plushie.
#
# Organized as a column layout with tab-like navigation across four sections:
# layout, input, display, and composite. Each section demonstrates a category
# of widgets with realistic props and interactive state.
#
# Demonstrated widgets:
#
# Layout: column, row, container, scrollable, stack, grid, pin, floating,
# responsive, keyed_column, themer, space
#
# Input: button, text_input, checkbox, toggler, radio, slider,
# vertical_slider, pick_list, combo_box, text_editor
#
# Display: text, rule, progress_bar, tooltip, image, svg, markdown,
# rich_text, canvas
#
# Interactive/Composite: mouse_area, sensor, pane_grid, table

require "plushie"

class Catalog
  include Plushie::App

  Model = Plushie::Model.define(
    :active_tab,
    :demo_tabs_active,
    :text_value,
    :checkbox_checked,
    :toggler_on,
    :slider_value,
    :vslider_value,
    :radio_selected,
    :pick_list_selected,
    :combo_value,
    :editor_content,
    :progress,
    :panel_collapsed,
    :modal_visible,
    :click_count,
    :mouse_area_status,
    :sensor_status
  )

  # -- init ------------------------------------------------------------------

  def init(_opts)
    Model.new(
      active_tab: "layout",
      demo_tabs_active: "tab_one",
      text_value: "",
      checkbox_checked: false,
      toggler_on: false,
      slider_value: 50,
      vslider_value: 50,
      radio_selected: "a",
      pick_list_selected: nil,
      combo_value: nil,
      editor_content: "Edit me...",
      progress: 65,
      panel_collapsed: false,
      modal_visible: false,
      click_count: 0,
      mouse_area_status: "idle",
      sensor_status: "waiting"
    )
  end

  # -- update ----------------------------------------------------------------

  def update(model, event)
    case event
    # Tab switching
    in Event::Widget[type: :click, id: "tab_layout"]
      model.with(active_tab: "layout")
    in Event::Widget[type: :click, id: "tab_input"]
      model.with(active_tab: "input")
    in Event::Widget[type: :click, id: "tab_display"]
      model.with(active_tab: "display")
    in Event::Widget[type: :click, id: "tab_composite"]
      model.with(active_tab: "composite")

    # Input widgets
    in Event::Widget[type: :input, id: "demo_input", value:]
      model.with(text_value: value)
    in Event::Widget[type: :toggle, id: "demo_check", value:]
      model.with(checkbox_checked: value)
    in Event::Widget[type: :toggle, id: "demo_toggler", value:]
      model.with(toggler_on: value)
    in Event::Widget[type: :slide, id: "demo_slider", value:]
      model.with(slider_value: value)
    in Event::Widget[type: :slide, id: "demo_vslider", value:]
      model.with(vslider_value: value)
    in Event::Widget[type: :select, id: "demo_radio", value:]
      model.with(radio_selected: value)
    in Event::Widget[type: :select, id: "demo_pick", value:]
      model.with(pick_list_selected: value)
    in Event::Widget[type: :select, id: "demo_combo", value:]
      model.with(combo_value: value)
    in Event::Widget[type: :input, id: "demo_editor", value:]
      model.with(editor_content: value)

    # Composite section - simulated tab switching with buttons
    in Event::Widget[type: :click, id: "tab_one"]
      model.with(demo_tabs_active: "tab_one")
    in Event::Widget[type: :click, id: "tab_two"]
      model.with(demo_tabs_active: "tab_two")

    # Modal show/hide
    in Event::Widget[type: :click, id: "show_modal"]
      model.with(modal_visible: true)
    in Event::Widget[type: :click, id: "hide_modal"]
      model.with(modal_visible: false)

    # Panel collapse toggle
    in Event::Widget[type: :click, id: "demo_panel"]
      model.with(panel_collapsed: !model.panel_collapsed)

    # Interactive widgets
    in Event::Widget[type: :click, id: "counter_btn"]
      model.with(click_count: model.click_count + 1)
    in Event::Widget[type: :click, id: "inc_progress"]
      model.with(progress: [model.progress + 5, 100].min)

    # Mouse area events
    in Event::MouseArea[type: :enter, id: "demo_mouse_area"]
      model.with(mouse_area_status: "hovering")
    in Event::MouseArea[type: :exit, id: "demo_mouse_area"]
      model.with(mouse_area_status: "idle")

    # Sensor events
    in Event::Sensor[type: :resize, id: "demo_sensor"]
      model.with(sensor_status: "activated")

    # Catch-all
    else
      model
    end
  end

  # -- view ------------------------------------------------------------------

  def view(model)
    window("catalog", title: "Widget Catalog") do
      column(spacing: 12, padding: 16) do
        text("catalog_title", "Plushie Widget Catalog", size: 24)
        rule

        row(spacing: 8) do
          button("tab_layout", "Layout")
          button("tab_input", "Input")
          button("tab_display", "Display")
          button("tab_composite", "Composite")
        end

        rule

        case model.active_tab
        when "layout" then layout_tab
        when "input" then input_tab(model)
        when "display" then display_tab(model)
        when "composite" then composite_tab(model)
        end
      end
    end
  end

  private

  # -- tab views -------------------------------------------------------------

  def layout_tab
    column(spacing: 8) do
      text("layout_heading", "Layout Widgets", size: 18)

      # Row
      row(spacing: 8) do
        text("Row child 1")
        text("Row child 2")
        text("Row child 3")
      end

      # Nested column
      column(spacing: 4) do
        text("Nested column child 1")
        text("Nested column child 2")
      end

      # Container with padding
      container("demo_container", padding: 12) do
        text("Inside a container")
      end

      # Scrollable
      scrollable("demo_scrollable") do
        column(spacing: 4) do
          text("Scrollable item 1")
          text("Scrollable item 2")
          text("Scrollable item 3")
          text("Scrollable item 4")
          text("Scrollable item 5")
        end
      end

      # Stack - layers on top of each other
      stack do
        text("Stack layer 1 (back)")
        text("Stack layer 2 (front)")
      end

      # Grid layout
      grid(columns: 3, spacing: 4) do
        text("Grid 1")
        text("Grid 2")
        text("Grid 3")
        text("Grid 4")
        text("Grid 5")
        text("Grid 6")
      end

      # Pin - positioned element
      pin("demo_pin", x: 0, y: 0) do
        text("Pinned content")
      end

      # Float - floating overlay element with translation
      floating("demo_float", translate_x: 100, translate_y: 10) do
        text("Floating element")
      end

      # Responsive layout
      responsive("demo_responsive") do
        column do
          text("Responsive content adapts to width")
        end
      end

      # Keyed column - stable identity for children
      keyed_column(spacing: 4) do
        text("key_a", "Keyed item A")
        text("key_b", "Keyed item B")
        text("key_c", "Keyed item C")
      end

      # Themer - overrides the theme for its subtree
      themer("demo_themer",
        theme: {background: "#1a1a2e", text: "#e0e0e0", primary: "#0f3460"}) do
        container("themed_box", padding: 12) do
          column(spacing: 4) do
            text("Themed section with custom palette")
            button("themed_btn", "Themed Button")
          end
        end
      end

      # Space - explicit gap
      space(height: 16)
    end
  end

  def input_tab(model)
    column(spacing: 8) do
      text("input_heading", "Input Widgets", size: 18)

      # Text input
      text_input("demo_input", model.text_value, placeholder: "Type here...")

      # Button
      button("demo_button", "A Button")

      # Checkbox
      checkbox("demo_check", model.checkbox_checked, label: "Check me")

      # Toggler
      toggler("demo_toggler", model.toggler_on, label: "Toggle me")

      # Radio group
      radio("demo_radio", %w[a b c], model.radio_selected)

      # Slider
      slider("demo_slider", [0, 100], model.slider_value, step: 1)
      text("Slider: #{model.slider_value}")

      # Vertical slider
      vertical_slider("demo_vslider", [0, 100], model.vslider_value, step: 1)

      # Pick list
      pick_list("demo_pick", %w[Small Medium Large], model.pick_list_selected,
        placeholder: "Pick a size...")

      # Combo box
      combo_box("demo_combo", %w[Elixir Rust Go], model.combo_value || "",
        placeholder: "Choose a language...")

      # Text editor
      text_editor("demo_editor", model.editor_content, height: 100)
    end
  end

  def display_tab(model)
    column(spacing: 8) do
      text("display_heading", "Display Widgets", size: 18)

      # Plain text
      text("Plain text label")

      # Rule (horizontal divider)
      rule

      # Progress bar with interactive control
      row(spacing: 8) do
        progress_bar("demo_progress", [0, 100], model.progress)
        button("inc_progress", "+5%")
      end

      # Tooltip wrapping a button
      tooltip("demo_tooltip", "This is a tooltip", position: :top) do
        button("tooltip_target", "Hover me for tooltip")
      end

      # Image
      image("demo_image", "/assets/placeholder.png", width: 120, height: 80)

      # SVG
      svg("demo_svg", "/assets/icon.svg", width: 24, height: 24)

      # Markdown with settings
      markdown(
        "demo_markdown",
        "## Markdown\n\nSome **bold** and *italic* text.\n\n- Item one\n- Item two"
      )

      # Rich text with styled spans
      rich_text("demo_rich_text", [
        {text: "Bold text ", weight: :bold, size: 16},
        {text: "italic text ", style: :italic},
        {text: "normal text "},
        {text: "colored text", color: "#e74c3c"}
      ])

      # Canvas with geometric shapes
      canvas("demo_canvas", width: 200, height: 150) do
        layer("default") do
          canvas_rect(10, 10, 80, 60, fill: "#3498db")
          canvas_circle(150, 75, 40, fill: "#e74c3c")
          canvas_line(10, 130, 190, 130, stroke: "#2ecc71", stroke_width: 2)
        end
      end
    end
  end

  def composite_tab(model)
    column(spacing: 8) do
      text("composite_heading", "Interactive & Composite Widgets", size: 18)

      # Mouse area wrapping content -- detects hover enter/exit
      mouse_area("demo_mouse_area", on_enter: true, on_exit: true) do
        container("mouse_area_box", padding: 12) do
          text("Mouse area: #{model.mouse_area_status}")
        end
      end

      # Sensor detecting pointer events
      sensor("demo_sensor") do
        container("sensor_box", padding: 12) do
          text("Sensor: #{model.sensor_status}")
        end
      end

      # Simulated tab switching using buttons and conditional content
      container("demo_tabs") do
        column(spacing: 4) do
          row(spacing: 4) do
            button("tab_one", "Tab One")
            button("tab_two", "Tab Two")
          end

          if model.demo_tabs_active == "tab_one"
            text("Tab one content")
          else
            text("Tab two content")
          end
        end
      end

      # Modal simulation using container with visible prop
      button("show_modal", "Show Modal")

      if model.modal_visible
        container("demo_modal", padding: 16) do
          column(spacing: 8) do
            text("Modal Content")
            button("hide_modal", "Close")
          end
        end
      end

      # Collapsible panel simulation
      button("demo_panel", model.panel_collapsed ? "Expand Panel" : "Collapse Panel")

      unless model.panel_collapsed
        container("panel_content", padding: 8) do
          text("Panel content that can be collapsed")
        end
      end

      # Counter demonstrating click events updating model
      row(spacing: 8) do
        button("counter_btn", "Click me")
        text("Clicked #{model.click_count} times")
      end

      # PaneGrid with multiple panes
      pane_grid("demo_panes", spacing: 2) do
        container("pane_left", padding: 8) do
          column do
            text("Left pane")
            text("Navigation or file tree")
          end
        end

        container("pane_right", padding: 8) do
          column do
            text("Right pane")
            text("Main editor area")
          end
        end
      end

      # Table with columns and rows
      table("demo_table",
        columns: [
          {key: "name", label: "Name"},
          {key: "lang", label: "Language"},
          {key: "stars", label: "Stars"}
        ],
        rows: [
          {"name" => "Phoenix", "lang" => "Elixir", "stars" => "20k"},
          {"name" => "Iced", "lang" => "Rust", "stars" => "24k"},
          {"name" => "React", "lang" => "JavaScript", "stars" => "220k"}
        ])
    end
  end
end

Plushie.run(Catalog) if __FILE__ == $PROGRAM_NAME
