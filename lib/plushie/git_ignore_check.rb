# frozen_string_literal: true

require "open3"

module Plushie
  # Warns when a generated output directory is not gitignored.
  #
  # Used by the download and package rake tasks so developers don't
  # accidentally commit large generated artifacts (renderer binaries,
  # package payloads). Silent when not inside a git work tree or when
  # the path is already ignored.
  module GitIgnoreCheck
    module_function

    # Emit a warning to stderr if +path+ is inside a git work tree but
    # is not gitignored. No-op otherwise.
    #
    # @param path [String] project-relative path to check (e.g. "bin")
    # @return [void]
    def warn_if_unignored(path)
      return unless inside_work_tree?

      display = path.sub(%r{/+\z}, "")
      # Check against a trailing slash so directory-only patterns like
      # `/bin/` in .gitignore match even when the path doesn't exist
      # on disk yet (or exists as a file).
      return if ignored?("#{display}/")
      warn "warning: #{display}/ is not in .gitignore."
      warn "  Recommended: add the following line so generated artifacts don't end"
      warn "  up committed:"
      warn ""
      warn "      /#{display}/"
    end

    def inside_work_tree?
      _stdout, _stderr, status = Open3.capture3("git", "rev-parse", "--is-inside-work-tree")
      status.success?
    rescue SystemCallError
      false
    end

    def ignored?(path)
      _stdout, _stderr, status = Open3.capture3("git", "check-ignore", "-q", path)
      status.success?
    rescue SystemCallError
      false
    end
  end
end
