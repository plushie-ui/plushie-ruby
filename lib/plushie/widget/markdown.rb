# frozen_string_literal: true

module Plushie
  module Widget
    # Markdown display -- renders parsed markdown content.
    #
    # @example
    #   md = Plushie::Widget::Markdown.new("docs", "# Hello\nWorld",
    #     text_size: 16)
    #   node = md.build
    #
    # Props:
    # - content (string) -- raw markdown text.
    # - width (length) -- container width.
    # - text_size (number) -- base text size in pixels.
    # - h1_size (number) -- heading 1 size in pixels.
    # - h2_size (number) -- heading 2 size in pixels.
    # - h3_size (number) -- heading 3 size in pixels.
    # - code_size (number) -- code block text size in pixels.
    # - spacing (number) -- spacing between elements in pixels.
    # - link_color (string) -- link color override.
    # - code_theme (string) -- syntax highlighting theme for code blocks.
    # - a11y (hash) -- accessibility overrides.
    class Markdown
      PROPS = %i[content width text_size h1_size h2_size h3_size code_size
        spacing link_color code_theme a11y].freeze

      attr_reader :id, *PROPS

      # @param id [String] widget identifier
      # @param content [String] raw markdown text
      # @param opts [Hash] optional properties
      def initialize(id, content = nil, **opts)
        @id = id.to_s
        @content = content
        PROPS.each { |k| instance_variable_set(:"@#{k}", opts[k]) if opts.key?(k) }
        @content = opts[:content] if opts.key?(:content)
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
        Node.new(id: @id, type: "markdown", props: props)
      end
    end
  end
end
