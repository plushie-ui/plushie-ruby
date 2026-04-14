# frozen_string_literal: true

module Plushie
  module Widget
    Table = Plushie::Widget.define(:table) do
      children :many
      prop :columns, :rows, :header, :separator, :separator_color,
        :width, :height, :padding, :sort_by, :sort_order,
        :header_text_size, :row_text_size
      default_a11y role: :table
    end

    # Data table with column definitions and optional sorting.
    #
    # @example
    #   table = Plushie::Widget::Table.new("users",
    #     columns: [{ key: "name", label: "Name" }, { key: "email", label: "Email" }],
    #     sort_by: "name", sort_order: :asc)
    #   node = table.build
    class Table
      # Row validation hooks applied via prepend.
      module RowValidation
        # Validate rows on construction and set_rows.
        # @api private
        def initialize(id, **opts)
          super
          validate_rows!(@rows, @columns) if @rows
        end

        # Override set_rows with validation.
        def set_rows(rows)
          validate_rows!(rows, @columns)
          dup.tap { |copy| copy.instance_variable_set(:@rows, rows) }
        end
      end
      prepend RowValidation

      private

      # Validate row data key types are consistent.
      def validate_rows!(rows, columns)
        return unless rows.is_a?(Array) && !rows.empty?

        col_key_type = nil
        if columns.is_a?(Array) && !columns.empty?
          first_col = columns[0]
          if first_col.is_a?(Hash)
            key_val = first_col[:key] || first_col["key"]
            col_key_type = key_val.is_a?(Symbol) ? :symbol : :string if key_val
          end
        end

        rows.each_with_index do |row, idx|
          next unless row.is_a?(Hash) && !row.empty?

          row_key_type = row.keys.first.is_a?(Symbol) ? :symbol : :string

          if col_key_type && row_key_type != col_key_type
            raise ArgumentError,
              "table #{@id.inspect} row #{idx} uses #{row_key_type} keys but columns use #{col_key_type} keys. " \
              "All keys must be the same type across columns and rows."
          end

          mixed = row.keys.any? { |k| (k.is_a?(Symbol) ? :symbol : :string) != row_key_type }
          if mixed
            raise ArgumentError,
              "table #{@id.inspect} row #{idx} has mixed key types. " \
              "Use all symbol keys or all string keys, not both."
          end
        end
      end
    end
  end
end
