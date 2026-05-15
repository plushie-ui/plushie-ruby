# frozen_string_literal: true

require "test_helper"
require "rake"
Rake::TaskManager.record_task_metadata = true
require "plushie/rake"

class TestRakeTasks < Minitest::Test
  def setup
    @original_artifacts = Plushie.configuration.artifacts
    @original_bin_file = Plushie.configuration.bin_file
    @original_bin_env = ENV.delete("PLUSHIE_BIN_FILE")
  end

  def teardown
    Plushie.configuration.artifacts = @original_artifacts
    Plushie.configuration.bin_file = @original_bin_file
    if @original_bin_env
      ENV["PLUSHIE_BIN_FILE"] = @original_bin_env
    else
      ENV.delete("PLUSHIE_BIN_FILE")
    end
    Rake::Task["plushie:download"].reenable
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
end
