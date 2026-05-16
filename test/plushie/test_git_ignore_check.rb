# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "plushie/git_ignore_check"

class TestGitIgnoreCheck < Minitest::Test
  def test_no_warning_outside_git_repo
    Dir.mktmpdir do |tmpdir|
      _out, err = run_in(tmpdir) do
        Plushie::GitIgnoreCheck.warn_if_unignored("bin")
      end
      assert_equal "", err
    end
  end

  def test_no_warning_when_path_is_gitignored
    with_git_repo do |repo|
      File.write(File.join(repo, ".gitignore"), "/bin/\n")
      _out, err = run_in(repo) do
        Plushie::GitIgnoreCheck.warn_if_unignored("bin")
      end
      assert_equal "", err
    end
  end

  def test_warns_when_path_not_gitignored
    with_git_repo do |repo|
      File.write(File.join(repo, ".gitignore"), "# nothing relevant\n")
      _out, err = run_in(repo) do
        Plushie::GitIgnoreCheck.warn_if_unignored("bin")
      end
      assert_includes err, "warning: bin/ is not in .gitignore."
      assert_includes err, "    /bin/"
    end
  end

  def test_warns_for_nested_path
    with_git_repo do |repo|
      File.write(File.join(repo, ".gitignore"), "")
      _out, err = run_in(repo) do
        Plushie::GitIgnoreCheck.warn_if_unignored("dist")
      end
      assert_includes err, "warning: dist/ is not in .gitignore."
      assert_includes err, "    /dist/"
    end
  end

  private

  def with_git_repo
    Dir.mktmpdir do |tmpdir|
      Dir.chdir(tmpdir) do
        system("git", "init", "-q", out: File::NULL, err: File::NULL)
        system("git", "config", "user.email", "test@example.com", out: File::NULL, err: File::NULL)
        system("git", "config", "user.name", "test", out: File::NULL, err: File::NULL)
      end
      yield tmpdir
    end
  end

  def run_in(dir)
    Dir.chdir(dir) do
      capture_io { yield }
    end
  end
end
