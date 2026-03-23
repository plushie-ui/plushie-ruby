# frozen_string_literal: true

require "test_helper"

class DocsThemingTest < Minitest::Test
  # Helper that includes the DSL for building trees in tests
  class Builder
    include Plushie::UI

    public(*Plushie::UI.private_instance_methods(false))
  end

  def setup
    @b = Builder.new
  end

  # -- Built-in theme names --

  def test_theming_builtin_dark
    assert_equal "dark", Plushie::Type::Theme.encode(:dark)
  end

  def test_theming_builtin_catppuccin_mocha
    assert_equal "catppuccin_mocha", Plushie::Type::Theme.encode(:catppuccin_mocha)
  end

  def test_theming_builtin_nord
    assert_equal "nord", Plushie::Type::Theme.encode(:nord)
  end

  def test_theming_builtin_light
    assert_equal "light", Plushie::Type::Theme.encode(:light)
  end

  def test_theming_builtin_all_valid
    Plushie::Type::Theme::BUILTIN.each do |name|
      encoded = Plushie::Type::Theme.encode(name)
      assert_equal name.to_s, encoded
    end
  end

  def test_theming_unknown_raises
    assert_raises(ArgumentError) { Plushie::Type::Theme.encode(:nonexistent) }
  end

  def test_theming_system
    assert_equal "system", Plushie::Type::Theme.encode(:system)
  end

  # -- Custom theme (hash palette) --

  def test_theming_custom_hash
    theme = {
      name: "my_app",
      background: "#1e1e2e",
      text: "#cdd6f4",
      primary: "#89b4fa",
      success: "#a6e3a1",
      danger: "#f38ba8",
      warning: "#f9e2af"
    }
    encoded = Plushie::Type::Theme.encode(theme)
    assert_equal theme, encoded
  end

  def test_theming_custom_with_shade_overrides
    theme = {
      name: "branded",
      background: "#1a1a2e",
      text: "#e0e0e0",
      primary: "#0f3460",
      primary_strong: "#1a5276",
      primary_strong_text: "#ffffff",
      background_weakest: "#0d0d1a"
    }
    encoded = Plushie::Type::Theme.encode(theme)
    assert_equal "#1a5276", encoded[:primary_strong]
  end

  # -- Themer widget in tree --

  def test_theming_themer_widget
    node = @b.window("main", title: "My App") do
      @b.themer("theme", theme: :catppuccin_mocha) do
        @b.column do
          @b.text("Themed content")
        end
      end
    end
    tree = Plushie::Tree.normalize(node).first
    themer = tree.children.first
    assert_equal "themer", themer.type
    assert_equal "catppuccin_mocha", themer.props[:theme]
  end

  def test_theming_subtree_override
    node = @b.column do
      @b.text("Uses window theme")
      @b.themer("sidebar_theme", theme: :nord) do
        @b.container("sidebar") do
          @b.text("Uses Nord theme")
        end
      end
    end
    tree = Plushie::Tree.normalize(node).first
    themer = tree.children[1]
    assert_equal "themer", themer.type
    assert_equal "nord", themer.props[:theme]
  end

  # -- StyleMap construction --

  def test_theming_style_map_spec
    spec = Plushie::Type::StyleMap::Spec.new(
      background: "#ffffff",
      text_color: "#1a1a1a",
      border: Plushie::Type::Border::Spec.new(radius: 8, width: 1, color: "#e0e0e0"),
      shadow: Plushie::Type::Shadow::Spec.new(color: "#00000020", offset_x: 0, offset_y: 2, blur_radius: 8)
    )
    wire = spec.to_wire
    assert_equal "#ffffff", wire[:background]
    assert_equal "#1a1a1a", wire[:text_color]
    assert_equal "#e0e0e0", wire[:border][:color]
    assert_equal 8, wire[:border][:radius]
    assert_equal 1, wire[:border][:width]
    assert_equal "#00000020", wire[:shadow][:color]
    assert_equal [0, 2], wire[:shadow][:offset]
    assert_equal 8, wire[:shadow][:blur_radius]
  end

  def test_theming_style_map_with_status_overrides
    spec = Plushie::Type::StyleMap::Spec.new(
      background: "#00000000",
      text_color: "#cccccc",
      hovered: {background: "#333333", text_color: "#ffffff"},
      pressed: {background: "#222222"},
      disabled: {text_color: "#666666"}
    )
    wire = spec.to_wire
    assert_equal "#333333", wire[:hovered][:background]
    assert_equal "#ffffff", wire[:hovered][:text_color]
    assert_equal "#222222", wire[:pressed][:background]
    assert_equal "#666666", wire[:disabled][:text_color]
  end

  # -- Per-widget style prop (named preset) --

  def test_theming_button_style_preset
    node = @b.button("save", "Save", style: :primary)
    tree = Plushie::Tree.normalize(node).first
    assert_equal "primary", tree.props[:style]
  end

  def test_theming_button_style_danger
    node = @b.button("delete", "Delete", style: :danger)
    tree = Plushie::Tree.normalize(node).first
    assert_equal "danger", tree.props[:style]
  end

  # -- Per-widget style prop (StyleMap spec) --

  def test_theming_container_with_style_map
    spec = Plushie::Type::StyleMap::Spec.new(
      background: "#ffffff",
      text_color: "#1a1a1a"
    )
    node = @b.container("card", style: spec) do
      @b.text("Card content")
    end
    tree = Plushie::Tree.normalize(node).first
    assert_kind_of Hash, tree.props[:style]
    assert_equal "#ffffff", tree.props[:style]["background"]
    assert_equal "#1a1a1a", tree.props[:style]["text_color"]
  end

  # -- Settings with theme --

  def test_theming_settings_hash
    settings = {theme: :system}
    assert_equal :system, settings[:theme]
  end

  # -- System theme via themer --

  def test_theming_system_themer
    node = @b.window("main", title: "My App") do
      @b.themer("sys_theme", theme: :system) do
        @b.text("content")
      end
    end
    tree = Plushie::Tree.normalize(node).first
    themer = tree.children.first
    assert_equal "system", themer.props[:theme]
  end
end
