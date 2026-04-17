# frozen_string_literal: true

module Plushie
  module Widget
    # Text editor: multi-line editable text area.
    #
    # @example
    #   ed = Plushie::Widget::TextEditor.new("editor",
    #     content: "Hello", placeholder: "Type here...")
    #   node = ed.build
    #
    # Props:
    # - content (string): initial text content.
    # - placeholder (string): placeholder text.
    # - width (length): editor width.
    # - height (length): editor height.
    # - min_height (number): minimum height in pixels.
    # - max_height (number): maximum height in pixels.
    # - font (string|hash): font specification.
    # - size (number): font size in pixels.
    # - line_height (number|hash): line height.
    # - padding (number): uniform padding in pixels.
    # - wrapping (symbol): text wrapping mode.
    # - input_purpose (string): input purpose hint: "normal", "secure", "terminal", "number", "decimal", "phone", "email", "url", "search".
    # - highlight_syntax (string): language for syntax highlighting.
    # - highlight_theme (string): highlighter theme.
    # - style (symbol|hash): named style or style map.
    # - key_bindings (array of hashes): declarative key binding rules.
    # - placeholder_color (string): placeholder text color.
    # - selection_color (string): selection highlight color.
    TextEditor = Plushie::Widget.define(:text_editor) do
      children :none
      prop :content, :placeholder, :width, :height, :min_height, :max_height,
        :font, :size, :line_height, :padding, :wrapping, :input_purpose,
        :highlight_syntax, :highlight_theme, :style, :key_bindings,
        :placeholder_color, :selection_color,
        :required, :validation
      default_a11y role: :multiline_text_input, label_from: :placeholder
    end
  end
end
