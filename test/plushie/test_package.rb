# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "plushie/package"

class TestPackage < Minitest::Test
  P = Plushie::Package

  def test_normalize_package_target
    assert_equal "linux-x86_64", P.normalize_package_target("Linux", "x86_64")
    assert_equal "darwin-aarch64", P.normalize_package_target("Darwin", "arm64")
    assert_equal "windows-x86_64", P.normalize_package_target("Windows", "AMD64")
  end

  def test_rejects_unknown_package_target_parts
    assert_raises(Plushie::Error) { P.normalize_package_target("plan9", "x86_64") }
    assert_raises(Plushie::Error) { P.normalize_package_target("linux", "riscv64") }
  end

  def test_manifest_for_payload_records_hash_size_and_sdk_metadata
    Dir.mktmpdir do |tmpdir|
      archive = File.join(tmpdir, "payload.tar.zst")
      File.binwrite(archive, "payload")

      manifest = P.manifest_for_payload(
        app_id: "dev.plushie.test",
        app_name: "Test App",
        app_version: "0.1.0",
        target: "linux-x86_64",
        renderer_kind: "custom",
        renderer_source: "local-build",
        renderer_path: "bin/plushie-renderer",
        host_command: ["ruby/bin/ruby", "bin/connect"],
        working_dir: "app",
        payload_archive: archive
      )

      assert_equal 7, manifest.fetch(:payload_size)
      assert_equal 64, manifest.fetch(:payload_hash).length
      assert_equal "payload.tar.zst", manifest.fetch(:payload_archive)

      toml = P.render_manifest(manifest)
      assert_includes toml, 'app_name = "Test App"'
      assert_includes toml, 'host_sdk = "ruby"'
      assert_includes toml, "host_sdk_version = \"#{Plushie::VERSION}\""
      assert_includes toml, "plushie_rust_version = \"#{Plushie::PLUSHIE_RUST_VERSION}\""
      assert_includes toml, "protocol_version = #{Plushie::Protocol::PROTOCOL_VERSION}"
      assert_includes toml, 'renderer_path = "bin/plushie-renderer"'
      assert_includes toml, 'host_command = ["ruby/bin/ruby", "bin/connect"]'
      assert_includes toml, 'working_dir = "app"'
      assert_includes toml, 'kind = "custom"'
      assert_includes toml, 'source = "local-build"'
      assert_includes toml, 'archive = "payload.tar.zst"'
      assert_includes toml, "hash = \"sha256:#{manifest.fetch(:payload_hash)}\""
    end
  end

  def test_write_manifest_creates_parent_directories
    Dir.mktmpdir do |tmpdir|
      archive = File.join(tmpdir, "payload.tar.zst")
      File.binwrite(archive, "payload")
      manifest = P.manifest_for_payload(
        app_id: "dev.plushie.test",
        app_version: "0.1.0",
        target: "linux-x86_64",
        renderer_path: "bin/plushie-renderer",
        host_command: ["bin/connect"],
        payload_archive: archive
      )

      output = File.join(tmpdir, "dist", "package", "plushie-package.toml")
      P.write_manifest(output, manifest)

      assert_equal P.render_manifest(manifest), File.read(output)
    end
  end

  def test_resolve_renderer_records_explicit_paths_as_local_paths
    Dir.mktmpdir do |tmpdir|
      renderer = File.join(tmpdir, "plushie-renderer")
      write_executable(renderer)

      result = P.resolve_renderer!(path: renderer)

      assert_equal "local-path", result.fetch(:source)
      assert_equal renderer, result.fetch(:source_path)
    end
  end

  def test_resolve_renderer_preserves_explicit_source
    Dir.mktmpdir do |tmpdir|
      renderer = File.join(tmpdir, "plushie-renderer")
      write_executable(renderer)

      result = P.resolve_renderer!(path: renderer, source: "test-fixture")

      assert_equal "test-fixture", result.fetch(:source)
    end
  end

  def test_resolve_renderer_records_environment_paths_as_local_paths
    Dir.mktmpdir do |tmpdir|
      renderer = File.join(tmpdir, "plushie-renderer")
      write_executable(renderer)

      with_env("PLUSHIE_BINARY_PATH" => renderer) do
        result = P.resolve_renderer!

        assert_equal "local-path", result.fetch(:source)
        assert_equal renderer, result.fetch(:source_path)
      end
    end
  end

  def test_resolve_renderer_records_source_builds_as_local_builds
    Dir.mktmpdir do |tmpdir|
      renderer = File.join(tmpdir, "target", "release", "plushie-renderer")
      write_executable(renderer)

      with_env("PLUSHIE_RUST_SOURCE_PATH" => tmpdir, "PLUSHIE_BINARY_PATH" => nil) do
        P.stub(:renderer_from_source_path, renderer) do
          result = P.resolve_renderer!

          assert_equal "local-build", result.fetch(:source)
          assert_equal renderer, result.fetch(:source_path)
        end
      end
    end
  end

  private

  def write_executable(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#!/bin/sh\nexit 0\n")
    FileUtils.chmod(0o755, path)
  end

  def with_env(values)
    old_values = values.to_h { |key, _value| [key, ENV[key]] }
    values.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
    yield
  ensure
    old_values.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end
end
