# frozen_string_literal: true

require "test_helper"

class DocsLayoutTest < Minitest::Test
  # Helper that includes the DSL for building trees in tests
  class Builder
    include Plushie::UI

    public(*Plushie::UI.private_instance_methods(false))
  end

  def setup
    @b = Builder.new
  end

  # -- Length values --

  def test_layout_length_fill
    tree = Plushie::Tree.normalize(@b.column(width: :fill) {}).first
    assert_equal "fill", tree.props[:width]
  end

  def test_layout_length_shrink
    tree = Plushie::Tree.normalize(
      @b.button("save", "Save", width: :shrink)
    ).first
    assert_equal "shrink", tree.props[:width]
  end

  def test_layout_length_fill_portion
    node = @b.container("left", width: [:fill_portion, 2]) {}
    tree = Plushie::Tree.normalize(node).first
    assert_equal ["fill_portion", 2], tree.props[:width]
  end

  def test_layout_length_fixed
    node = @b.container("sidebar", width: 250) {}
    tree = Plushie::Tree.normalize(node).first
    assert_equal 250, tree.props[:width]
  end

  # -- Padding values --

  def test_layout_padding_uniform
    node = @b.container("box", padding: 16) {}
    tree = Plushie::Tree.normalize(node).first
    assert_equal 16, tree.props[:padding]
  end

  def test_layout_padding_axis
    node = @b.container("box", padding: [8, 16]) {}
    tree = Plushie::Tree.normalize(node).first
    assert_equal [8, 16], tree.props[:padding]
  end

  def test_layout_padding_per_side
    node = @b.container("box", padding: {top: 0, right: 16, bottom: 8, left: 16}) {}
    tree = Plushie::Tree.normalize(node).first
    pad = tree.props[:padding]
    assert_equal 0, pad["top"]
    assert_equal 16, pad["right"]
    assert_equal 8, pad["bottom"]
    assert_equal 16, pad["left"]
  end

  # -- Column with spacing and padding --

  def test_layout_column_spacing_padding
    node = @b.column("main", spacing: 16, padding: 20, width: :fill, align_x: :center) do
      @b.text("title", "Title", size: 24)
      @b.text("subtitle", "Subtitle", size: 14)
    end
    tree = Plushie::Tree.normalize(node).first
    assert_equal "column", tree.type
    assert_equal 16, tree.props[:spacing]
    assert_equal 20, tree.props[:padding]
    assert_equal "fill", tree.props[:width]
    assert_equal "center", tree.props[:align_x]
    assert_equal 2, tree.children.length
    assert_equal "Title", tree.children[0].props[:content]
    assert_equal 24, tree.children[0].props[:size]
  end

  # -- Row with spacing --

  def test_layout_row_spacing
    node = @b.row(spacing: 8, align_y: :center) do
      @b.button("back", "<")
      @b.text("Page 1 of 5")
      @b.button("next", ">")
    end
    tree = Plushie::Tree.normalize(node).first
    assert_equal "row", tree.type
    assert_equal 8, tree.props[:spacing]
    assert_equal "center", tree.props[:align_y]
    assert_equal 3, tree.children.length
  end

  # -- Container with style --

  def test_layout_container_with_style
    node = @b.container("card", padding: 16, style: :rounded_box, width: :fill) do
      @b.column do
        @b.text("Card title")
        @b.text("Card content")
      end
    end
    tree = Plushie::Tree.normalize(node).first
    assert_equal "container", tree.type
    assert_equal 16, tree.props[:padding]
    assert_equal "rounded_box", tree.props[:style]
    assert_equal "fill", tree.props[:width]
    assert_equal 1, tree.children.length
    assert_equal "column", tree.children.first.type
  end

  # -- Scrollable with direction --

  def test_layout_scrollable
    node = @b.scrollable("list", height: 400, width: :fill) do
      @b.column(spacing: 4) do
        @b.text("item_1", "First")
        @b.text("item_2", "Second")
      end
    end
    tree = Plushie::Tree.normalize(node).first
    assert_equal "scrollable", tree.type
    assert_equal "list", tree.id
    assert_equal 400, tree.props[:height]
    assert_equal "fill", tree.props[:width]
  end

  # -- Stack --

  def test_layout_stack
    node = @b.stack do
      @b.image("bg", "background.png", width: :fill, height: :fill)
      @b.container("overlay", width: :fill, height: :fill, center: true) do
        @b.text("overlay_text", "Overlaid text", size: 48)
      end
    end
    tree = Plushie::Tree.normalize(node).first
    assert_equal "stack", tree.type
    assert_equal 2, tree.children.length
    assert_equal "image", tree.children[0].type
    assert_equal "container", tree.children[1].type
  end

  # -- Space --

  def test_layout_space
    node = @b.row do
      @b.text("Left")
      @b.space(width: :fill)
      @b.text("Right")
    end
    tree = Plushie::Tree.normalize(node).first
    assert_equal "row", tree.type
    assert_equal 3, tree.children.length
    assert_equal "space", tree.children[1].type
    assert_equal "fill", tree.children[1].props[:width]
  end

  # -- Grid --

  def test_layout_grid
    node = @b.grid("gallery", columns: 3, spacing: 8) do
      @b.image("img_1", "a.png", width: :fill)
      @b.image("img_2", "b.png", width: :fill)
      @b.image("img_3", "c.png", width: :fill)
    end
    tree = Plushie::Tree.normalize(node).first
    assert_equal "grid", tree.type
    assert_equal "gallery", tree.id
    assert_equal 3, tree.props[:columns]
    assert_equal 8, tree.props[:spacing]
    assert_equal 3, tree.children.length
  end

  # -- Common patterns: centered page --

  def test_layout_centered_page
    node = @b.container("page", width: :fill, height: :fill, center: true) do
      @b.column(spacing: 16, align_x: :center) do
        @b.text("welcome", "Welcome", size: 32)
        @b.button("start", "Get Started")
      end
    end
    tree = Plushie::Tree.normalize(node).first
    assert_equal "container", tree.type
    assert_equal true, tree.props[:center]
    assert_equal "fill", tree.props[:width]
    assert_equal "fill", tree.props[:height]

    col = tree.children.first
    assert_equal "column", col.type
    assert_equal 16, col.props[:spacing]
    assert_equal "center", col.props[:align_x]
  end

  # -- Common patterns: sidebar + content --

  def test_layout_sidebar_content
    node = @b.row(width: :fill, height: :fill) do
      @b.container("sidebar", width: 250, height: :fill, padding: 16) do
        @b.text("nav", "Navigation")
      end
      @b.container("content", width: :fill, height: :fill, padding: 16) do
        @b.text("main", "Main content")
      end
    end
    tree = Plushie::Tree.normalize(node).first
    assert_equal "row", tree.type
    assert_equal 2, tree.children.length

    sidebar = tree.children[0]
    assert_equal "container", sidebar.type
    assert_equal 250, sidebar.props[:width]

    content = tree.children[1]
    assert_equal "container", content.type
    assert_equal "fill", content.props[:width]
  end

  # -- Common patterns: header + body + footer --

  def test_layout_header_body_footer
    node = @b.column(width: :fill, height: :fill) do
      @b.container("header", width: :fill, padding: [8, 16]) do
        @b.text("h", "Header")
      end
      @b.scrollable("body", width: :fill, height: :fill) do
        @b.text("content", "Body")
      end
      @b.container("footer", width: :fill, padding: [8, 16]) do
        @b.text("f", "Footer")
      end
    end
    tree = Plushie::Tree.normalize(node).first
    assert_equal "column", tree.type
    assert_equal 3, tree.children.length

    header = tree.children[0]
    assert_equal "container", header.type
    assert_equal [8, 16], header.props[:padding]

    body = tree.children[1]
    assert_equal "scrollable", body.type
    assert_equal "fill", body.props[:height]

    footer = tree.children[2]
    assert_equal "container", footer.type
  end

  # -- Alignment --

  def test_layout_column_center_align
    node = @b.column(align_x: :center) do
      @b.text("Centered")
      @b.button("ok", "OK")
    end
    tree = Plushie::Tree.normalize(node).first
    assert_equal "center", tree.props[:align_x]
  end

  def test_layout_container_center_shorthand
    node = @b.container("page", width: :fill, height: :fill, center: true) do
      @b.text("Dead center")
    end
    tree = Plushie::Tree.normalize(node).first
    assert_equal true, tree.props[:center]
  end
end
