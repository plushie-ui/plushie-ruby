# frozen_string_literal: true

module Plushie
  module Widget
    # Markdown display: renders parsed markdown content.
    #
    # @example
    #   md = Plushie::Widget::Markdown.new("docs", "# Hello\nWorld",
    #     text_size: 16)
    #   node = md.build
    #
    # Props:
    # - content (string): raw markdown text.
    # - width (length): container width.
    # - text_size (number): base text size in pixels.
    # - h1_size (number): heading 1 size in pixels.
    # - h2_size (number): heading 2 size in pixels.
    # - h3_size (number): heading 3 size in pixels.
    # - code_size (number): code block text size in pixels.
    # - spacing (number): spacing between elements in pixels.
    # - link_color (string): link color override.
    # - code_theme (string): syntax highlighting theme for code blocks.
    # - a11y (hash): accessibility overrides.
    class Markdown < BuiltIn
      wire_type :markdown
      default_a11y role: :document
      children :none
      positional :content, default: nil
      prop :content, :width, :text_size, :h1_size, :h2_size, :h3_size,
        :code_size, :spacing, :link_color, :code_theme, :a11y
    end
  end
end
