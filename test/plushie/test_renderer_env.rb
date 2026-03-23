# frozen_string_literal: true

require "test_helper"

class TestRendererEnv < Minitest::Test
  RE = Plushie::RendererEnv

  def test_allowed_exact_vars
    assert RE.allowed?("DISPLAY")
    assert RE.allowed?("PATH")
    assert RE.allowed?("HOME")
    assert RE.allowed?("RUST_LOG")
    assert RE.allowed?("WAYLAND_DISPLAY")
    assert RE.allowed?("XDG_RUNTIME_DIR")
    assert RE.allowed?("WGPU_BACKEND")
  end

  def test_allowed_prefix_vars
    assert RE.allowed?("LC_ALL")
    assert RE.allowed?("LC_CTYPE")
    assert RE.allowed?("MESA_GL_VERSION_OVERRIDE")
    assert RE.allowed?("VK_ICD_FILENAMES")
    assert RE.allowed?("FONTCONFIG_PATH")
    assert RE.allowed?("AT_SPI_BUS_ADDRESS")
    assert RE.allowed?("GALLIUM_DRIVER")
  end

  def test_disallowed_vars
    refute RE.allowed?("DATABASE_URL")
    refute RE.allowed?("AWS_SECRET_ACCESS_KEY")
    refute RE.allowed?("STRIPE_SECRET_KEY")
    refute RE.allowed?("GITHUB_TOKEN")
    refute RE.allowed?("REDIS_URL")
    refute RE.allowed?("SECRET_KEY_BASE")
    refute RE.allowed?("API_KEY")
  end

  def test_build_sets_rust_log
    env = RE.build(log_level: :debug)
    assert_equal "plushie=debug", env["RUST_LOG"]
  end

  def test_build_default_rust_log_is_error
    env = RE.build
    assert_equal "plushie=error", env["RUST_LOG"]
  end

  def test_build_sets_rust_backtrace
    env = RE.build
    assert_equal "1", env["RUST_BACKTRACE"]
  end

  def test_build_preserves_allowed_vars
    # PATH should always be in the environment
    env = RE.build
    refute_nil env["PATH"]
    assert_equal ENV["PATH"], env["PATH"]
  end

  def test_build_unsets_disallowed_vars
    # Set a sensitive var temporarily and verify it's unset
    original = ENV["PLUSHIE_TEST_SECRET"]
    ENV["PLUSHIE_TEST_SECRET"] = "hunter2"
    begin
      env = RE.build
      assert_nil env["PLUSHIE_TEST_SECRET"], "sensitive var should be nil (unset)"
    ensure
      if original
        ENV["PLUSHIE_TEST_SECRET"] = original
      else
        ENV.delete("PLUSHIE_TEST_SECRET")
      end
    end
  end

  def test_build_returns_hash
    env = RE.build
    assert_kind_of Hash, env
  end

  def test_rust_log_levels
    assert_equal "off", RE.build(log_level: :off)["RUST_LOG"]
    assert_equal "plushie=warn", RE.build(log_level: :warning)["RUST_LOG"]
    assert_equal "plushie=warn", RE.build(log_level: :warn)["RUST_LOG"]
    assert_equal "plushie=info", RE.build(log_level: :info)["RUST_LOG"]
    assert_equal "plushie=trace", RE.build(log_level: :trace)["RUST_LOG"]
  end
end
