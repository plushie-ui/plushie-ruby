# frozen_string_literal: true

require "test_helper"

class TestData < Minitest::Test
  D = Plushie::DataQuery

  RECORDS = [
    {name: "Alice", age: 30, dept: "eng"},
    {name: "Bob", age: 25, dept: "eng"},
    {name: "Carol", age: 35, dept: "sales"},
    {name: "Dave", age: 28, dept: "sales"},
    {name: "Eve", age: 22, dept: "eng"}
  ].freeze

  def test_query_returns_all_by_default
    result = D.query(RECORDS)
    assert_equal RECORDS.length, result[:total]
    assert_equal RECORDS, result[:entries]
    assert_equal 1, result[:page]
    assert_equal 25, result[:page_size]
    assert_nil result[:groups]
  end

  def test_filter
    result = D.query(RECORDS, filter: ->(r) { r[:age] > 27 })
    assert_equal 3, result[:total]
    names = result[:entries].map { |r| r[:name] }
    assert_equal %w[Alice Carol Dave], names
  end

  def test_search
    result = D.query(RECORDS, search: [[:name], "al"])
    names = result[:entries].map { |r| r[:name] }
    assert_equal %w[Alice], names
  end

  def test_search_multiple_fields
    result = D.query(RECORDS, search: [[:name, :dept], "al"])
    names = result[:entries].map { |r| r[:name] }
    assert_includes names, "Alice"
    assert_includes names, "Carol"
    assert_includes names, "Dave"
  end

  def test_search_case_insensitive
    result = D.query(RECORDS, search: [[:name], "ALICE"])
    assert_equal 1, result[:total]
  end

  def test_sort_asc
    result = D.query(RECORDS, sort: [:asc, :name])
    names = result[:entries].map { |r| r[:name] }
    assert_equal %w[Alice Bob Carol Dave Eve], names
  end

  def test_sort_desc
    result = D.query(RECORDS, sort: [:desc, :age])
    ages = result[:entries].map { |r| r[:age] }
    assert_equal [35, 30, 28, 25, 22], ages
  end

  def test_sort_multiple_fields
    result = D.query(RECORDS, sort: [[:asc, :dept], [:desc, :age]])
    names = result[:entries].map { |r| r[:name] }
    assert_equal %w[Alice Bob Eve Carol Dave], names
  end

  def test_pagination
    result = D.query(RECORDS, page: 2, page_size: 2)
    assert_equal 5, result[:total]
    assert_equal 2, result[:entries].length
    assert_equal "Carol", result[:entries][0][:name]
    assert_equal "Dave", result[:entries][1][:name]
  end

  def test_pagination_last_page
    result = D.query(RECORDS, page: 3, page_size: 2)
    assert_equal 5, result[:total]
    assert_equal 1, result[:entries].length
    assert_equal "Eve", result[:entries][0][:name]
  end

  def test_pagination_beyond
    result = D.query(RECORDS, page: 10, page_size: 2)
    assert_equal 5, result[:total]
    assert_empty result[:entries]
  end

  def test_grouping
    result = D.query(RECORDS, group: :dept)
    assert_equal 2, result[:groups].keys.length
    assert_equal 3, result[:groups]["eng"].length
    assert_equal 2, result[:groups]["sales"].length
  end

  def test_pipeline_filter_sort_paginate
    result = D.query(RECORDS,
      filter: ->(r) { r[:dept] == "eng" },
      sort: [:asc, :age],
      page: 1,
      page_size: 2)

    assert_equal 3, result[:total]
    assert_equal 2, result[:entries].length
    assert_equal "Eve", result[:entries][0][:name]
    assert_equal "Bob", result[:entries][1][:name]
  end

  def test_empty_records
    result = D.query([])
    assert_equal 0, result[:total]
    assert_empty result[:entries]
  end
end
