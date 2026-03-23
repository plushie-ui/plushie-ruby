# frozen_string_literal: true

require "test_helper"
require "rake"
Rake::TaskManager.record_task_metadata = true
require "plushie/rake"

class TestRakeTasks < Minitest::Test
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

  def test_download_task_accepts_args
    task = Rake::Task["plushie:download"]
    assert_includes task.arg_names, :arg1
    assert_includes task.arg_names, :arg2
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
end
