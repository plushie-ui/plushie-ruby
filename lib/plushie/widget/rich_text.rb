# frozen_string_literal: true

module Plushie
  module Widget
    # Rich text display with individually styled spans.
    #
    # @example
    #   rt = Plushie::Widget::RichText.new("msg",
    #     spans: [
    #       Plushie::Widget::RichText::Span.new(text: "Hello "),
    #       Plushie::Widget::RichText::Span.new(text: "World", color: "#f00", underline: true)
    #     ])
    #   node = rt.build
    #
    # Props:
    # - spans (array): list of Span instances or plain hashes.
    # - width (length): widget width.
    # - height (length): widget height.
    # - size (number): default font size.
    # - font (string|hash): default font.
    # - color (string): default text color.
    # - line_height (number|hash): line height.
    # - wrapping (symbol): text wrapping mode.
    # - ellipsis (symbol): text ellipsis mode: :none, :start, :middle, or :end.
    RichText = Plushie::Widget.define(:rich_text) do
      children :none
      prop :spans, :width, :height, :size, :font, :color, :line_height,
        :wrapping
      prop :ellipsis, type: {enum: %i[none start middle end]}
      prop :a11y, :event_rate
      default_a11y role: :label
    end

    # A typed span for the rich_text widget.
    #
    # Each Span carries one segment of text with optional styling.
    # Construct with the keyword form and immutably copy with +with+
    # to derive variants:
    #
    #   ok = Plushie::Widget::RichText::Span.new(text: "ok",
    #          color: "#22aa22", underline: true)
    #   bold_ok = ok.with(text: "BOLD OK")
    #
    # Spans encode to wire-format hashes via #to_wire; unset fields
    # are omitted so the renderer falls back to the rich_text
    # widget's defaults.
    RichText::Span = Data.define(
      :text, :size, :font, :color, :line_height, :link,
      :underline, :strikethrough, :padding, :highlight
    ) do
      def initialize(text:, size: nil, font: nil, color: nil, line_height: nil,
        link: nil, underline: nil, strikethrough: nil, padding: nil, highlight: nil)
        super
      end

      # Return a copy with the given fields updated.
      def with(**changes)
        self.class.new(**to_h.merge(changes))
      end

      # Wire encoding: snake_case keys, omit unset fields.
      def to_wire
        out = {text: text}
        out[:size] = size unless size.nil?
        out[:font] = Type::Font.encode(font) unless font.nil?
        out[:color] = Type::Color.cast(color) unless color.nil?
        out[:line_height] = Type::LineHeight.encode(line_height) unless line_height.nil?
        out[:link] = link unless link.nil?
        out[:underline] = underline unless underline.nil?
        out[:strikethrough] = strikethrough unless strikethrough.nil?
        out[:padding] = Type::Padding.encode(padding) unless padding.nil?
        out[:highlight] = encode_highlight(highlight) unless highlight.nil?
        out
      end

      private

      def encode_highlight(value)
        case value
        when Hash
          h = {}
          h[:background] = Type::Color.cast(value[:background]) if value[:background]
          h[:border] = Type::Border.encode(value[:border]) if value[:border]
          h
        else
          value
        end
      end
    end
  end
end
