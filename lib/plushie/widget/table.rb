# frozen_string_literal: true

module Plushie
  module Widget
    # Table: data table with column definitions and optional sorting.
    #
    # @example
    #   table = Plushie::Widget::Table.new("users",
    #     columns: [{ key: "name", label: "Name" }, { key: "email", label: "Email" }],
    #     sort_by: "name", sort_order: :asc)
    #   node = table.build
    #
    # Props:
    # - columns (array of hashes): column definitions (key, label, width, sortable, align).
    # - rows (array of hashes): data rows with keys matching column key values.
    #   Each map should include an "id" key for stable row identity.
    # - header (boolean): show header row. Default: true.
    # - separator (number): divider line thickness in pixels. Set to 0.0 to hide.
    # - separator_color (string): divider line color.
    # - width (length): table width. Default: fill.
    # - height (length): table height. Wraps in a scrollable when set.
    # - padding (number|hash): cell internal padding.
    # - sort_by (string): column key to sort by.
    # - sort_order (symbol): :asc or :desc.
    # - header_text_size (number): header row text size in pixels.
    # - row_text_size (number): body row text size in pixels.
    # - event_rate (integer): max events per second for coalescable events.
    # - a11y (hash): accessibility overrides.
    class Table < BuiltIn
      wire_type :table
      children :many
      prop :columns, :rows, :header, :separator, :separator_color,
        :width, :height, :padding, :sort_by, :sort_order,
        :header_text_size, :row_text_size, :event_rate, :a11y

      # Validation and override hooks applied via prepend so they
      # wrap the generated methods rather than being overwritten.
      module RowValidation
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
      # Both symbol and string keys are accepted in row data, but they
      # must match the column key value types. Column definitions always
      # use the :key field to declare which data key to look up.
      def validate_rows!(rows, columns)
        return unless rows.is_a?(Array) && !rows.empty?

        # Determine expected key type from column :key values
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

          # Check consistency within the row
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
