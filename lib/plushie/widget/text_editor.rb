# frozen_string_literal: true

module Plushie
  module Widget
    # Text editor -- multi-line editable text area.
    #
    # @example
    #   ed = Plushie::Widget::TextEditor.new("editor",
    #     content: "Hello", placeholder: "Type here...")
    #   node = ed.build
    #
    # Props:
    # - content (string) -- initial text content.
    # - placeholder (string) -- placeholder text.
    # - width (length) -- editor width.
    # - height (length) -- editor height.
    # - min_height (number) -- minimum height in pixels.
    # - max_height (number) -- maximum height in pixels.
    # - font (string|hash) -- font specification.
    # - size (number) -- font size in pixels.
    # - line_height (number|hash) -- line height.
    # - padding (number) -- uniform padding in pixels.
    # - wrapping (symbol) -- text wrapping mode.
    # - ime_purpose (string) -- IME input purpose: "normal", "secure", "terminal".
    # - highlight_syntax (string) -- language for syntax highlighting.
    # - highlight_theme (string) -- highlighter theme.
    # - style (symbol|hash) -- named style or style map.
    # - key_bindings (array of hashes) -- declarative key binding rules.
    # - placeholder_color (string) -- placeholder text color.
    # - selection_color (string) -- selection highlight color.
    # - a11y (hash) -- accessibility overrides.
    class TextEditor
      PROPS = %i[content placeholder width height min_height max_height font
        size line_height padding wrapping ime_purpose highlight_syntax
        highlight_theme style key_bindings placeholder_color selection_color
        a11y].freeze

      attr_reader :id, *PROPS

      # @param id [String] widget identifier
      # @param opts [Hash] optional properties
      def initialize(id, **opts)
        @id = id.to_s
        PROPS.each { |k| instance_variable_set(:"@#{k}", opts[k]) if opts.key?(k) }
      end

      PROPS.each do |prop|
        define_method(:"set_#{prop}") do |value|
          dup.tap { _1.instance_variable_set(:"@#{prop}", value) }
        end
      end

      # @return [Plushie::Node]
      def build
        props = {}
        PROPS.each do |key|
          val = instance_variable_get(:"@#{key}")
          Build.put_if(props, key, val)
        end
        Node.new(id: @id, type: "text_editor", props: props)
      end
    end
  end
end
