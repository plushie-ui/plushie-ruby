# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

module Plushie
  module Test
    # Snapshot and screenshot assertion helpers.
    #
    # Tree hash snapshots compare a SHA-256 hash captured by the renderer
    # against a golden file in test/snapshots/*.sha256. Screenshot
    # assertions do the same with pixel data hashes in
    # test/screenshots/*.sha256.
    #
    # First run creates the golden file. Set PLUSHIE_UPDATE_SNAPSHOTS=1
    # or PLUSHIE_UPDATE_SCREENSHOTS=1 to update existing golden files.
    #
    # @example Assert a tree hash snapshot in a test
    #   assert_tree_hash("counter_initial")
    #
    # @example Assert a screenshot (skipped on mock backend)
    #   assert_screenshot("counter_after_click")
    #
    # @example Assert a full tree snapshot as JSON
    #   assert_tree_snapshot(session.tree, "test/snapshots/counter.json")
    module Snapshot
      # Default directory for tree snapshot files.
      # @api private
      SNAPSHOTS_DIR = "test/snapshots"
      # Default directory for screenshot files.
      # @api private
      SCREENSHOTS_DIR = "test/screenshots"

      # Compare a tree hash from the renderer against a stored golden value.
      # On first run, writes the golden file. Set PLUSHIE_UPDATE_SNAPSHOTS=1
      # to overwrite.
      #
      # @param name [String] snapshot name (used as filename stem)
      def assert_tree_hash(name)
        response = session.tree_hash(name)
        hash = response[:hash] || response["hash"]
        raise "tree_hash returned no hash for #{name.inspect}" unless hash

        path = File.join(SNAPSHOTS_DIR, "#{name}.sha256")
        _assert_golden_hash(path, hash, update_env: "PLUSHIE_UPDATE_SNAPSHOTS")
      end

      # Compare a screenshot pixel hash against a stored golden value.
      # No-op on mock backend (screenshots are meaningless without rendering).
      #
      # @param name [String] screenshot name (used as filename stem)
      def assert_screenshot(name, **opts)
        return if Plushie::Test.backend == :mock

        response = session.screenshot(name, **opts)
        hash = response[:hash] || response["hash"]
        raise "screenshot returned no hash for #{name.inspect}" unless hash

        path = File.join(SCREENSHOTS_DIR, "#{name}.sha256")
        _assert_golden_hash(path, hash, update_env: "PLUSHIE_UPDATE_SCREENSHOTS")
      end

      # Compare a tree (as JSON) against a stored golden file.
      # On first run, writes the golden file. Set PLUSHIE_UPDATE_SNAPSHOTS=1
      # to overwrite.
      #
      # @param tree [Hash, Node] the tree to snapshot
      # @param path [String] path to the golden file (relative or absolute)
      def assert_tree_snapshot(tree, path)
        tree = strip_meta(tree) unless tree.is_a?(String)
        json = tree.is_a?(String) ? tree : JSON.pretty_generate(tree)
        hash = Digest::SHA256.hexdigest(json)

        if !File.exist?(path) || ENV["PLUSHIE_UPDATE_SNAPSHOTS"]
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, json)
        else
          stored = File.read(path)
          stored_hash = Digest::SHA256.hexdigest(stored)
          assert_equal stored_hash, hash,
            "Tree snapshot mismatch for #{path}. Run with PLUSHIE_UPDATE_SNAPSHOTS=1 to update."
        end
      end

      private

      # Strip :meta from tree structures before snapshotting.
      # Meta contains internal SDK bookkeeping (widget state, event specs)
      # that isn't sent over the wire.
      def strip_meta(tree)
        case tree
        when Plushie::Node
          Tree.node_to_wire(tree)
        when Hash
          result = tree.reject { |k, _| k == :meta || k == "meta" }
          result.transform_values { |v| strip_meta(v) }
        when Array
          tree.map { |v| strip_meta(v) }
        else
          tree
        end
      end

      def _assert_golden_hash(path, hash, update_env:)
        if !File.exist?(path) || ENV[update_env]
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, hash)
        else
          stored = File.read(path).strip
          assert_equal stored, hash,
            "Snapshot mismatch for #{path}. Run with #{update_env}=1 to update."
        end
      end
    end
  end
end
