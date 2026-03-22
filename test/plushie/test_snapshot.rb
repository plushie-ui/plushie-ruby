# frozen_string_literal: true

require "test_helper"
require "plushie/test"
require "tmpdir"
require "digest"
require "json"

class TestSnapshot < Minitest::Test
  include Plushie::Test::Snapshot

  # Stub session and assert_equal for snapshot module tests.
  # The snapshot module calls assert_equal from Minitest via the including class.

  # -- assert_tree_snapshot: first run writes the file --------------------

  def test_tree_snapshot_creates_golden_file_on_first_run
    Dir.mktmpdir do |dir|
      path = File.join(dir, "snapshots", "counter.json")
      tree = {"id" => "root", "type" => "column", "children" => []}

      assert_tree_snapshot(tree, path)

      assert File.exist?(path), "Expected golden file to be created"
      stored = JSON.parse(File.read(path))
      assert_equal tree, stored
    end
  end

  def test_tree_snapshot_passes_when_matching
    Dir.mktmpdir do |dir|
      path = File.join(dir, "counter.json")
      tree = {"id" => "root", "type" => "column"}

      # Write the golden file first
      assert_tree_snapshot(tree, path)
      # Second call should pass (same tree)
      assert_tree_snapshot(tree, path)
    end
  end

  def test_tree_snapshot_fails_when_different
    Dir.mktmpdir do |dir|
      path = File.join(dir, "counter.json")
      tree1 = {"id" => "root", "type" => "column"}
      tree2 = {"id" => "root", "type" => "row"}

      assert_tree_snapshot(tree1, path)

      error = assert_raises(Minitest::Assertion) do
        assert_tree_snapshot(tree2, path)
      end
      assert_match(/Tree snapshot mismatch/, error.message)
    end
  end

  def test_tree_snapshot_updates_when_env_set
    Dir.mktmpdir do |dir|
      path = File.join(dir, "counter.json")
      tree1 = {"id" => "root", "type" => "column"}
      tree2 = {"id" => "root", "type" => "row"}

      assert_tree_snapshot(tree1, path)

      with_env("PLUSHIE_UPDATE_SNAPSHOTS" => "1") do
        assert_tree_snapshot(tree2, path)
      end

      stored = JSON.parse(File.read(path))
      assert_equal tree2, stored
    end
  end

  # -- _assert_golden_hash: internal helper tests -------------------------

  def test_golden_hash_creates_file_on_first_run
    Dir.mktmpdir do |dir|
      path = File.join(dir, "test.sha256")
      hash = "abc123def456"

      _assert_golden_hash(path, hash, update_env: "PLUSHIE_UPDATE_SNAPSHOTS")

      assert File.exist?(path)
      assert_equal hash, File.read(path).strip
    end
  end

  def test_golden_hash_passes_on_match
    Dir.mktmpdir do |dir|
      path = File.join(dir, "test.sha256")
      hash = "abc123def456"

      File.write(path, hash)
      _assert_golden_hash(path, hash, update_env: "PLUSHIE_UPDATE_SNAPSHOTS")
    end
  end

  def test_golden_hash_fails_on_mismatch
    Dir.mktmpdir do |dir|
      path = File.join(dir, "test.sha256")
      File.write(path, "old_hash")

      error = assert_raises(Minitest::Assertion) do
        _assert_golden_hash(path, "new_hash", update_env: "PLUSHIE_UPDATE_SNAPSHOTS")
      end
      assert_match(/Snapshot mismatch/, error.message)
    end
  end

  def test_golden_hash_updates_when_env_set
    Dir.mktmpdir do |dir|
      path = File.join(dir, "test.sha256")
      File.write(path, "old_hash")

      with_env("PLUSHIE_UPDATE_SNAPSHOTS" => "1") do
        _assert_golden_hash(path, "new_hash", update_env: "PLUSHIE_UPDATE_SNAPSHOTS")
      end

      assert_equal "new_hash", File.read(path).strip
    end
  end

  private

  def with_env(vars)
    saved = {}
    vars.each do |k, v|
      saved[k] = ENV[k]
      ENV[k] = v
    end
    yield
  ensure
    saved.each { |k, v| ENV[k] = v }
  end
end
