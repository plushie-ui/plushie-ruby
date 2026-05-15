# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class TestBinary < Minitest::Test
  B = Plushie::Binary

  def test_os_name
    os = B.os_name
    assert_includes %w[linux darwin windows], os
  end

  def test_arch_name
    arch = B.arch_name
    assert_includes %w[x86_64 aarch64], arch
  end

  def test_binary_name
    name = B.binary_name
    assert_includes ["plushie-renderer", "plushie-renderer.exe"], name
  end

  def test_release_name
    name = B.release_name
    assert_match(/\Aplushie-renderer-(linux|darwin|windows)-(x86_64|aarch64)/, name)
  end

  def test_release_url
    url = B.release_url("0.4.1")
    assert_match(%r{\Ahttps://github\.com/plushie-ui/plushie-renderer/releases/}, url)
    assert_includes url, "0.4.1"
  end

  def test_resolve_returns_nil_without_binary
    # Don't set PLUSHIE_BINARY_PATH, don't download
    # resolve should return nil or a valid path
    result = B.resolve
    assert(result.nil? || File.exist?(result))
  end

  def test_resolve_does_not_use_path
    Dir.mktmpdir do |tmpdir|
      binary = File.join(tmpdir, "plushie")
      File.write(binary, "renderer")
      File.chmod(0o755, binary)

      with_env("PATH" => tmpdir, "PLUSHIE_BINARY_PATH" => nil) do
        B.stub(:custom_build_path, nil) do
          B.stub(:downloaded_path, nil) do
            assert_nil B.resolve
          end
        end
      end
    end
  end

  def test_resolve_does_not_use_sibling_rust_checkout
    Dir.mktmpdir do |tmpdir|
      binary = File.join(tmpdir, "target", "release", "plushie-renderer")
      FileUtils.mkdir_p(File.dirname(binary))
      File.write(binary, "renderer")
      File.chmod(0o755, binary)

      with_env("PLUSHIE_RUST_SOURCE_PATH" => tmpdir, "PLUSHIE_BINARY_PATH" => nil) do
        B.stub(:custom_build_path, nil) do
          B.stub(:downloaded_path, nil) do
            assert_nil B.resolve
          end
        end
      end
    end
  end

  private

  def with_env(values)
    previous = values.transform_values { nil }
    values.each_key { |key| previous[key] = ENV[key] }
    values.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
    yield
  ensure
    previous.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end
end
