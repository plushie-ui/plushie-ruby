# frozen_string_literal: true

require "test_helper"
require "rake"
Rake::TaskManager.record_task_metadata = true
require "plushie/package"
require "plushie/rake"

class TestRakeTasks < Minitest::Test
  def setup
    @original_artifacts = Plushie.configuration.artifacts
    @original_bin_file = Plushie.configuration.bin_file
    @original_bin_env = ENV.delete("PLUSHIE_BIN_FILE")
    @original_package_env = package_env_names.to_h { |name| [name, ENV[name]] }
  end

  def teardown
    Plushie.configuration.artifacts = @original_artifacts
    Plushie.configuration.bin_file = @original_bin_file
    if @original_bin_env
      ENV["PLUSHIE_BIN_FILE"] = @original_bin_env
    else
      ENV.delete("PLUSHIE_BIN_FILE")
    end
    restore_package_env
    Rake::Task["plushie:download"].reenable
    Rake::Task["plushie:package"].reenable
  end

  def test_download_task_exists
    assert Rake::Task.task_defined?("plushie:download"),
      "plushie:download task should be defined"
  end

  def test_build_task_exists
    assert Rake::Task.task_defined?("plushie:build"),
      "plushie:build task should be defined"
  end

  def test_run_task_exists
    assert Rake::Task.task_defined?("plushie:run"),
      "plushie:run task should be defined"
  end

  def test_inspect_task_exists
    assert Rake::Task.task_defined?("plushie:inspect"),
      "plushie:inspect task should be defined"
  end

  def test_script_task_exists
    assert Rake::Task.task_defined?("plushie:script"),
      "plushie:script task should be defined"
  end

  def test_replay_task_exists
    assert Rake::Task.task_defined?("plushie:replay"),
      "plushie:replay task should be defined"
  end

  def test_preflight_task_exists
    assert Rake::Task.task_defined?("plushie:preflight"),
      "plushie:preflight task should be defined"
  end

  def test_package_task_exists
    assert Rake::Task.task_defined?("plushie:package"),
      "plushie:package task should be defined"
  end

  def test_download_task_has_description
    desc = Rake::Task["plushie:download"].comment
    assert_includes desc, "Download"
  end

  def test_build_task_has_description
    desc = Rake::Task["plushie:build"].comment
    assert_includes desc, "Build"
  end

  def test_script_task_has_description
    desc = Rake::Task["plushie:script"].comment
    assert_includes desc, "script"
  end

  def test_connect_task_exists
    assert Rake::Task.task_defined?("plushie:connect"),
      "plushie:connect task should be defined"
  end

  def test_replay_task_has_description
    desc = Rake::Task["plushie:replay"].comment
    assert_includes desc, "Replay"
  end

  def test_connect_task_has_description
    desc = Rake::Task["plushie:connect"].comment
    assert_includes desc, "Connect"
  end

  def test_package_task_has_description
    desc = Rake::Task["plushie:package"].comment
    assert_includes desc, "package"
  end

  def test_package_task_accepts_common_package_args
    task = Rake::Task["plushie:package"]
    assert_includes task.arg_names, :app_id
    assert_includes task.arg_names, :app_name
    assert_includes task.arg_names, :app_version
  end

  def test_download_task_accepts_args
    task = Rake::Task["plushie:download"]
    assert_includes task.arg_names, :arg1
  end

  def test_run_task_accepts_options
    task = Rake::Task["plushie:run"]
    assert_includes task.arg_names, :app_class
    assert_includes task.arg_names, :opt1
  end

  def test_preflight_task_has_description
    desc = Rake::Task["plushie:preflight"].comment
    assert_includes desc, "CI"
  end

  def test_download_task_skips_existing_custom_bin_file
    Dir.mktmpdir do |tmpdir|
      bin_file = File.join(tmpdir, "plushie-renderer")
      File.write(bin_file, "existing")
      Plushie.configuration.artifacts = [:bin]
      Plushie.configuration.bin_file = bin_file

      download_called = false
      stdout, = capture_io do
        Plushie::Binary.stub(:download!, ->(**_) {
          download_called = true
          raise "download should not be called"
        }) do
          Rake::Task["plushie:download"].invoke
        end
      end

      refute download_called
      assert_includes stdout, "Binary already exists at #{bin_file}. Use force to re-download."
    end
  end

  def test_download_task_force_redownloads_existing_custom_bin_file
    Dir.mktmpdir do |tmpdir|
      bin_file = File.join(tmpdir, "plushie-renderer")
      File.write(bin_file, "existing")
      Plushie.configuration.artifacts = [:bin]
      Plushie.configuration.bin_file = bin_file

      downloaded_dest = nil
      Plushie::Binary.stub(:download!, ->(dest: nil, **_) {
        downloaded_dest = dest
        dest
      }) do
        capture_io do
          Rake::Task["plushie:download"].invoke("force")
        end
      end

      assert_equal bin_file, downloaded_dest
    end
  end

  def test_package_task_prints_env_configured_portable_command
    result = {
      archive_path: "dist/payload.tar.zst",
      manifest_path: "dist/plushie-package.toml"
    }

    with_package_env(
      "PLUSHIE_PACKAGE_PORTABLE_OUT" => "dist/notes",
      "PLUSHIE_PACKAGE_STRICT_TOOLS" => "true"
    ) do
      with_package_method(:build_from_env, result) do
        with_package_method(:verify_strict_package_tools!, nil) do
          stdout, = capture_io do
            Rake::Task["plushie:package"].invoke("dev.plushie.notes")
          end

          assert_includes stdout, "Build launcher with:"
          assert_includes(
            stdout,
            "  bin/plushie package portable --manifest dist/plushie-package.toml --out dist/notes --strict-tools"
          )
        end
      end
    end
  end

  def test_package_task_runs_env_configured_portable_command
    result = {
      archive_path: "dist/payload.tar.zst",
      manifest_path: "dist/plushie-package.toml"
    }
    captured = nil

    with_package_env(
      "PLUSHIE_PACKAGE_PORTABLE" => "true",
      "PLUSHIE_PACKAGE_PORTABLE_OUT" => "dist/notes",
      "PLUSHIE_PACKAGE_STRICT_TOOLS" => "true"
    ) do
      with_package_method(:build_from_env, result) do
        with_package_method(:verify_strict_package_tools!, nil) do
          with_package_method(:run!, ->(command) { captured = command }) do
            capture_io do
              Rake::Task["plushie:package"].invoke("dev.plushie.notes")
            end
          end
        end
      end
    end

    assert_equal [
      "bin/plushie",
      "package",
      "portable",
      "--manifest",
      "dist/plushie-package.toml",
      "--out",
      "dist/notes",
      "--strict-tools"
    ], captured
  end

  private

  def package_env_names
    [
      "PLUSHIE_PACKAGE_PORTABLE",
      "PLUSHIE_PACKAGE_PORTABLE_OUT",
      "PLUSHIE_PACKAGE_STRICT_TOOLS"
    ]
  end

  def with_package_env(values)
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    restore_package_env
  end

  def restore_package_env
    @original_package_env.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end

  def with_package_method(name, implementation)
    singleton = Plushie::Package.singleton_class
    had_original = singleton.method_defined?(name)
    original = singleton.instance_method(name) if had_original
    singleton.send(:remove_method, name) if had_original
    if implementation.respond_to?(:call)
      singleton.define_method(name, implementation)
    else
      singleton.define_method(name) { |*_args, **_kwargs| implementation }
    end
    yield
  ensure
    singleton.send(:remove_method, name)
    singleton.define_method(name, original) if had_original
  end
end
