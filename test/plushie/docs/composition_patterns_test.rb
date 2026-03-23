# frozen_string_literal: true

require "test_helper"

class DocsCompositionPatternsTest < Minitest::Test
  # -- Tab bar from composition-patterns.md --

  class TabApp
    include Plushie::App

    Model = Plushie::Model.define(:active_tab)

    def init(_opts) = Model.new(active_tab: :overview)

    def update(model, event)
      case event
      in Event::Widget[type: :click, id: /\Atab:(.+)\z/]
        model.with(active_tab: $1.to_sym)
      else
        model
      end
    end

    def view(model)
      tabs = [:overview, :details, :settings]

      window("main", title: "Tab Demo") do
        column(width: :fill) do
          row(spacing: 0) do
            tabs.each do |tab|
              button("tab:#{tab}", tab.to_s.capitalize,
                style: tab_style(model.active_tab == tab),
                padding: {top: 10, bottom: 10, left: 20, right: 20})
            end
          end

          rule

          container("content", padding: 20, width: :fill, height: :fill) do
            text("Content for #{model.active_tab}")
          end
        end
      end
    end

    private

    def tab_style(active)
      if active
        Plushie::Type::StyleMap::Spec.new(
          background: "#ffffff",
          text_color: "#1a1a1a",
          border: Plushie::Type::Border::Spec.new(color: "#0066ff", width: 2, radius: 0)
        )
      else
        Plushie::Type::StyleMap::Spec.new(
          background: "#f0f0f0",
          text_color: "#666666",
          hovered: {background: "#e0e0e0"}
        )
      end
    end
  end

  def test_tab_bar_init
    app = TabApp.new
    model = app.init({})
    assert_equal :overview, model.active_tab
  end

  def test_tab_bar_click_changes_tab
    app = TabApp.new
    model = app.init({})
    model = app.update(model, Plushie::Event::Widget.new(type: :click, id: "tab:settings"))
    assert_equal :settings, model.active_tab
  end

  def test_tab_bar_view_tree
    app = TabApp.new
    model = app.init({})
    tree = Plushie::Tree.normalize(app.view(model)).first

    assert_equal "window", tree.type
    column = tree.children.first
    assert_equal "column", column.type

    row_node = column.children.first
    assert_equal "row", row_node.type

    tab_ids = row_node.children.map(&:id)
    assert_includes tab_ids, "tab:overview"
    assert_includes tab_ids, "tab:details"
    assert_includes tab_ids, "tab:settings"
  end

  def test_tab_bar_active_style_has_border
    app = TabApp.new
    style = app.send(:tab_style, true)
    assert_instance_of Plushie::Type::StyleMap::Spec, style
    assert_equal "#ffffff", style.background
    refute_nil style.border
  end

  # -- Sidebar navigation from composition-patterns.md --

  class SidebarApp
    include Plushie::App

    NAV_ITEMS = [[:inbox, "Inbox"], [:sent, "Sent"], [:drafts, "Drafts"], [:trash, "Trash"]]

    Model = Plushie::Model.define(:page)

    def init(_opts) = Model.new(page: :inbox)

    def update(model, event)
      case event
      in Event::Widget[type: :click, id: /\Anav:(.+)\z/]
        model.with(page: $1.to_sym)
      else
        model
      end
    end

    def view(model)
      window("main", title: "Sidebar Demo") do
        row(width: :fill, height: :fill) do
          container("sidebar", width: 200, height: :fill, background: "#1e1e2e", padding: 8) do
            column(spacing: 4, width: :fill) do
              text("nav_label", "Navigation", size: 12, color: "#888888")
              space(height: 8)

              NAV_ITEMS.each do |id, label|
                button("nav:#{id}", label,
                  style: nav_item_style(model.page == id),
                  width: :fill,
                  padding: {top: 8, bottom: 8, left: 12, right: 12})
              end
            end
          end

          container("main", width: :fill, height: :fill, padding: 24) do
            text("page_title", "#{model.page.to_s.capitalize} page", size: 20)
          end
        end
      end
    end

    private

    def nav_item_style(selected)
      if selected
        Plushie::Type::StyleMap::Spec.new(
          background: "#3366ff",
          text_color: "#ffffff",
          hovered: {background: "#4477ff"}
        )
      else
        Plushie::Type::StyleMap::Spec.new(
          background: "#1e1e2e",
          text_color: "#cccccc",
          hovered: {background: "#2a2a3e", text_color: "#ffffff"}
        )
      end
    end
  end

  def test_sidebar_init
    app = SidebarApp.new
    model = app.init({})
    assert_equal :inbox, model.page
  end

  def test_sidebar_nav_click
    app = SidebarApp.new
    model = app.init({})
    model = app.update(model, Plushie::Event::Widget.new(type: :click, id: "nav:drafts"))
    assert_equal :drafts, model.page
  end

  def test_sidebar_view_has_nav_buttons
    app = SidebarApp.new
    model = app.init({})
    tree = Plushie::Tree.normalize(app.view(model)).first

    sidebar = Plushie::Tree.find(tree, "sidebar")
    refute_nil sidebar
    assert_equal "container", sidebar.type

    nav_button = Plushie::Tree.find(tree, "sidebar/nav:inbox")
    refute_nil nav_button
    assert_equal "button", nav_button.type
  end

  def test_sidebar_page_title_updates
    app = SidebarApp.new
    model = app.init({})
    model = app.update(model, Plushie::Event::Widget.new(type: :click, id: "nav:trash"))
    tree = Plushie::Tree.normalize(app.view(model)).first

    title = Plushie::Tree.find(tree, "main/page_title")
    refute_nil title
    assert_equal "Trash page", title.props[:content]
  end

  # -- Modal dialog from composition-patterns.md --

  class ModalApp
    include Plushie::App

    Model = Plushie::Model.define(:show_modal, :confirmed)

    def init(_opts) = Model.new(show_modal: false, confirmed: false)

    def update(model, event)
      case event
      in Event::Widget[type: :click, id: "open_modal"]
        model.with(show_modal: true)
      in Event::Widget[type: :click, id: "confirm"]
        model.with(show_modal: false, confirmed: true)
      in Event::Widget[type: :click, id: "cancel"]
        model.with(show_modal: false)
      else
        model
      end
    end

    def view(model)
      window("main", title: "Modal Demo") do
        stack(width: :fill, height: :fill) do
          container("main", width: :fill, height: :fill, padding: 24, center: true) do
            column(spacing: 12, align_x: :center) do
              text("main_content", "Main application content", size: 20)

              if model.confirmed
                text("confirmed_msg", "Action confirmed.", color: "#22aa44")
              end

              button("open_modal", "Open Dialog", style: :primary)
            end
          end

          if model.show_modal
            container("overlay", width: :fill, height: :fill,
              background: "#00000088", center: true) do
              container("dialog", max_width: 400, padding: 24,
                background: "#ffffff",
                border: Plushie::Type::Border::Spec.new(color: "#dddddd", width: 1, radius: 8),
                shadow: Plushie::Type::Shadow::Spec.new(color: "#00000040", offset_x: 0, offset_y: 4, blur_radius: 16)) do
                column(spacing: 16) do
                  text("dialog_title", "Confirm action", size: 18, color: "#1a1a1a")
                  text("dialog_body", "Are you sure you want to proceed?",
                    color: "#555555", wrapping: :word)

                  row(spacing: 8, align_x: :end) do
                    button("cancel", "Cancel", style: :secondary)
                    button("confirm", "Confirm", style: :primary)
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  def test_modal_init_hidden
    app = ModalApp.new
    model = app.init({})
    refute model.show_modal
    refute model.confirmed
  end

  def test_modal_open_and_confirm
    app = ModalApp.new
    model = app.init({})
    model = app.update(model, Plushie::Event::Widget.new(type: :click, id: "open_modal"))
    assert model.show_modal

    model = app.update(model, Plushie::Event::Widget.new(type: :click, id: "confirm"))
    refute model.show_modal
    assert model.confirmed
  end

  def test_modal_cancel
    app = ModalApp.new
    model = app.init({})
    model = app.update(model, Plushie::Event::Widget.new(type: :click, id: "open_modal"))
    model = app.update(model, Plushie::Event::Widget.new(type: :click, id: "cancel"))
    refute model.show_modal
    refute model.confirmed
  end

  def test_modal_overlay_absent_when_closed
    app = ModalApp.new
    model = app.init({})
    tree = Plushie::Tree.normalize(app.view(model)).first

    assert_nil Plushie::Tree.find(tree, "overlay")
  end

  def test_modal_overlay_present_when_open
    app = ModalApp.new
    model = app.init({}).with(show_modal: true)
    tree = Plushie::Tree.normalize(app.view(model)).first

    overlay = Plushie::Tree.find(tree, "overlay")
    refute_nil overlay
    dialog = Plushie::Tree.find(tree, "overlay/dialog")
    refute_nil dialog

    title = Plushie::Tree.find(tree, "overlay/dialog/dialog_title")
    assert_equal "Confirm action", title.props[:content]
  end

  # -- Card helper from composition-patterns.md --

  class CardApp
    include Plushie::App

    Model = Plushie::Model.define(:status)

    def init(_opts) = Model.new(status: "All services operational")

    def update(model, _event) = model

    def view(model)
      window("main", title: "Card Demo") do
        column(padding: 24, spacing: 16, width: :fill) do
          card("info", "System status") do
            text("status_msg", model.status, color: "#22aa44")
            text("last_checked", "Last checked: 2 minutes ago", size: 12, color: "#888888")
          end
        end
      end
    end

    private

    def card(id, title, &block)
      border = Plushie::Type::Border::Spec.new(color: "#e0e0e0", width: 1, radius: 8)
      shadow = Plushie::Type::Shadow::Spec.new(color: "#00000020", offset_x: 0, offset_y: 2, blur_radius: 8)

      container(id, width: :fill, padding: 16, background: "#ffffff",
        border: border, shadow: shadow) do
        column(spacing: 8) do
          text("card_title", title, size: 16, color: "#1a1a1a")
          rule
          instance_exec(&block) if block
        end
      end
    end
  end

  def test_card_view_structure
    app = CardApp.new
    model = app.init({})
    tree = Plushie::Tree.normalize(app.view(model)).first

    card_container = Plushie::Tree.find(tree, "info")
    refute_nil card_container
    assert_equal "container", card_container.type

    card_title = Plushie::Tree.find(tree, "info/card_title")
    refute_nil card_title
    assert_equal "System status", card_title.props[:content]

    status_msg = Plushie::Tree.find(tree, "info/status_msg")
    refute_nil status_msg
    assert_equal "All services operational", status_msg.props[:content]
  end

  # -- State helpers from composition-patterns.md --

  def test_state_helper_animation_easing
    assert_equal 0.0, Plushie::Animation.ease_in(0.0)
    assert_equal 1.0, Plushie::Animation.ease_out(1.0)
    assert_in_delta 0.5, Plushie::Animation.ease_in_out(0.5), 0.001
  end

  def test_state_helper_route_push_pop
    route = Plushie::Route.new("/dashboard")
    assert_equal "/dashboard", Plushie::Route.current(route)

    route = Plushie::Route.push(route, "/settings", tab: "general")
    assert_equal "/settings", Plushie::Route.current(route)
    assert_equal({tab: "general"}, Plushie::Route.params(route))

    route = Plushie::Route.pop(route)
    assert_equal "/dashboard", Plushie::Route.current(route)
  end

  def test_state_helper_selection_toggle
    sel = Plushie::Selection.new(mode: :multi)
    sel = Plushie::Selection.select(sel, "item_1")
    sel = Plushie::Selection.select(sel, "item_3", extend: true)
    assert_equal Set["item_1", "item_3"], Plushie::Selection.selected(sel)

    sel = Plushie::Selection.toggle(sel, "item_1")
    assert_equal Set["item_3"], Plushie::Selection.selected(sel)
  end

  UndoModel = Plushie::Model.define(:name)

  def test_state_helper_undo_apply_and_undo
    model = UndoModel.new(name: "Alice")

    undo = Plushie::Undo.new(model)
    undo = Plushie::Undo.apply(undo, {
      apply: ->(m) { m.with(name: "Bob") },
      undo: ->(m) { m.with(name: "Alice") },
      label: "Rename to Bob"
    })
    assert_equal "Bob", Plushie::Undo.current(undo).name

    undo = Plushie::Undo.undo(undo)
    assert_equal "Alice", Plushie::Undo.current(undo).name

    undo = Plushie::Undo.redo(undo)
    assert_equal "Bob", Plushie::Undo.current(undo).name
  end
end
