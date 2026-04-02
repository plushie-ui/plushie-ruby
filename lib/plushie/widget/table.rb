# frozen_string_literal: true

module Plushie
  module Widget
    # Table -- data table with column definitions and optional sorting.
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
    class Table < BuiltIn
      wire_type :table
      children :many
      prop :columns, :rows, :header, :separator, :width, :padding,
        :sort_by, :sort_order, :header_text_size, :row_text_size,
        :cell_spacing, :row_spacing, :separator_thickness,
        :separator_color, :a11y

      # Validation and override hooks applied via prepend so they
      # wrap the generated methods rather than being overwritten.
      module RowValidation
        def initialize(id, **opts)
          super
          validate_row_keys!(@rows) if @rows
        end

        # Override set_rows with string key validation.
        def set_rows(rows)
          validate_row_keys!(rows)
          dup.tap { |copy| copy.instance_variable_set(:@rows, rows) }
        end
      end
      prepend RowValidation

      private

      def validate_row_keys!(rows)
        return unless rows.is_a?(Array) && !rows.empty? && rows[0].is_a?(Hash)
        sym_key = rows[0].keys.find { |k| k.is_a?(Symbol) }
        return unless sym_key
        raise ArgumentError,
          "table #{@id.inspect} row maps must use string keys to match column key values, " \
          "got symbol key #{sym_key.inspect}. " \
          "Use {#{sym_key.to_s.inspect} => value} instead of {#{sym_key}: value}"
      end
    end
  end
end
