# frozen_string_literal: true

require "test_helper"

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
    assert_match(/\Aplushie-(linux|darwin|windows)-(x86_64|aarch64)/, name)
  end

  def test_release_url
    url = B.release_url("0.4.1")
    assert_match(%r{\Ahttps://github\.com/plushie-ui/plushie/releases/}, url)
    assert_includes url, "0.4.1"
  end

  def test_which_finds_ruby
    path = B.which("ruby")
    refute_nil path
    assert File.executable?(path)
  end

  def test_which_returns_nil_for_nonexistent
    assert_nil B.which("definitely_not_a_real_command_#{rand(10000)}")
  end

  def test_resolve_returns_nil_without_binary
    # Don't set PLUSHIE_BINARY_PATH, don't download
    # resolve should return nil or a valid path
    result = B.resolve
    assert(result.nil? || File.exist?(result))
  end
end
