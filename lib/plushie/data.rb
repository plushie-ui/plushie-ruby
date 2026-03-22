# frozen_string_literal: true

module Plushie
  # Query pipeline for in-memory record collections. Pure functions
  # supporting filter, search, sort, group, and pagination.
  #
  # All operations are applied in order: filter, search, sort, then paginate.
  # Grouping is applied to the paginated results.
  #
  # @example
  #   records = [
  #     { name: "Alice", age: 30 },
  #     { name: "Bob", age: 25 },
  #     { name: "Carol", age: 35 }
  #   ]
  #
  #   result = Plushie::Data.query(records,
  #     filter: ->(r) { r[:age] > 24 },
  #     sort: [:asc, :name],
  #     page: 1,
  #     page_size: 10
  #   )
  #
  #   result[:entries]  #=> all three records sorted by name
  #   result[:total]    #=> 3
  #
  module DataQuery
    # Queries a list of records with optional filtering, searching, sorting,
    # grouping, and pagination.
    #
    # @param records [Array<Hash>] the records to query
    # @param filter [Proc, nil] a proc that returns true for records to keep
    # @param search [Array, nil] a [fields, query_string] pair; fields is an
    #   array of hash keys to search; query_string is case-insensitive
    #   substring-matched
    # @param sort [Array, Array<Array>, nil] a [direction, field] pair or
    #   array of pairs. Direction is +:asc+ or +:desc+.
    # @param group [Object, nil] a hash key to group paginated results by
    # @param page [Integer] page number (1-based, default: 1)
    # @param page_size [Integer] records per page (default: 25)
    # @return [Hash] with keys :entries, :total, :page, :page_size, :groups
    def self.query(records, filter: nil, search: nil, sort: nil, group: nil, page: 1, page_size: 25)
      result = records
      result = result.select(&filter) if filter
      result = apply_search(result, search) if search
      result = apply_sort(result, sort) if sort

      total = result.length
      offset = (page - 1) * page_size
      entries = result[offset, page_size] || []

      groups = if group
        entries.group_by { |r| r[group] }
      end

      {entries: entries, total: total, page: page, page_size: page_size, groups: groups}
    end

    # @api private
    def self.apply_search(records, search)
      fields, query_string = search
      q = query_string.downcase

      records.select do |record|
        fields.any? do |field|
          record.fetch(field, "").to_s.downcase.include?(q)
        end
      end
    end

    # @api private
    def self.apply_sort(records, sort)
      # Normalize single spec to array of specs
      specs = if sort.is_a?(Array) && sort.first.is_a?(Array)
        sort
      else
        [sort]
      end

      records.sort do |a, b|
        compare_records(a, b, specs)
      end
    end

    # @api private
    def self.compare_records(a, b, specs)
      specs.each do |dir, field|
        va = a[field]
        vb = b[field]

        next if va == vb

        return dir == :asc ? compare_values(va, vb) : compare_values(vb, va)
      end

      0
    end

    # @api private
    def self.compare_values(a, b)
      (a.to_s <=> b.to_s) || 0
    end

    private_class_method :apply_search, :apply_sort, :compare_records, :compare_values
  end
end
