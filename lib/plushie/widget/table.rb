# frozen_string_literal: true

module Plushie
  module Widget
    # Table -- data table with column definitions and optional sorting.
    #
    # A container widget: child nodes represent row content.
    # Use {#push} to add children immutably.
    #
    # @example
    #   table = Plushie::Widget::Table.new("users",
    #     columns: [{ key: "name", label: "Name" }, { key: "email", label: "Email" }],
    #     sort_by: "name", sort_order: :asc)
    #   node = table.build
    #
    # Props:
    # - columns (array of hashes) -- column definitions (key, label, width).
    # - rows (array) -- row data.
    # - header (boolean) -- show header row.
    # - separator (boolean) -- show row separators.
    # - width (length) -- table width.
    # - padding (number|hash) -- cell padding.
    # - sort_by (string) -- column key to sort by.
    # - sort_order (symbol) -- :asc or :desc.
    # - header_text_size (number) -- header font size.
    # - row_text_size (number) -- row font size.
    # - cell_spacing (number) -- horizontal spacing between cells.
    # - row_spacing (number) -- vertical spacing between rows.
    # - separator_thickness (number) -- separator line thickness.
    # - separator_color (string) -- separator colour.
    # - a11y (hash) -- accessibility overrides.
    class Table
      # Supported property keys for the table widget.
      PROPS = %i[columns rows header separator width padding sort_by sort_order
        header_text_size row_text_size cell_spacing row_spacing
        separator_thickness separator_color a11y].freeze

      # @!parse
      #   attr_reader :id, :children, :columns, :rows, :header, :separator, :width, :padding, :sort_by, :sort_order, :header_text_size, :row_text_size, :cell_spacing, :row_spacing, :separator_thickness, :separator_color, :a11y
      class_eval { attr_reader :id, :children, *PROPS }

      # @param id [String] widget identifier
      # @param opts [Hash] optional properties matching PROPS keys
      def initialize(id, **opts)
        @id = id.to_s
        @children = opts.delete(:children) || []
        PROPS.each { |k| instance_variable_set(:"@#{k}", opts[k]) if opts.key?(k) }
      end

      PROPS.each do |prop|
        define_method(:"set_#{prop}") do |value|
          dup.tap { _1.instance_variable_set(:"@#{prop}", value) }
        end
      end

      # Append a child node. Returns a new Table (immutable).
      #
      # @param child [Object] child widget or node
      # @return [Table]
      def push(child)
        dup.tap { _1.instance_variable_set(:@children, @children + [child]) }
      end

      # @return [Plushie::Node]
      def build
        props = {}
        PROPS.each do |key|
          val = instance_variable_get(:"@#{key}")
          Build.put_if(props, key, val)
        end
        Node.new(id: @id, type: "table", props: props,
          children: Build.children_to_nodes(@children))
      end
    end
  end
end
